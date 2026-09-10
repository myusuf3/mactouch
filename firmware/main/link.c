#include "link.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "board.h"
#include "driver/gpio.h"
#include "esp_system.h"
#include "esp_private/periph_ctrl.h"
#include "soc/periph_defs.h"
#include "soc/rtc_cntl_reg.h"
#include "soc/soc.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "mbedtls/md.h"
#include "tusb.h"

#include "led.h"
#include "settings.h"
#include "touch.h"
#include "zw101.h"

#define LINK_LINE_MAX 256
#define IDENTIFY_DEFAULT_MS 15000
#define IDENTIFY_MAX_MS 120000

typedef enum { JOB_IDENTIFY, JOB_ENROLL, JOB_PAIR } job_kind_t;
typedef struct {
  job_kind_t kind;
  char args[LINK_LINE_MAX];
} job_t;

static QueueHandle_t jobs;
static volatile bool busy;
static volatile bool cancel_requested;
static bool pair_done;
static char final_reply[LINK_LINE_MAX];

// Stages the reply of a long-running command; the worker sends it after the
// command has released the sensor and cleared busy.
static void finish(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void finish(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(final_reply, sizeof(final_reply), fmt, ap);
  va_end(ap);
}

// GPIOs reported by the GPIO diagnostic, for confirming which pad a wire
// landed on. The sensor UART pins are left out.
static const int DIAG_PINS[] = {3, 4, 5, 6, 7, 8, 9, 43, 44};

// Every line leaves through this queue and is written by the console task.
// TinyUSB's class APIs are not safe to call from several tasks at once, and
// a write racing the USB task can leave the endpoint stuck until power cycle.
typedef struct { char text[LINK_LINE_MAX + 2]; } outbound_t;
static QueueHandle_t outbox;

void link_send(const char *fmt, ...) {
  outbound_t line;
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(line.text, LINK_LINE_MAX, fmt, ap);
  va_end(ap);
  if (n < 0) return;
  if (n > LINK_LINE_MAX - 1) n = LINK_LINE_MAX - 1;
  line.text[n++] = '\n';
  line.text[n] = '\0';
  if (!tud_cdc_connected() || !outbox) return;
  // A host that has stopped reading must not stall the sensor tasks.
  xQueueSend(outbox, &line, pdMS_TO_TICKS(20));
}

static void write_line(const char *text) {
  size_t n = strlen(text);
  size_t sent = 0;
  int64_t deadline = esp_timer_get_time() + 200000;
  while (sent < n && tud_cdc_connected() && esp_timer_get_time() < deadline) {
    uint32_t w = tud_cdc_write(text + sent, (uint32_t)(n - sent));
    if (w) sent += w; else vTaskDelay(1);
  }
  tud_cdc_write_flush();
}

bool link_busy(void) { return busy; }

// key=value lookup among space-separated tokens.
static bool arg(const char *args, const char *key, char *out, size_t cap) {
  size_t klen = strlen(key);
  const char *p = args;
  while (*p) {
    while (*p == ' ') p++;
    const char *end = strchr(p, ' ');
    size_t len = end ? (size_t)(end - p) : strlen(p);
    if (len > klen + 1 && strncmp(p, key, klen) == 0 && p[klen] == '=') {
      size_t vlen = len - klen - 1;
      if (vlen >= cap) vlen = cap - 1;
      memcpy(out, p + klen + 1, vlen);
      out[vlen] = '\0';
      return true;
    }
    if (!end) break;
    p = end;
  }
  return false;
}

// Nth space-separated token (0-based).
static bool token(const char *args, unsigned index, char *out, size_t cap) {
  const char *p = args;
  for (unsigned i = 0;; i++) {
    while (*p == ' ') p++;
    if (!*p) return false;
    const char *end = strchr(p, ' ');
    size_t len = end ? (size_t)(end - p) : strlen(p);
    if (i == index) {
      if (len >= cap) len = cap - 1;
      memcpy(out, p, len);
      out[len] = '\0';
      return true;
    }
    if (!end) return false;
    p = end;
  }
}

static bool parse_u32(const char *text, uint32_t max, uint32_t *out) {
  char *end = NULL;
  unsigned long v = strtoul(text, &end, 10);
  if (!*text || !end || *end || v > max) return false;
  *out = (uint32_t)v;
  return true;
}

static void hex_encode(const uint8_t *in, size_t len, char *out) {
  static const char digits[] = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    out[i * 2] = digits[in[i] >> 4];
    out[i * 2 + 1] = digits[in[i] & 0xf];
  }
  out[len * 2] = '\0';
}

static bool valid_nonce(char *nonce) {
  if (strlen(nonce) != 32) return false;
  for (char *c = nonce; *c; c++) {
    if (!isxdigit((unsigned char)*c)) return false;
    *c = (char)tolower((unsigned char)*c);
  }
  return true;
}

static bool sign_match(const char *nonce, uint16_t slot, char mac_hex[65]) {
  uint8_t key[32];
  settings_device_key(key);
  char material[64];
  snprintf(material, sizeof(material), "IDENTIFY|%s|%u", nonce, slot);
  uint8_t mac[32];
  const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  int rc = mbedtls_md_hmac(info, key, sizeof(key), (const uint8_t *)material,
                           strlen(material), mac);
  memset(key, 0, sizeof(key));
  if (rc != 0) return false;
  hex_encode(mac, sizeof(mac), mac_hex);
  return true;
}

static bool wait_lift(uint32_t timeout_ms) {
  int64_t deadline = esp_timer_get_time() + (int64_t)timeout_ms * 1000;
  unsigned absent = 0;
  while (esp_timer_get_time() < deadline && !cancel_requested) {
    int image = zw101_get_image();
    if (image == ZW101_CONFIRM_NO_FINGER) { if (++absent >= 3) return true; }
    else absent = 0;
    vTaskDelay(pdMS_TO_TICKS(80));
  }
  return false;
}

// Blocks until a finger is captured into `buffer`, the timeout passes, or a
// cancel arrives. Sets *reason on failure.
static bool capture(uint8_t buffer, uint32_t timeout_ms, const char **reason) {
  int64_t deadline = esp_timer_get_time() + (int64_t)timeout_ms * 1000;
  while (esp_timer_get_time() < deadline) {
    if (cancel_requested) { *reason = "cancelled"; return false; }
    int image = zw101_get_image();
    if (image == ZW101_CONFIRM_OK && zw101_gen_char(buffer)) return true;
    if (image < 0 && !zw101_recover()) { *reason = "sensor"; return false; }
    vTaskDelay(pdMS_TO_TICKS(60));
  }
  *reason = "timeout";
  return false;
}

static void run_identify(const char *args, bool pair) {
  const char *verb = pair ? "PAIR" : "IDENTIFY";
  char value[64];
  uint32_t timeout_ms = IDENTIFY_DEFAULT_MS;
  if (arg(args, "timeout", value, sizeof(value)) &&
      (!parse_u32(value, IDENTIFY_MAX_MS, &timeout_ms) || timeout_ms < 1000)) {
    finish("ERR %s reason=timeout_value", verb);
    return;
  }
  led_colour_t prompt = pair ? LED_WHITE : LED_BLUE;
  if (!pair && arg(args, "prompt", value, sizeof(value)) && !led_parse_colour(value, &prompt)) {
    finish("ERR %s reason=colour", verb);
    return;
  }
  char nonce[64] = "";
  bool have_nonce = arg(args, "nonce", nonce, sizeof(nonce));
  if (have_nonce && !valid_nonce(nonce)) {
    finish("ERR %s reason=nonce", verb);
    return;
  }
  if (pair && pair_done) {
    finish("ERR PAIR reason=already");
    return;
  }
  if (!zw101_lock(1000)) {
    finish("ERR %s reason=sensor", verb);
    return;
  }

  led_set(LED_MODE_BREATHE, prompt, prompt, 0);
  int64_t deadline = esp_timer_get_time() + (int64_t)timeout_ms * 1000;
  const char *reason = "timeout";
  bool matched = false;
  uint16_t slot = 0, score = 0;
  while (esp_timer_get_time() < deadline) {
    if (cancel_requested) { reason = "cancelled"; break; }
    int result = zw101_match_now(&slot, &score);
    if (result == 1) {
      matched = true;
      link_send("EVT MATCH slot=%u score=%u", slot, score);
      break;
    }
    if (result == 0) {
      link_send("EVT NOMATCH");
      led_set(LED_MODE_ON, LED_RED, LED_RED, 0);
      vTaskDelay(pdMS_TO_TICKS(350));
      led_set(LED_MODE_BREATHE, prompt, prompt, 0);
      wait_lift(2000);
      continue;
    }
    if (result < 0 && !zw101_recover()) { reason = "sensor"; break; }
    vTaskDelay(pdMS_TO_TICKS(60));
  }

  if (!matched) {
    led_idle();
    zw101_unlock();
    finish("ERR %s reason=%s", verb, reason);
    return;
  }

  if (pair) {
    uint8_t key[32];
    char key_hex[65];
    settings_device_key(key);
    hex_encode(key, sizeof(key), key_hex);
    memset(key, 0, sizeof(key));
    pair_done = true;
    finish("OK PAIR key=%s", key_hex);
    memset(key_hex, 0, sizeof(key_hex));
  } else if (have_nonce) {
    char mac_hex[65];
    if (sign_match(nonce, slot, mac_hex)) {
      finish("OK IDENTIFY slot=%u score=%u mac=%s", slot, score, mac_hex);
    } else {
      finish("ERR IDENTIFY reason=hmac");
    }
  } else {
    finish("OK IDENTIFY slot=%u score=%u", slot, score);
  }
  led_result(true);
  zw101_unlock();
}

static void run_enroll(const char *args) {
  char value[16];
  uint32_t slot = 0;
  if (!arg(args, "slot", value, sizeof(value)) || !parse_u32(value, ZW101_MAX_SLOTS, &slot) || slot < 1) {
    finish("ERR ENROLL reason=slot");
    return;
  }
  if (!zw101_lock(1000)) {
    finish("ERR ENROLL reason=sensor");
    return;
  }
  const char *reason = "failed";
  bool ok = false;
  led_set(LED_MODE_BREATHE, LED_BLUE, LED_BLUE, 0);
  link_send("EVT ENROLL step=touch");
  if (!capture(1, 15000, &reason)) goto done;
  link_send("EVT ENROLL step=lift");
  if (!wait_lift(10000)) { reason = cancel_requested ? "cancelled" : "timeout"; goto done; }
  vTaskDelay(pdMS_TO_TICKS(200));
  link_send("EVT ENROLL step=touch_again");
  if (!capture(2, 15000, &reason)) goto done;
  link_send("EVT ENROLL step=processing");
  ok = zw101_reg_model() && zw101_store(1, (uint16_t)slot);

done:
  if (ok) finish("OK ENROLL slot=%lu", (unsigned long)slot);
  else finish("ERR ENROLL reason=%s", reason);
  led_result(ok);
  zw101_unlock();
}

static void worker_task(void *arg_) {
  (void)arg_;
  job_t job;
  while (xQueueReceive(jobs, &job, portMAX_DELAY) == pdTRUE) {
    cancel_requested = false;
    final_reply[0] = '\0';
    switch (job.kind) {
      case JOB_IDENTIFY: run_identify(job.args, false); break;
      case JOB_PAIR: run_identify(job.args, true); break;
      case JOB_ENROLL: run_enroll(job.args); break;
    }
    busy = false;
    if (final_reply[0]) link_send("%s", final_reply);
    memset(final_reply, 0, sizeof(final_reply));
  }
}

static void submit(job_kind_t kind, const char *verb, const char *args) {
  if (busy) {
    link_send("ERR %s reason=busy", verb);
    return;
  }
  job_t job = {.kind = kind};
  strlcpy(job.args, args, sizeof(job.args));
  busy = true;
  if (xQueueSend(jobs, &job, 0) != pdTRUE) {
    busy = false;
    link_send("ERR %s reason=busy", verb);
  }
}

static void status(void) {
  int count = zw101_count();
  char ring[32];
  led_describe(ring, sizeof(ring));
  link_send("OK STATUS fw=%s proto=%d sensor=%s prints=%d touch=%s finger=%d watch=%s idle=%s ring=%s",
            MACTOUCH_FW_VERSION, MACTOUCH_PROTOCOL_VERSION,
            count >= 0 ? "ready" : "offline", count,
            settings_touch_source() == TOUCH_SOURCE_PIN ? "pin" : "poll",
            touch_present() ? 1 : 0, touch_watch() ? "on" : "off",
            led_colour_name(led_idle_colour()), ring);
}

static void led_command(const char *args) {
  char mode_name[16], c1[16], c2[16], cycles_text[8];
  led_mode_t mode;
  led_colour_t colour = LED_OFF, colour2 = LED_OFF;
  uint32_t cycles = 0;
  if (!token(args, 0, mode_name, sizeof(mode_name)) || !led_parse_mode(mode_name, &mode)) {
    link_send("ERR LED reason=mode");
    return;
  }
  if (mode != LED_MODE_OFF) {
    if (!token(args, 1, c1, sizeof(c1)) || !led_parse_colour(c1, &colour)) {
      link_send("ERR LED reason=colour");
      return;
    }
    colour2 = colour;
    if (token(args, 2, c2, sizeof(c2)) && !led_parse_colour(c2, &colour2)) {
      link_send("ERR LED reason=colour");
      return;
    }
    if (token(args, 3, cycles_text, sizeof(cycles_text)) && !parse_u32(cycles_text, 255, &cycles)) {
      link_send("ERR LED reason=cycles");
      return;
    }
  }
  link_send(led_set(mode, colour, colour2, (uint8_t)cycles) ? "OK LED" : "ERR LED reason=sensor");
}

static void slots(void) {
  uint32_t used = 0;
  if (!zw101_index_table(&used)) {
    link_send("ERR SLOTS reason=sensor");
    return;
  }
  char list[96] = "";
  size_t off = 0;
  for (unsigned slot = 1; slot <= ZW101_MAX_SLOTS; slot++) {
    if (!(used & (1u << slot))) continue;
    off += snprintf(list + off, sizeof(list) - off, "%s%u", off ? "," : "", slot);
  }
  link_send("OK SLOTS used=%s capacity=%d", list, ZW101_MAX_SLOTS);
}

static void gpio_diag(void) {
  char line[96] = "OK GPIO";
  size_t off = strlen(line);
  for (unsigned i = 0; i < sizeof(DIAG_PINS) / sizeof(DIAG_PINS[0]); i++) {
    off += snprintf(line + off, sizeof(line) - off, " %d=%d", DIAG_PINS[i], gpio_get_level(DIAG_PINS[i]));
  }
  link_send("%s", line);
}

// Asks the ROM to boot into download mode. This is the Arduino core's
// sequence: reset the USB controller, set the request, then reset only the
// CPU so the request register survives (a full system reset clears it). Run
// as a shutdown handler so esp_restart has already quiesced everything else.
// The ROM then serves download mode over USB-Serial/JTAG.
#ifdef MACTOUCH_EXPERIMENTAL_BOOTLOADER
static void request_download_boot(void) {
  periph_module_reset(PERIPH_USB_MODULE);
  periph_module_enable(PERIPH_USB_MODULE);
  REG_WRITE(RTC_CNTL_OPTION1_REG, RTC_CNTL_FORCE_DOWNLOAD_BOOT);
  SET_PERI_REG_MASK(RTC_CNTL_OPTIONS0_REG, RTC_CNTL_SW_PROCPU_RST_M);
  while (true) {}
}
#endif

static void handle(char *line) {
  char *args = strchr(line, ' ');
  if (args) *args++ = '\0'; else args = line + strlen(line);
  char value[16];
  led_colour_t colour;
  uint32_t number;

  if (strcmp(line, "PING") == 0) {
    link_send("OK PONG proto=%d fw=%s", MACTOUCH_PROTOCOL_VERSION, MACTOUCH_FW_VERSION);
  } else if (strcmp(line, "STATUS") == 0) {
    status();
  } else if (strcmp(line, "LED") == 0) {
    led_command(args);
  } else if (strcmp(line, "IDLE") == 0) {
    if (token(args, 0, value, sizeof(value)) && led_parse_colour(value, &colour)) {
      link_send(led_set_idle(colour) ? "OK IDLE" : "ERR IDLE reason=sensor");
    } else {
      link_send("ERR IDLE reason=colour");
    }
  } else if (strcmp(line, "WATCH") == 0) {
    if (strcmp(args, "on") == 0 || strcmp(args, "off") == 0) {
      touch_set_watch(args[1] == 'n');
      link_send("OK WATCH");
    } else {
      link_send("ERR WATCH reason=value");
    }
  } else if (strcmp(line, "TOUCH") == 0) {
    if (strcmp(args, "pin") == 0 || strcmp(args, "poll") == 0) {
      settings_set_touch_source(args[1] == 'i' ? TOUCH_SOURCE_PIN : TOUCH_SOURCE_POLL);
      link_send("OK TOUCH");
    } else {
      link_send("ERR TOUCH reason=value");
    }
  } else if (strcmp(line, "DELETE") == 0) {
    if (strcmp(args, "all") == 0) {
      link_send(zw101_delete_all() ? "OK DELETE" : "ERR DELETE reason=sensor");
    } else if (arg(args, "slot", value, sizeof(value)) && parse_u32(value, ZW101_MAX_SLOTS, &number) && number >= 1) {
      link_send(zw101_delete((uint16_t)number) ? "OK DELETE" : "ERR DELETE reason=sensor");
    } else {
      link_send("ERR DELETE reason=slot");
    }
  } else if (strcmp(line, "SLOTS") == 0) {
    slots();
  } else if (strcmp(line, "GPIO") == 0) {
    gpio_diag();
  } else if (strcmp(line, "IDENTIFY") == 0) {
    submit(JOB_IDENTIFY, "IDENTIFY", args);
  } else if (strcmp(line, "ENROLL") == 0) {
    submit(JOB_ENROLL, "ENROLL", args);
  } else if (strcmp(line, "PAIR") == 0) {
    submit(JOB_PAIR, "PAIR", args);
  } else if (strcmp(line, "CANCEL") == 0) {
    cancel_requested = true;
    link_send("OK CANCEL");
  } else if (strcmp(line, "BOOTLOADER") == 0) {
#ifdef MACTOUCH_EXPERIMENTAL_BOOTLOADER
    // The USB port belongs to TinyUSB while the app runs, so esptool cannot
    // toggle the chip into download mode itself. Ask the ROM to boot there.
    link_send("OK BOOTLOADER");
    vTaskDelay(pdMS_TO_TICKS(200));
    esp_register_shutdown_handler(request_download_boot);
    esp_restart();
#else
    // Neither documented sequence has worked on this board so far, and a
    // failed attempt leaves the USB link dead until a power cycle. Off until
    // it is understood; build with -DMACTOUCH_EXPERIMENTAL_BOOTLOADER to test.
    link_send("ERR BOOTLOADER reason=unsupported");
#endif
  } else if (strcmp(line, "REBOOT") == 0) {
    link_send("OK REBOOT");
    vTaskDelay(pdMS_TO_TICKS(200));
    esp_restart();
  } else {
    link_send("ERR COMMAND reason=unknown");
  }
}

static void console_task(void *arg_) {
  (void)arg_;
  char line[LINK_LINE_MAX];
  size_t len = 0;
  bool overflow = false;
  bool was_connected = false;
  uint8_t chunk[64];
  TickType_t next_beat = 0;
  bool beat = false;

  while (true) {
    // Heartbeat on the board LED: a stopped blink means this task is stuck; a
    // blink with a silent host means the USB link is the problem.
    TickType_t now = xTaskGetTickCount();
    if (now >= next_beat) {
      beat = !beat;
      gpio_set_level(BOARD_USER_LED_PIN, beat ? 0 : 1);
      next_beat = now + pdMS_TO_TICKS(beat ? 100 : 900);
    }
    outbound_t out;
    bool wrote = false;
    while (xQueueReceive(outbox, &out, 0) == pdTRUE) {
      write_line(out.text);
      wrote = true;
    }

    bool connected = tud_cdc_connected();
    if (connected && !was_connected) {
      vTaskDelay(pdMS_TO_TICKS(50));
      link_send("EVT READY fw=%s proto=%d", MACTOUCH_FW_VERSION, MACTOUCH_PROTOCOL_VERSION);
    }
    was_connected = connected;

    bool activity = false;
    while (tud_cdc_available()) {
      uint32_t n = tud_cdc_read(chunk, sizeof(chunk));
      activity = n > 0;
      for (uint32_t i = 0; i < n; i++) {
        char c = (char)chunk[i];
        if (c == '\r') continue;
        if (c != '\n') {
          if (len + 1 < sizeof(line)) line[len++] = c; else overflow = true;
          continue;
        }
        line[len] = '\0';
        if (overflow) link_send("ERR LINE reason=too_long");
        else if (len) handle(line);
        len = 0;
        overflow = false;
      }
    }
    if (!activity && !wrote) vTaskDelay(pdMS_TO_TICKS(5));
  }
}

void link_init(void) {
  outbox = xQueueCreate(32, sizeof(outbound_t));
  configASSERT(outbox);
  jobs = xQueueCreate(1, sizeof(job_t));
  configASSERT(jobs);

  uint64_t mask = 0;
  for (unsigned i = 0; i < sizeof(DIAG_PINS) / sizeof(DIAG_PINS[0]); i++) mask |= 1ULL << DIAG_PINS[i];
  gpio_config_t diag = {
    .pin_bit_mask = mask,
    .mode = GPIO_MODE_INPUT,
    .pull_down_en = GPIO_PULLDOWN_ENABLE,
    .intr_type = GPIO_INTR_DISABLE,
  };
  ESP_ERROR_CHECK(gpio_config(&diag));
  gpio_config_t led = {
    .pin_bit_mask = 1ULL << BOARD_USER_LED_PIN,
    .mode = GPIO_MODE_OUTPUT,
  };
  ESP_ERROR_CHECK(gpio_config(&led));
  gpio_set_level(BOARD_USER_LED_PIN, 1);

  configASSERT(xTaskCreate(worker_task, "link_worker", 6144, NULL, 3, NULL) == pdPASS);
  configASSERT(xTaskCreate(console_task, "link_console", 6144, NULL, 3, NULL) == pdPASS);
}

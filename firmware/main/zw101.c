#include "zw101.h"

#include <string.h>

#include "board.h"
#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

static const char *TAG = "zw101";
static const uart_port_t UART = BOARD_FP_UART_NUM;

static SemaphoreHandle_t lock;
static volatile bool ready;

static uint16_t checksum(uint8_t packet_id, const uint8_t *payload, size_t len) {
  uint16_t length = (uint16_t)(len + 2);
  uint32_t sum = packet_id + (length >> 8) + (length & 0xff);
  for (size_t i = 0; i < len; i++) sum += payload[i];
  return (uint16_t)sum;
}

static bool read_exact(uint8_t *out, size_t n, TickType_t deadline) {
  size_t got = 0;
  while (got < n) {
    TickType_t now = xTaskGetTickCount();
    if (now >= deadline) return false;
    int r = uart_read_bytes(UART, out + got, n - got, deadline - now);
    if (r > 0) got += (size_t)r;
  }
  return true;
}

// Sends one command packet and reads its acknowledgement. Data bytes after
// the confirm code are copied into `data` (at most *data_len, updated).
static bool command(uint8_t instruction, const uint8_t *params, size_t param_len,
                    uint8_t *confirm, uint8_t *data, size_t *data_len, uint32_t timeout_ms) {
  uint8_t drain[64];
  while (uart_read_bytes(UART, drain, sizeof(drain), 0) > 0) {}

  uint8_t payload[32];
  if (param_len + 1 > sizeof(payload)) return false;
  payload[0] = instruction;
  if (param_len) memcpy(payload + 1, params, param_len);
  size_t payload_len = param_len + 1;
  uint16_t length = (uint16_t)(payload_len + 2);
  uint16_t sum = checksum(0x01, payload, payload_len);
  uint8_t header[] = {0xef, 0x01, 0xff, 0xff, 0xff, 0xff, 0x01,
                      (uint8_t)(length >> 8), (uint8_t)length};
  uint8_t tail[] = {(uint8_t)(sum >> 8), (uint8_t)sum};
  if (uart_write_bytes(UART, header, sizeof(header)) != (int)sizeof(header) ||
      uart_write_bytes(UART, payload, payload_len) != (int)payload_len ||
      uart_write_bytes(UART, tail, sizeof(tail)) != (int)sizeof(tail)) {
    ready = false;
    return false;
  }

  TickType_t deadline = xTaskGetTickCount() + pdMS_TO_TICKS(timeout_ms);
  uint8_t head[9];
  // Resynchronise on the 0xEF01 start marker in case of stray bytes.
  size_t have = 0;
  while (have < 2) {
    if (!read_exact(head + have, 1, deadline)) { ready = false; return false; }
    if ((have == 0 && head[0] == 0xef) || (have == 1 && head[1] == 0x01)) have++;
    else have = 0;
  }
  if (!read_exact(head + 2, 7, deadline)) { ready = false; return false; }
  uint16_t resp_len = ((uint16_t)head[7] << 8) | head[8];
  uint8_t packet_id = head[6];
  if (resp_len < 3 || resp_len > 64) { ready = false; return false; }
  uint8_t body[64];
  if (!read_exact(body, resp_len, deadline)) { ready = false; return false; }
  size_t body_payload = resp_len - 2;
  uint16_t got = ((uint16_t)body[body_payload] << 8) | body[body_payload + 1];
  if (got != checksum(packet_id, body, body_payload) || packet_id != 0x07) {
    ESP_LOGW(TAG, "bad response: id=0x%02x len=%u", packet_id, resp_len);
    ready = false;
    return false;
  }
  ready = true;
  *confirm = body[0];
  if (data && data_len) {
    size_t n = body_payload - 1;
    if (n > *data_len) n = *data_len;
    memcpy(data, body + 1, n);
    *data_len = n;
  }
  return true;
}

static bool simple(uint8_t instruction, const uint8_t *params, size_t param_len, uint32_t timeout_ms) {
  if (!zw101_lock(2000)) return false;
  uint8_t confirm = 0xff;
  bool ok = command(instruction, params, param_len, &confirm, NULL, NULL, timeout_ms) &&
            confirm == ZW101_CONFIRM_OK;
  zw101_unlock();
  return ok;
}

static bool verify(void) {
  uint8_t password[4] = {0};
  return simple(0x13, password, sizeof(password), 1500);
}

bool zw101_lock(uint32_t timeout_ms) {
  return xSemaphoreTakeRecursive(lock, pdMS_TO_TICKS(timeout_ms)) == pdTRUE;
}

void zw101_unlock(void) { xSemaphoreGiveRecursive(lock); }

bool zw101_ready(void) { return ready; }

bool zw101_recover(void) {
  if (!zw101_lock(3000)) return false;
  uart_flush_input(UART);
  bool ok = false;
  for (int attempt = 0; attempt < 3 && !ok; attempt++) {
    ok = verify();
    if (!ok) vTaskDelay(pdMS_TO_TICKS(100));
  }
  zw101_unlock();
  return ok;
}

bool zw101_led(uint8_t function, uint8_t start_colour, uint8_t end_colour, uint8_t cycles) {
  uint8_t params[] = {function, start_colour, end_colour, cycles};
  return simple(0x3c, params, sizeof(params), 1000);
}

int zw101_get_image(void) {
  if (!zw101_lock(1000)) return -1;
  uint8_t confirm = 0xff;
  bool ok = command(0x01, NULL, 0, &confirm, NULL, NULL, 600);
  zw101_unlock();
  return ok ? confirm : -1;
}

bool zw101_gen_char(uint8_t buffer) {
  return simple(0x02, &buffer, 1, 2000);
}

bool zw101_search(uint8_t buffer, uint16_t *slot, uint16_t *score, bool *error) {
  *error = false;
  if (!zw101_lock(1000)) { *error = true; return false; }
  uint8_t params[] = {buffer, 0x00, 0x01, 0x00, ZW101_MAX_SLOTS};
  uint8_t data[4];
  size_t len = sizeof(data);
  uint8_t confirm = 0xff;
  bool answered = command(0x04, params, sizeof(params), &confirm, data, &len, 2000);
  zw101_unlock();
  if (!answered) { *error = true; return false; }
  if (confirm != ZW101_CONFIRM_OK || len != sizeof(data)) return false;
  *slot = ((uint16_t)data[0] << 8) | data[1];
  *score = ((uint16_t)data[2] << 8) | data[3];
  return *score > 0 && *slot >= 1 && *slot <= ZW101_MAX_SLOTS;
}

bool zw101_reg_model(void) { return simple(0x05, NULL, 0, 2000); }

bool zw101_store(uint8_t buffer, uint16_t slot) {
  uint8_t params[] = {buffer, (uint8_t)(slot >> 8), (uint8_t)slot};
  return simple(0x06, params, sizeof(params), 2000);
}

bool zw101_delete(uint16_t slot) {
  uint8_t params[] = {(uint8_t)(slot >> 8), (uint8_t)slot, 0x00, 0x01};
  return simple(0x0c, params, sizeof(params), 2000);
}

bool zw101_delete_all(void) { return simple(0x0d, NULL, 0, 2000); }

int zw101_count(void) {
  if (!zw101_lock(2000)) return -1;
  uint8_t data[2];
  size_t len = sizeof(data);
  uint8_t confirm = 0xff;
  bool ok = command(0x1d, NULL, 0, &confirm, data, &len, 1500) &&
            confirm == ZW101_CONFIRM_OK && len == sizeof(data);
  zw101_unlock();
  return ok ? (((int)data[0] << 8) | data[1]) : -1;
}

bool zw101_index_table(uint32_t *used) {
  if (!zw101_lock(2000)) return false;
  uint8_t page = 0;
  uint8_t table[32];
  size_t len = sizeof(table);
  uint8_t confirm = 0xff;
  bool ok = command(0x1f, &page, 1, &confirm, table, &len, 1500) &&
            confirm == ZW101_CONFIRM_OK && len == sizeof(table);
  zw101_unlock();
  if (!ok) return false;
  *used = 0;
  for (unsigned slot = 1; slot <= ZW101_MAX_SLOTS; slot++) {
    if (table[slot / 8] & (1u << (slot % 8))) *used |= 1u << slot;
  }
  return true;
}

bool zw101_touch_pin(void) { return gpio_get_level(BOARD_FP_TOUCH_PIN) == 1; }

void zw101_init(void) {
  gpio_config_t touch = {
    .pin_bit_mask = 1ULL << BOARD_FP_TOUCH_PIN,
    .mode = GPIO_MODE_INPUT,
    .pull_down_en = GPIO_PULLDOWN_ENABLE,
    .intr_type = GPIO_INTR_DISABLE,
  };
  ESP_ERROR_CHECK(gpio_config(&touch));

  uart_config_t cfg = {
    .baud_rate = BOARD_FP_BAUD,
    .data_bits = UART_DATA_8_BITS,
    .parity = UART_PARITY_DISABLE,
    .stop_bits = UART_STOP_BITS_1,
    .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
    .source_clk = UART_SCLK_DEFAULT,
  };
  ESP_ERROR_CHECK(uart_driver_install(UART, 1024, 0, 0, NULL, 0));
  ESP_ERROR_CHECK(uart_param_config(UART, &cfg));
  ESP_ERROR_CHECK(uart_set_pin(UART, BOARD_FP_TX_PIN, BOARD_FP_RX_PIN,
                               UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
  lock = xSemaphoreCreateRecursiveMutex();
  configASSERT(lock);

  bool ok = false;
  for (int attempt = 0; attempt < 3 && !ok; attempt++) {
    ok = verify();
    if (!ok) vTaskDelay(pdMS_TO_TICKS(250));
  }
  ESP_LOGI(TAG, "sensor %s", ok ? "ready" : "offline");
}

int zw101_match_now(uint16_t *slot, uint16_t *score) {
  if (!zw101_lock(1000)) return -1;
  int result = -1;
  int image = zw101_get_image();
  if (image == ZW101_CONFIRM_NO_FINGER) {
    result = 2;
  } else if (image == ZW101_CONFIRM_OK) {
    bool error = false;
    if (!zw101_gen_char(1)) {
      // A partial or smeared image converts badly; treat it as no finger so
      // the caller simply tries again.
      result = 2;
    } else if (zw101_search(1, slot, score, &error)) {
      result = 1;
    } else {
      result = error ? -1 : 0;
    }
  }
  zw101_unlock();
  return result;
}

#include "touch.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "led.h"
#include "link.h"
#include "settings.h"
#include "zw101.h"

#define SAMPLE_MS 10
#define POLL_INTERVAL_MS 150
#define TAP_MAX_MS 400
#define TAP_GAP_MS 300
#define HOLD_MS 800

static volatile bool present;
static volatile bool watch;

static bool sample(bool last) {
  if (settings_touch_source() == TOUCH_SOURCE_PIN) return zw101_touch_pin();
  static TickType_t next_poll;
  TickType_t now = xTaskGetTickCount();
  if (now < next_poll || link_busy() || !zw101_lock(0)) return last;
  next_poll = now + pdMS_TO_TICKS(POLL_INTERVAL_MS);
  int image = zw101_get_image();
  zw101_unlock();
  return image == ZW101_CONFIRM_OK ? true : image == ZW101_CONFIRM_NO_FINGER ? false : last;
}

static void match_on_touch(void) {
  if (link_busy() || !zw101_lock(0)) return;
  uint16_t slot = 0, score = 0;
  int result = 2;
  // The pin can rise before the sensor has a usable image.
  for (int attempt = 0; attempt < 6 && result == 2; attempt++) {
    result = zw101_match_now(&slot, &score);
    if (result == 2) vTaskDelay(pdMS_TO_TICKS(50));
  }
  if (result == 1) link_send("EVT MATCH slot=%u score=%u", slot, score);
  else if (result == 0) link_send("EVT NOMATCH");
  if (result == 1 || result == 0) led_result(result == 1);
  zw101_unlock();
}

static void touch_task(void *arg) {
  (void)arg;
  bool last = false;
  TickType_t down_at = 0;
  TickType_t tap_deadline = 0;
  unsigned taps = 0;
  bool hold_sent = false;

  while (true) {
    TickType_t now = xTaskGetTickCount();
    bool now_present = sample(last);
    present = now_present;

    if (now_present && !last) {
      down_at = now;
      hold_sent = false;
      link_send("EVT TOUCH state=down");
      if (watch) match_on_touch();
    } else if (!now_present && last) {
      link_send("EVT TOUCH state=up");
      if (!hold_sent && now - down_at < pdMS_TO_TICKS(TAP_MAX_MS)) {
        taps++;
        tap_deadline = now + pdMS_TO_TICKS(TAP_GAP_MS);
      }
    } else if (now_present && !hold_sent && now - down_at >= pdMS_TO_TICKS(HOLD_MS)) {
      hold_sent = true;
      taps = 0;
      link_send("EVT HOLD");
    }

    if (taps && !now_present && now >= tap_deadline) {
      link_send("EVT TAP count=%u", taps);
      taps = 0;
    }

    last = now_present;
    vTaskDelay(pdMS_TO_TICKS(SAMPLE_MS));
  }
}

bool touch_present(void) { return present; }
bool touch_watch(void) { return watch; }
void touch_set_watch(bool enabled) { watch = enabled; }

void touch_init(void) {
  BaseType_t created = xTaskCreate(touch_task, "touch", 4096, NULL, 4, NULL);
  configASSERT(created == pdPASS);
}

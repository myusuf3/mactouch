#include "presence.h"

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "led.h"
#include "link.h"
#include "zw101.h"

static bool wait_lift(uint32_t timeout_ms) {
  int64_t deadline = esp_timer_get_time() + (int64_t)timeout_ms * 1000;
  unsigned absent = 0;
  while (esp_timer_get_time() < deadline) {
    int image = zw101_get_image();
    if (image == ZW101_CONFIRM_NO_FINGER) { if (++absent >= 3) return true; }
    else absent = 0;
    vTaskDelay(pdMS_TO_TICKS(80));
  }
  return false;
}

bool presence_confirm(uint32_t timeout_ms, uint8_t colour, void (*tick)(void), const char **reason) {
  if (!zw101_lock(1000)) { *reason = "busy"; return false; }
  led_set(LED_MODE_BREATHE, colour, colour, 0);
  int64_t deadline = esp_timer_get_time() + (int64_t)timeout_ms * 1000;
  int64_t next_tick = 0;
  bool matched = false;
  *reason = "timeout";
  while (esp_timer_get_time() < deadline) {
    if (tick && esp_timer_get_time() >= next_tick) {
      tick();
      next_tick = esp_timer_get_time() + 500000;
    }
    uint16_t slot, score;
    int result = zw101_match_now(&slot, &score);
    if (result == 1) {
      link_send("EVT MATCH slot=%u score=%u", slot, score);
      matched = true;
      break;
    }
    if (result == 0) {
      link_send("EVT NOMATCH");
      led_set(LED_MODE_ON, LED_RED, LED_RED, 0);
      vTaskDelay(pdMS_TO_TICKS(350));
      led_set(LED_MODE_BREATHE, colour, colour, 0);
      wait_lift(2000);
      continue;
    }
    if (result < 0 && !zw101_recover()) { *reason = "sensor"; break; }
    vTaskDelay(pdMS_TO_TICKS(60));
  }
  zw101_unlock();
  return matched;
}

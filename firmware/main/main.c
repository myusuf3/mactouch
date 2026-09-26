#include "esp_err.h"
#include "esp_ota_ops.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "ccid.h"
#include "led.h"
#include "link.h"
#include "piv.h"
#include "settings.h"
#include "touch.h"
#include "usb.h"
#include "zw101.h"

void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    err = nvs_flash_init();
  }
  ESP_ERROR_CHECK(err);

  settings_init();
  zw101_init();
  led_init();
  piv_init();
  ccid_init();
  usb_init();
  link_init();
  touch_init();
#ifdef MACTOUCH_CRASH_TEST
  vTaskDelay(pdMS_TO_TICKS(5000));
  abort();
#endif
  // A freshly updated image stays on probation until the link task has seen
  // the host connected for a while (fw_mark_valid); a crash before then
  // sends the next boot back to the previous slot (ADR-0018).
}

#include "esp_err.h"
#include "esp_ota_ops.h"
#include "nvs_flash.h"

#include "ccid.h"
#include "led.h"
#include "link.h"
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
  ccid_init();
  usb_init();
  link_init();
  touch_init();
  // Harmless with a plain factory layout. When this image was delivered by
  // another firmware's OTA into a rollback-enabled slot, it keeps us booted.
  (void)esp_ota_mark_app_valid_cancel_rollback();
}

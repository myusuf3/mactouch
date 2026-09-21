#include "usb.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "tinyusb.h"
#include "tinyusb_default_config.h"
#include "usb_descriptors.h"

void usb_init(void) {
  usb_descriptors_init_serial();
  tinyusb_config_t cfg = TINYUSB_DEFAULT_CONFIG();
  cfg.descriptor.device = &mactouch_device_descriptor;
  cfg.descriptor.string = mactouch_string_descriptors;
  cfg.descriptor.string_count = mactouch_string_descriptor_count;
  cfg.descriptor.full_speed_config = mactouch_configuration_descriptor;
  ESP_ERROR_CHECK(tinyusb_driver_install(&cfg));
}

static void rescan_task(void *arg) {
  vTaskDelay(pdMS_TO_TICKS((uint32_t)(uintptr_t)arg));
  tud_disconnect();
  vTaskDelay(pdMS_TO_TICKS(250));
  tud_connect();
  vTaskDelete(NULL);
}

void usb_rescan(uint32_t delay_ms) {
  xTaskCreate(rescan_task, "usb_rescan", 2048, (void *)(uintptr_t)delay_ms, 2, NULL);
}

#include "usb.h"

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

#include "usb_descriptors.h"

#include <stdio.h>

#include "esp_mac.h"

#define USB_VID 0x303a  // Espressif
#define USB_PID 0x4d54  // "MT"

enum { ITF_NUM_CDC = 0, ITF_NUM_CDC_DATA, ITF_NUM_TOTAL };
#define EPNUM_CDC_NOTIF 0x81
#define EPNUM_CDC_OUT 0x02
#define EPNUM_CDC_IN 0x82
#define CONFIG_TOTAL_LEN (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN)

const tusb_desc_device_t mactouch_device_descriptor = {
  .bLength = sizeof(tusb_desc_device_t),
  .bDescriptorType = TUSB_DESC_DEVICE,
  .bcdUSB = 0x0200,
  .bDeviceClass = TUSB_CLASS_MISC,
  .bDeviceSubClass = MISC_SUBCLASS_COMMON,
  .bDeviceProtocol = MISC_PROTOCOL_IAD,
  .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
  .idVendor = USB_VID,
  .idProduct = USB_PID,
  .bcdDevice = 0x0100,
  .iManufacturer = 1,
  .iProduct = 2,
  .iSerialNumber = 3,
  .bNumConfigurations = 1,
};

const uint8_t mactouch_configuration_descriptor[] = {
  TUD_CONFIG_DESCRIPTOR(1, ITF_NUM_TOTAL, 0, CONFIG_TOTAL_LEN, 0, 100),
  TUD_CDC_DESCRIPTOR(ITF_NUM_CDC, 4, EPNUM_CDC_NOTIF, 8, EPNUM_CDC_OUT, EPNUM_CDC_IN, 64),
};

static char serial[20] = "MT-UNKNOWN";

const char *mactouch_string_descriptors[] = {
  (const char[]){0x09, 0x04},
  "mactouch",
  "mactouch",
  serial,
  "mactouch link",
};

const int mactouch_string_descriptor_count =
  sizeof(mactouch_string_descriptors) / sizeof(mactouch_string_descriptors[0]);

void usb_descriptors_init_serial(void) {
  uint8_t mac[6];
  if (esp_read_mac(mac, ESP_MAC_WIFI_STA) != ESP_OK) return;
  snprintf(serial, sizeof(serial), "MT-%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

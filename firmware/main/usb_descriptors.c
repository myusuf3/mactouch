#include "usb_descriptors.h"

#include <stdio.h>

#include "esp_mac.h"

#define USB_VID 0x303a  // Espressif
#define USB_PID 0x4d54  // "MT"

enum { ITF_NUM_CDC = 0, ITF_NUM_CDC_DATA, ITF_NUM_CCID, ITF_NUM_TOTAL };
#define EPNUM_CDC_NOTIF 0x81
#define EPNUM_CDC_OUT 0x02
#define EPNUM_CDC_IN 0x82
#define EPNUM_CCID_OUT 0x03
#define EPNUM_CCID_IN 0x83
#define CCID_DESC_LEN (9 + CCID_CLASS_DESC_LEN + 7 + 7)
#define CONFIG_TOTAL_LEN (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN + CCID_DESC_LEN)

// Smart card reader interface: class 0x0B, the CCID class descriptor, and
// two bulk endpoints. One slot, no interrupt endpoint because the card is
// never removed. Features: automatic parameters throughout, short and
// extended APDU level exchange, T=1 only.
#define CCID_DESCRIPTOR(_itfnum, _stridx, _epout, _epin, _epsize) \
  9, TUSB_DESC_INTERFACE, _itfnum, 0, 2, TUSB_CLASS_SMART_CARD, 0, 0, _stridx, \
  CCID_CLASS_DESC_LEN, 0x21, U16_TO_U8S_LE(0x0110), 0 /* bMaxSlotIndex */, 0x07 /* bVoltageSupport */, \
  U32_TO_U8S_LE(0x00000002) /* dwProtocols T=1 */, U32_TO_U8S_LE(4000) /* dwDefaultClock */, \
  U32_TO_U8S_LE(4000) /* dwMaximumClock */, 0 /* bNumClockSupported */, U32_TO_U8S_LE(9600) /* dwDataRate */, \
  U32_TO_U8S_LE(9600) /* dwMaxDataRate */, 0 /* bNumDataRatesSupported */, U32_TO_U8S_LE(254) /* dwMaxIFSD */, \
  U32_TO_U8S_LE(0) /* dwSynchProtocols */, U32_TO_U8S_LE(0) /* dwMechanical */, \
  U32_TO_U8S_LE(0x000404FE) /* dwFeatures */, U32_TO_U8S_LE(CCID_MAX_MESSAGE) /* dwMaxCCIDMessageLength */, \
  0xFF /* bClassGetResponse */, 0xFF /* bClassEnvelope */, U16_TO_U8S_LE(0) /* wLcdLayout */, \
  0 /* bPINSupport */, 1 /* bMaxCCIDBusySlots */, \
  7, TUSB_DESC_ENDPOINT, _epout, TUSB_XFER_BULK, U16_TO_U8S_LE(_epsize), 0, \
  7, TUSB_DESC_ENDPOINT, _epin, TUSB_XFER_BULK, U16_TO_U8S_LE(_epsize), 0

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
  CCID_DESCRIPTOR(ITF_NUM_CCID, 5, EPNUM_CCID_OUT, EPNUM_CCID_IN, 64),
};

static char serial[20] = "MT-UNKNOWN";

const char *mactouch_string_descriptors[] = {
  (const char[]){0x09, 0x04},
  "mactouch",
  "mactouch",
  serial,
  "mactouch link",
  "mactouch smart card",
};

const int mactouch_string_descriptor_count =
  sizeof(mactouch_string_descriptors) / sizeof(mactouch_string_descriptors[0]);

void usb_descriptors_init_serial(void) {
  uint8_t mac[6];
  if (esp_read_mac(mac, ESP_MAC_WIFI_STA) != ESP_OK) return;
  snprintf(serial, sizeof(serial), "MT-%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

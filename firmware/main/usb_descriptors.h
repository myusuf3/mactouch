#pragma once

#include "tusb.h"

// The reader's limits, shared with the class driver. Messages carry a
// 10-byte header plus one APDU; 3072 leaves room for a certificate.
#define CCID_MAX_MESSAGE 3072
#define CCID_CLASS_DESC_LEN 54

extern const tusb_desc_device_t mactouch_device_descriptor;
extern const uint8_t mactouch_configuration_descriptor[];
extern const char *mactouch_string_descriptors[];
extern const int mactouch_string_descriptor_count;

// Derives the USB serial number from the chip's MAC address.
void usb_descriptors_init_serial(void);

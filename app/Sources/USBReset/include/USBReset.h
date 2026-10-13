#pragma once

#include <stdbool.h>
#include <stdint.h>

// Resets the attached USB device with this vendor and product ID and has
// macOS enumerate it again, as unplugging it would. False when there is no
// such device or macOS refused.
bool usb_reenumerate(uint16_t vendor, uint16_t product);

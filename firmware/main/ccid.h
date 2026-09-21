#pragma once

#include <stdbool.h>
#include <stdint.h>

// USB CCID smart card reader interface, one slot, card always inserted. The
// class driver registers itself with TinyUSB; ccid_init starts the task that
// answers APDUs off the USB task.
void ccid_init(void);
bool ccid_mounted(void);
// For the card, while it works on the APDU in flight.
void ccid_time_extension(void);

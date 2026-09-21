#pragma once

#include <stdint.h>

void usb_init(void);
// Drops off the bus and comes back after `delay_ms`, without a reboot, so
// the host re-reads a card whose identity changed. The serial link drops too.
void usb_rescan(uint32_t delay_ms);

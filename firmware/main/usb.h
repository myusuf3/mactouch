#pragma once

#include <stdbool.h>
#include <stdint.h>

// `keyboard` adds the keyboard interface, for touch unlock mode. It is fixed
// for the life of the boot.
void usb_init(bool keyboard);
bool usb_has_keyboard(void);
// Drops off the bus and comes back after `delay_ms`, without a reboot, so
// the host re-reads a card whose identity changed. The serial link drops too.
void usb_rescan(uint32_t delay_ms);
// Restarts the board after `delay_ms`, so a reply queued now goes out first;
// how a change of unlock mode adds or removes the keyboard interface.
void usb_restart(uint32_t delay_ms);

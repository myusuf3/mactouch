#pragma once

#include <stdbool.h>
#include <stdint.h>

// Persistent device settings in NVS. Policy lives on the Mac; these are only
// the values the device needs before a host has connected.

typedef enum { TOUCH_SOURCE_PIN = 0, TOUCH_SOURCE_POLL = 1 } touch_source_t;

void settings_init(void);
uint8_t settings_idle_colour(void);
void settings_set_idle_colour(uint8_t colour);
touch_source_t settings_touch_source(void);
void settings_set_touch_source(touch_source_t source);
// 32-byte key created on first boot. Proves to a verifier holding a copy that
// a match came from this device.
void settings_device_key(uint8_t out[32]);

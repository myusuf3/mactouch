#pragma once

#include <stdbool.h>

// Finger presence, gesture events, and optional match-on-touch.
void touch_init(void);
bool touch_present(void);
bool touch_watch(void);
void touch_set_watch(bool enabled);

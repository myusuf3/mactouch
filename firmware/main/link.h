#pragma once

#include <stdbool.h>

// Host link: newline-delimited text over USB CDC. See docs/PROTOCOL.md.
void link_init(void);
// Sends one line. Thread-safe. Dropped when no host is connected.
void link_send(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
// True while IDENTIFY, ENROLL or PAIR owns the sensor.
bool link_busy(void);

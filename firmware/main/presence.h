#pragma once

#include <stdbool.h>
#include <stdint.h>

// Waits for an enrolled finger with the ring breathing `colour`, flashing
// red on a wrong finger. `tick`, if given, runs every few hundred
// milliseconds while waiting, for callers that must keep a host from timing
// out. Takes the sensor lock; fails at once if another task holds it.
// `reason` is "timeout", "sensor" or "busy" on failure.
bool presence_confirm(uint32_t timeout_ms, uint8_t colour, void (*tick)(void), const char **reason);

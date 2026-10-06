#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// The press and release sequence behind password typing (ADR-0022), apart
// from the USB stack so firmware/test can run it against a fake host.

// One keystroke: an HID modifier byte (0x02 is left Shift) and a key code.
// {0, 0} is every key up.
typedef struct {
  uint8_t modifier;
  uint8_t code;
} typing_key_t;

typedef struct {
  // The host has taken the last report, so another can be sent.
  bool (*ready)(void *ctx);
  bool (*send)(void *ctx, typing_key_t key);
  // Waits one scheduler tick.
  void (*sleep)(void *ctx);
  void *ctx;
} typing_port_t;

// Presses and releases each key in turn, waiting up to `max_waits` ticks for
// the host to take each report. Whatever goes wrong, the last report it
// tries is every key up: a key left down auto-repeats into whatever has
// focus.
bool typing_run(const typing_port_t *port, const typing_key_t *keys, size_t count, unsigned max_waits);

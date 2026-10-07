#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "typing.h"

// The boot keyboard interface, enumerated only in password mode (ADR-0022).
// Types each keystroke in turn, typing_run, and never leaves a key down.
// Only the link's console task calls it, for TYPE, so the HID endpoint has
// one owner, as the CCID one does.
bool keyboard_type(const typing_key_t *keys, size_t count);

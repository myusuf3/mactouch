#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "typing.h"

// How the Mac is unlocked (ADR-0022). Pure, so firmware/test builds and
// checks it on the host.

// pin: the smart card, its PIN then a touch. password: the card reports no
// card, and a touch the Mac armed for types the password it sends.
typedef enum { UNLOCK_PIN = 0, UNLOCK_PASSWORD = 1 } unlock_mode_t;

const char *unlock_mode_name(unlock_mode_t mode);
bool unlock_parse_mode(const char *name, unlock_mode_t *out);

#define UNLOCK_MAX_TEXT 64
#define UNLOCK_MAX_KEYS (UNLOCK_MAX_TEXT + 1)

// Keystrokes for printable ASCII as a US layout types it, digits on the
// keypad because those read the same in every layout, then Return. Returns
// how many, or 0 when the text is empty, too long, or has a character it
// cannot type.
size_t unlock_text_keys(const uint8_t *text, size_t len, typing_key_t keys[UNLOCK_MAX_KEYS]);

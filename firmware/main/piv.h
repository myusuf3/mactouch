#pragma once

#include <stddef.h>
#include <stdint.h>

// The card behind the CCID reader. Takes a command APDU and writes the
// response APDU, status word included. Never writes more than `cap` bytes;
// a response that would not fit becomes 6F00.
size_t piv_apdu(const uint8_t *cmd, size_t len, uint8_t *resp, size_t cap);

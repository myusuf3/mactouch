#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// The card behind the CCID reader: the subset of the PIV application
// (SP 800-73-4) that macOS's built-in token driver uses. docs/PIV.md.

void piv_init(void);

// Takes a command APDU and writes the response APDU, status word included.
// Never writes more than `cap` bytes; a response that would not fit becomes
// 6F00.
size_t piv_apdu(const uint8_t *cmd, size_t len, uint8_t *resp, size_t cap);

// Card power-off or USB reset: the PIN must be presented again.
void piv_session_reset(void);

// Off by default. While off the reader reports no card, so an unpaired
// device is invisible to the Mac's smart card stack.
bool piv_enabled(void);
void piv_set_enabled(bool enabled);

// The identity: P-256 keys for PIV Authentication (9A) and Key Management
// (9D) with self-signed certificates, made here and never exported. Both
// take a moment and are meant for the link's worker task.
bool piv_has_identity(void);
bool piv_generate_identity(void);
void piv_reset_identity(void);
// Whether the PIN is still the factory 123456, and tries left before block.
bool piv_pin_is_default(void);
uint8_t piv_pin_retries(void);

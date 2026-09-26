#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Firmware updates over the link, ADR-0018: the spare OTA slot is written
// in order, its SHA-256 checked, and the boot slot switched. The caller
// gates `fw_update_begin` behind a touch.

// Starts an update of `size` bytes whose digest is `sha256_hex`. Erases the
// spare slot, which takes a few seconds. `reason` is set on failure.
bool fw_update_begin(size_t size, const char *sha256_hex, const char **reason);
// Appends base64 `data` at `offset`, which must be where the last write
// ended. Returns false and aborts the update on any error.
bool fw_update_write(size_t offset, const char *data, const char **reason);
// Checks length, digest and image, then makes the new slot the boot slot.
bool fw_update_end(const char **reason);
void fw_update_abort(void);
bool fw_update_active(void);
size_t fw_update_written(void);

// The running slot's label, and whether it is still on probation.
const char *fw_running_slot(void);
bool fw_pending_verify(void);
// Called once the host link has been healthy long enough; ends probation.
void fw_mark_valid(void);

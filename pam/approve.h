#pragma once
// Fingerprint approval for a PAM module: ask the user's mactouchd for a
// nonce-bearing identify and verify the device's HMAC against a root-only
// copy of the device key. Construction pinned by docs/protocol-vectors.json.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MT_KEY_LEN 32
#define MT_NONCE_HEX 32
#define MT_MAC_HEX 64
#define MT_ERR_LEN 160

typedef enum {
  MT_APPROVED = 0,
  MT_DENIED,       // the daemon answered, but the signature did not verify
  MT_UNAVAILABLE,  // no daemon, no touch in time, or a daemon-side error: use the password
} mt_result_t;

bool mt_parse_key(const char *hex, uint8_t key[MT_KEY_LEN]);
bool mt_read_key_file(const char *path, uint8_t key[MT_KEY_LEN]);
void mt_sign(const uint8_t key[MT_KEY_LEN], const char *nonce_hex, unsigned slot, char mac_hex[MT_MAC_HEX + 1]);
bool mt_verify(const uint8_t key[MT_KEY_LEN], const char *nonce_hex, unsigned slot, const char *mac_hex);

// Sends `identify timeout=<s> nonce=<fresh> reason=<reason>` to the control
// socket and verifies the reply. `err` gets a one-line explanation for the
// log when the result is not MT_APPROVED.
mt_result_t mt_request_approval(const char *socket_path, const uint8_t key[MT_KEY_LEN],
                                unsigned timeout_s, const char *reason, char err[MT_ERR_LEN]);

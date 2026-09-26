#include "fw_update.h"

#include <ctype.h>
#include <string.h>

#include "esp_log.h"
#include "esp_ota_ops.h"
#include "mbedtls/base64.h"
#include "mbedtls/sha256.h"

static const char *TAG = "fw";

static const esp_partition_t *target;
static esp_ota_handle_t handle;
static size_t expected, written;
static uint8_t digest[32];
static mbedtls_sha256_context sha;
static bool active;

static bool parse_digest(const char *hex, uint8_t out[32]) {
  if (strlen(hex) != 64) return false;
  for (size_t i = 0; i < 32; i++) {
    char pair[3] = {hex[2 * i], hex[2 * i + 1], 0};
    if (!isxdigit((unsigned char)pair[0]) || !isxdigit((unsigned char)pair[1])) return false;
    out[i] = (uint8_t)strtoul(pair, NULL, 16);
  }
  return true;
}

void fw_update_abort(void) {
  if (active) {
    esp_ota_abort(handle);
    mbedtls_sha256_free(&sha);
  }
  active = false;
  target = NULL;
  expected = written = 0;
}

bool fw_update_begin(size_t size, const char *sha256_hex, const char **reason) {
  fw_update_abort();
  target = esp_ota_get_next_update_partition(NULL);
  if (!target) { *reason = "layout"; return false; }  // single-slot table
  if (size == 0 || size > target->size) { *reason = "size"; return false; }
  if (!parse_digest(sha256_hex, digest)) { *reason = "sha256"; return false; }
  esp_err_t err = esp_ota_begin(target, size, &handle);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "begin: %s", esp_err_to_name(err));
    *reason = "begin";
    target = NULL;
    return false;
  }
  mbedtls_sha256_init(&sha);
  mbedtls_sha256_starts(&sha, 0);
  expected = size;
  written = 0;
  active = true;
  ESP_LOGI(TAG, "updating %s, %u bytes", target->label, (unsigned)size);
  return true;
}

bool fw_update_write(size_t offset, const char *data, const char **reason) {
  if (!active) { *reason = "inactive"; return false; }
  if (offset != written) { *reason = "offset"; fw_update_abort(); return false; }
  uint8_t bytes[192];
  size_t length = 0;
  if (mbedtls_base64_decode(bytes, sizeof(bytes), &length, (const unsigned char *)data, strlen(data)) != 0 ||
      length == 0 || written + length > expected) {
    *reason = "data";
    fw_update_abort();
    return false;
  }
  if (esp_ota_write(handle, bytes, length) != ESP_OK) {
    *reason = "write";
    fw_update_abort();
    return false;
  }
  mbedtls_sha256_update(&sha, bytes, length);
  written += length;
  return true;
}

bool fw_update_end(const char **reason) {
  if (!active) { *reason = "inactive"; return false; }
  if (written != expected) { *reason = "short"; fw_update_abort(); return false; }
  uint8_t actual[32];
  mbedtls_sha256_finish(&sha, actual);
  mbedtls_sha256_free(&sha);
  if (memcmp(actual, digest, sizeof(actual)) != 0) {
    esp_ota_abort(handle);
    active = false;
    *reason = "sha256";
    return false;
  }
  active = false;
  // esp_ota_end checks the image header and segments before accepting it.
  esp_err_t err = esp_ota_end(handle);
  if (err != ESP_OK) { ESP_LOGE(TAG, "end: %s", esp_err_to_name(err)); *reason = "image"; return false; }
  if (esp_ota_set_boot_partition(target) != ESP_OK) { *reason = "boot"; return false; }
  ESP_LOGI(TAG, "next boot from %s", target->label);
  return true;
}

bool fw_update_active(void) { return active; }
size_t fw_update_written(void) { return written; }

const char *fw_running_slot(void) {
  const esp_partition_t *running = esp_ota_get_running_partition();
  return running ? running->label : "?";
}

bool fw_pending_verify(void) {
  esp_ota_img_states_t state;
  return esp_ota_get_state_partition(esp_ota_get_running_partition(), &state) == ESP_OK &&
         state == ESP_OTA_IMG_PENDING_VERIFY;
}

void fw_mark_valid(void) {
  if (!fw_pending_verify()) return;
  if (esp_ota_mark_app_valid_cancel_rollback() == ESP_OK) ESP_LOGI(TAG, "%s marked valid", fw_running_slot());
}

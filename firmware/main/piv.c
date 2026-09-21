#include "piv.h"

#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "mbedtls/ecdh.h"
#include "mbedtls/ecdsa.h"
#include "mbedtls/oid.h"
#include "mbedtls/pk.h"
#include "mbedtls/sha256.h"
#include "mbedtls/x509_crt.h"
#include "nvs.h"

static const char *TAG = "piv";

// Status words.
#define SW_OK 0x9000
#define SW_MORE 0x6100
#define SW_RETRIES 0x63C0
#define SW_WRONG_LENGTH 0x6700
#define SW_SECURITY_STATUS 0x6982
#define SW_AUTH_BLOCKED 0x6983
#define SW_CONDITIONS_NOT_SATISFIED 0x6985
#define SW_WRONG_DATA 0x6A80
#define SW_FILE_NOT_FOUND 0x6A82
#define SW_INCORRECT_P1P2 0x6A86
#define SW_REFERENCE_NOT_FOUND 0x6A88
#define SW_INS_NOT_SUPPORTED 0x6D00
#define SW_CLA_NOT_SUPPORTED 0x6E00
#define SW_UNKNOWN 0x6F00

// The PIV card application AID: RID A000000308, PIX 00001000, version 0100.
#define PIV_AID 0xA0, 0x00, 0x00, 0x03, 0x08, 0x00, 0x00, 0x10, 0x00, 0x01, 0x00
static const uint8_t aid[] = {PIV_AID};

// Application property template answered to SELECT: the AID's PIX and the
// coexisting tag allocation authority (the RID).
static const uint8_t property_template[] = {
  0x61, 0x11,
  0x4F, 0x06, 0x00, 0x00, 0x10, 0x00, 0x01, 0x00,
  0x79, 0x07, 0x4F, 0x05, 0xA0, 0x00, 0x00, 0x03, 0x08,
};

// Discovery object: the AID and the PIN usage policy, 0x40 meaning the PIV
// card application PIN satisfies the card, with no global PIN.
static const uint8_t discovery_object[] = {
  0x7E, 0x12,
  0x4F, 0x0B, PIV_AID,
  0x5F, 0x2F, 0x02, 0x40, 0x00,
};

// Card capability container. macOS reads it and needs nothing from it; the
// card identifier bytes are the conventional test values.
static const uint8_t capability_container[] = {
  0x53, 0x24,
  0xF0, 0x15, 0xA0, 0x00, 0x00, 0x01, 0x16, 0xFF, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
              0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
  0xF1, 0x01, 0x21,
  0xF2, 0x01, 0x21,
  0xF3, 0x00,
  0xF4, 0x01, 0x00,
  0xF5, 0x01, 0x10,
};

// Key history object: no retired keys.
static const uint8_t key_history[] = {
  0x53, 0x09,
  0xC1, 0x01, 0x00,
  0xC2, 0x01, 0x00,
  0xC3, 0x01, 0x00,
};

// Card holder unique identifier: FASC-N (the standard test value), the GUID
// that CryptoTokenKit uses as the token identifier, an expiry date, an empty
// issuer signature. The GUID is filled in by set_token_id.
#define CHUID_GUID_OFFSET 31
static uint8_t chuid[] = {
  0x53, 0x3B,
  0x30, 0x19, 0xD4, 0xE7, 0x39, 0xDA, 0x73, 0x9C, 0xED, 0x39, 0xCE, 0x73, 0x9D, 0x83, 0x68, 0x58,
              0x21, 0x08, 0x42, 0x10, 0x84, 0x21, 0xC8, 0x42, 0x10, 0xC3, 0xEB,
  0x34, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x35, 0x08, '2', '0', '4', '6', '0', '1', '0', '1',
  0x3E, 0x00,
  0xFE, 0x00,
};

// Data object tags as they appear after 5C in GET DATA.
static const uint8_t tag_chuid[] = {0x5F, 0xC1, 0x02};
static const uint8_t tag_capability[] = {0x5F, 0xC1, 0x07};
static const uint8_t tag_auth_cert[] = {0x5F, 0xC1, 0x05};
static const uint8_t tag_key_mgmt_cert[] = {0x5F, 0xC1, 0x0B};
static const uint8_t tag_key_history[] = {0x5F, 0xC1, 0x0C};
static const uint8_t tag_discovery[] = {0x7E};

// MARK: identity and PIN

#define PIV_MAX_CERT 1024
#define PIN_LEN 8
#define PIN_RETRIES 3

typedef struct {
  const char *key_name, *cert_name, *common_name;
  bool key_management;
  mbedtls_pk_context key;
  uint8_t cert[PIV_MAX_CERT];
  size_t cert_len;
} slot_t;

static slot_t auth_slot = {.key_name = "key9a", .cert_name = "cert9a", .common_name = "CN=mactouch PIV Authentication"};
static slot_t key_mgmt_slot = {.key_name = "key9d", .cert_name = "cert9d", .common_name = "CN=mactouch PIV Key Management", .key_management = true};
static bool identity_loaded;
static const uint8_t default_pin[PIN_LEN] = {'1', '2', '3', '4', '5', '6', 0xFF, 0xFF};
static uint8_t pin[PIN_LEN];
static uint8_t retries = PIN_RETRIES;
static bool pin_verified;
static nvs_handle_t store;
// Serialises the APDU task against the link's worker regenerating the identity.
static SemaphoreHandle_t lock;

static int rng(void *ctx, unsigned char *out, size_t len) {
  (void)ctx;
  esp_fill_random(out, len);
  return 0;
}

// The CHUID's GUID is what CryptoTokenKit files the card under, so it
// follows the identity: the authentication certificate once there is one,
// the chip's address before that, so an unprovisioned board is stable too.
static void set_token_id(const uint8_t *seed, size_t len) {
  uint8_t digest[32];
  mbedtls_sha256(seed, len, digest, 0);
  uint8_t *guid = chuid + CHUID_GUID_OFFSET;
  memcpy(guid, digest, 16);
  guid[6] = (guid[6] & 0x0F) | 0x40;  // RFC 4122 version 4 shape
  guid[8] = (guid[8] & 0x3F) | 0x80;
}

static void free_slot(slot_t *slot) {
  mbedtls_pk_free(&slot->key);
  mbedtls_pk_init(&slot->key);
  memset(slot->cert, 0, sizeof(slot->cert));
  slot->cert_len = 0;
}

static bool load_slot(slot_t *slot) {
  uint8_t der[256];
  size_t key_len = sizeof(der);
  size_t cert_len = sizeof(slot->cert);
  if (nvs_get_blob(store, slot->key_name, der, &key_len) != ESP_OK) return false;
  if (nvs_get_blob(store, slot->cert_name, slot->cert, &cert_len) != ESP_OK) return false;
  int rc = mbedtls_pk_parse_key(&slot->key, der, key_len, NULL, 0, rng, NULL);
  memset(der, 0, sizeof(der));
  if (rc != 0 || mbedtls_pk_get_type(&slot->key) != MBEDTLS_PK_ECKEY) return false;
  slot->cert_len = cert_len;
  return true;
}

static void load_identity(void) {
  free_slot(&auth_slot);
  free_slot(&key_mgmt_slot);
  identity_loaded = load_slot(&auth_slot) && load_slot(&key_mgmt_slot);
  if (identity_loaded) {
    set_token_id(auth_slot.cert, auth_slot.cert_len);
  } else {
    free_slot(&auth_slot);
    free_slot(&key_mgmt_slot);
    uint8_t mac[6];
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) set_token_id(mac, sizeof(mac));
  }
}

static void load_pin(void) {
  size_t len = sizeof(pin);
  if (nvs_get_blob(store, "pin", pin, &len) != ESP_OK || len != sizeof(pin)) memcpy(pin, default_pin, sizeof(pin));
  uint8_t value;
  retries = nvs_get_u8(store, "retries", &value) == ESP_OK ? value : PIN_RETRIES;
}

static void save_retries(void) {
  nvs_set_u8(store, "retries", retries);
  nvs_commit(store);
}

// Self-signed, twenty years, SHA-256. The card has no clock, so the dates are
// fixed; macOS pairs on the key hash and does not check them.
static bool make_certificate(slot_t *slot) {
  static const unsigned char client_auth_oid[] = MBEDTLS_OID_CLIENT_AUTH;
  mbedtls_asn1_sequence client_auth = {
    .buf = {.tag = MBEDTLS_ASN1_OID, .len = sizeof(client_auth_oid) - 1, .p = (unsigned char *)client_auth_oid},
  };
  uint8_t serial[16];
  esp_fill_random(serial, sizeof(serial));
  serial[0] &= 0x7F;
  mbedtls_x509write_cert crt;
  mbedtls_x509write_crt_init(&crt);
  mbedtls_x509write_crt_set_version(&crt, MBEDTLS_X509_CRT_VERSION_3);
  mbedtls_x509write_crt_set_md_alg(&crt, MBEDTLS_MD_SHA256);
  mbedtls_x509write_crt_set_subject_key(&crt, &slot->key);
  mbedtls_x509write_crt_set_issuer_key(&crt, &slot->key);
  int rc = mbedtls_x509write_crt_set_subject_name(&crt, slot->common_name);
  if (rc == 0) rc = mbedtls_x509write_crt_set_issuer_name(&crt, slot->common_name);
  if (rc == 0) rc = mbedtls_x509write_crt_set_validity(&crt, "20260101000000", "20460101000000");
  if (rc == 0) rc = mbedtls_x509write_crt_set_serial_raw(&crt, serial, sizeof(serial));
  if (rc == 0) rc = mbedtls_x509write_crt_set_basic_constraints(&crt, 0, -1);
  if (rc == 0) rc = mbedtls_x509write_crt_set_key_usage(&crt, slot->key_management ? MBEDTLS_X509_KU_KEY_AGREEMENT : MBEDTLS_X509_KU_DIGITAL_SIGNATURE);
  if (rc == 0 && !slot->key_management) rc = mbedtls_x509write_crt_set_ext_key_usage(&crt, &client_auth);
  if (rc == 0) {
    // mbedtls writes DER at the end of the buffer.
    rc = mbedtls_x509write_crt_der(&crt, slot->cert, sizeof(slot->cert), rng, NULL);
    if (rc > 0) {
      slot->cert_len = (size_t)rc;
      memmove(slot->cert, slot->cert + sizeof(slot->cert) - slot->cert_len, slot->cert_len);
      rc = 0;
    }
  }
  mbedtls_x509write_crt_free(&crt);
  return rc == 0;
}

static bool make_slot(slot_t *slot) {
  free_slot(slot);
  if (mbedtls_pk_setup(&slot->key, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY)) != 0) return false;
  if (mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1, mbedtls_pk_ec(slot->key), rng, NULL) != 0) return false;
  if (!make_certificate(slot)) return false;
  uint8_t der[256];
  int len = mbedtls_pk_write_key_der(&slot->key, der, sizeof(der));
  if (len <= 0) return false;
  bool ok = nvs_set_blob(store, slot->key_name, der + sizeof(der) - len, (size_t)len) == ESP_OK &&
            nvs_set_blob(store, slot->cert_name, slot->cert, slot->cert_len) == ESP_OK;
  memset(der, 0, sizeof(der));
  return ok;
}

bool piv_has_identity(void) { return identity_loaded; }
bool piv_pin_is_default(void) { return memcmp(pin, default_pin, sizeof(pin)) == 0; }
uint8_t piv_pin_retries(void) { return retries; }

bool piv_generate_identity(void) {
  xSemaphoreTake(lock, portMAX_DELAY);
  bool ok = !identity_loaded && make_slot(&auth_slot) && make_slot(&key_mgmt_slot) && nvs_commit(store) == ESP_OK;
  if (!ok) {
    nvs_erase_key(store, auth_slot.key_name); nvs_erase_key(store, auth_slot.cert_name);
    nvs_erase_key(store, key_mgmt_slot.key_name); nvs_erase_key(store, key_mgmt_slot.cert_name);
    nvs_commit(store);
  }
  load_identity();
  pin_verified = false;
  xSemaphoreGive(lock);
  ESP_LOGI(TAG, "%s", ok ? "identity generated" : "identity generation failed");
  return ok && identity_loaded;
}

// Destroys the keys and certificates and returns the PIN to the default.
void piv_reset_identity(void) {
  xSemaphoreTake(lock, portMAX_DELAY);
  nvs_erase_all(store);
  nvs_commit(store);
  load_identity();
  load_pin();
  pin_verified = false;
  xSemaphoreGive(lock);
  ESP_LOGI(TAG, "identity reset");
}

// MARK: APDUs

// A response longer than the host asked for is handed out through GET
// RESPONSE; this is the remainder.
#define PIV_MAX_OBJECT 2048
static uint8_t pending[PIV_MAX_OBJECT];
static size_t pending_len, pending_off;

typedef struct {
  uint8_t cla, ins, p1, p2;
  const uint8_t *data;
  size_t lc;
  size_t le;  // 0 when absent
} apdu_t;

// Short and extended encodings, cases 1 to 4. Le of 00 means the maximum.
static bool parse_apdu(const uint8_t *cmd, size_t len, apdu_t *out) {
  if (len < 4) return false;
  *out = (apdu_t){.cla = cmd[0], .ins = cmd[1], .p1 = cmd[2], .p2 = cmd[3]};
  if (len == 4) return true;
  if (len == 5) { out->le = cmd[4] ? cmd[4] : 256; return true; }
  if (cmd[4] != 0) {
    out->lc = cmd[4];
    out->data = cmd + 5;
    if (len == 5 + out->lc) return true;
    if (len == 6 + out->lc) { out->le = cmd[len - 1] ? cmd[len - 1] : 256; return true; }
    return false;
  }
  if (len == 7) { out->le = (cmd[5] << 8 | cmd[6]) ? (size_t)(cmd[5] << 8 | cmd[6]) : 65536; return true; }
  if (len < 7) return false;
  out->lc = (size_t)cmd[5] << 8 | cmd[6];
  out->data = cmd + 7;
  if (len == 7 + out->lc) return true;
  if (len == 9 + out->lc) {
    size_t le = (size_t)cmd[len - 2] << 8 | cmd[len - 1];
    out->le = le ? le : 65536;
    return true;
  }
  return false;
}

static size_t status(uint8_t *resp, size_t cap, uint16_t sw) {
  if (cap < 2) return 0;
  resp[0] = sw >> 8;
  resp[1] = sw & 0xFF;
  return 2;
}

// Writes as much of `data` as the host asked for and the buffer holds, then
// 9000 or 61xx with the rest kept for GET RESPONSE.
static size_t reply(uint8_t *resp, size_t cap, const uint8_t *data, size_t len, size_t le) {
  size_t room = cap - 2;
  size_t take = len;
  if (le && take > le) take = le;
  if (take > room) take = room;
  if (take > 256) take = 256;  // one GET RESPONSE worth at a time, as short APDUs expect
  memcpy(resp, data, take);
  size_t rest = len - take;
  if (rest == 0) {
    pending_len = pending_off = 0;
    return take + status(resp + take, 2, SW_OK);
  }
  if (rest > sizeof(pending)) return status(resp, cap, SW_UNKNOWN);
  memcpy(pending, data + take, rest);
  pending_len = rest;
  pending_off = 0;
  return take + status(resp + take, 2, SW_MORE | (rest > 255 ? 0 : rest));
}

static size_t get_response(uint8_t *resp, size_t cap, const apdu_t *apdu) {
  if (pending_off >= pending_len) return status(resp, cap, SW_CONDITIONS_NOT_SATISFIED);
  size_t rest = pending_len - pending_off;
  uint8_t chunk[256];
  size_t take = rest < sizeof(chunk) ? rest : sizeof(chunk);
  if (apdu->le && take > apdu->le) take = apdu->le;
  memcpy(chunk, pending + pending_off, take);
  pending_off += take;
  rest -= take;
  memcpy(resp, chunk, take);
  if (rest == 0) {
    pending_len = pending_off = 0;
    return take + status(resp + take, 2, SW_OK);
  }
  return take + status(resp + take, 2, SW_MORE | (rest > 255 ? 0 : rest));
}

static size_t select_application(uint8_t *resp, size_t cap, const apdu_t *apdu) {
  // Both the full AID and the version-less one select the application.
  bool full = apdu->lc == sizeof(aid) && memcmp(apdu->data, aid, sizeof(aid)) == 0;
  bool bare = apdu->lc == sizeof(aid) - 2 && memcmp(apdu->data, aid, sizeof(aid) - 2) == 0;
  if (!full && !bare) return status(resp, cap, SW_FILE_NOT_FOUND);
  return reply(resp, cap, property_template, sizeof(property_template), apdu->le);
}

static bool tag_is(const apdu_t *apdu, const uint8_t *tag, size_t tag_len) {
  return apdu->lc == 2 + tag_len && apdu->data[0] == 0x5C && apdu->data[1] == tag_len &&
         memcmp(apdu->data + 2, tag, tag_len) == 0;
}

// BER length, one to three bytes.
static size_t put_len(uint8_t *out, size_t len) {
  if (len < 0x80) { out[0] = (uint8_t)len; return 1; }
  if (len <= 0xFF) { out[0] = 0x81; out[1] = (uint8_t)len; return 2; }
  out[0] = 0x82; out[1] = (uint8_t)(len >> 8); out[2] = (uint8_t)len;
  return 3;
}

// A certificate object: 53 { 70 certificate, 71 00 (not compressed), FE 00 }.
static size_t certificate_object(const slot_t *slot, uint8_t *resp, size_t cap, size_t le) {
  if (!identity_loaded || slot->cert_len == 0) return status(resp, cap, SW_REFERENCE_NOT_FOUND);
  static uint8_t object[PIV_MAX_CERT + 16];
  uint8_t inner[PIV_MAX_CERT + 12];
  size_t n = 0;
  inner[n++] = 0x70;
  n += put_len(inner + n, slot->cert_len);
  memcpy(inner + n, slot->cert, slot->cert_len);
  n += slot->cert_len;
  inner[n++] = 0x71; inner[n++] = 0x01; inner[n++] = 0x00;
  inner[n++] = 0xFE; inner[n++] = 0x00;
  size_t m = 0;
  object[m++] = 0x53;
  m += put_len(object + m, n);
  memcpy(object + m, inner, n);
  m += n;
  return reply(resp, cap, object, m, le);
}

static size_t get_data(uint8_t *resp, size_t cap, const apdu_t *apdu) {
  if (apdu->p1 != 0x3F || apdu->p2 != 0xFF) return status(resp, cap, SW_INCORRECT_P1P2);
  if (apdu->lc < 3 || apdu->data[0] != 0x5C) return status(resp, cap, SW_WRONG_DATA);
  if (tag_is(apdu, tag_discovery, sizeof(tag_discovery)))
    return reply(resp, cap, discovery_object, sizeof(discovery_object), apdu->le);
  if (tag_is(apdu, tag_chuid, sizeof(tag_chuid)))
    return reply(resp, cap, chuid, sizeof(chuid), apdu->le);
  if (tag_is(apdu, tag_capability, sizeof(tag_capability)))
    return reply(resp, cap, capability_container, sizeof(capability_container), apdu->le);
  if (tag_is(apdu, tag_key_history, sizeof(tag_key_history)))
    return reply(resp, cap, key_history, sizeof(key_history), apdu->le);
  if (tag_is(apdu, tag_auth_cert, sizeof(tag_auth_cert)))
    return certificate_object(&auth_slot, resp, cap, apdu->le);
  if (tag_is(apdu, tag_key_mgmt_cert, sizeof(tag_key_mgmt_cert)))
    return certificate_object(&key_mgmt_slot, resp, cap, apdu->le);
  return status(resp, cap, SW_REFERENCE_NOT_FOUND);
}

// Six to eight digits, FF padding to eight, as the PIN standard says.
static bool pin_well_formed(const uint8_t *candidate) {
  size_t digits = 0;
  while (digits < PIN_LEN && candidate[digits] >= '0' && candidate[digits] <= '9') digits++;
  if (digits < 6) return false;
  for (size_t i = digits; i < PIN_LEN; i++) if (candidate[i] != 0xFF) return false;
  return true;
}

static bool pin_matches(const uint8_t *candidate) {
  uint8_t diff = 0;
  for (size_t i = 0; i < PIN_LEN; i++) diff |= candidate[i] ^ pin[i];
  return diff == 0;
}

// One attempt against the counter: the shared core of VERIFY and CHANGE
// REFERENCE DATA. Returns the status word, 9000 on success.
static uint16_t try_pin(const uint8_t *candidate) {
  if (retries == 0) return SW_AUTH_BLOCKED;
  if (pin_matches(candidate)) {
    if (retries != PIN_RETRIES) { retries = PIN_RETRIES; save_retries(); }
    return SW_OK;
  }
  retries--;
  save_retries();
  pin_verified = false;
  return retries ? (uint16_t)(SW_RETRIES | retries) : SW_AUTH_BLOCKED;
}

static size_t verify(uint8_t *resp, size_t cap, const apdu_t *apdu) {
  if (apdu->p2 != 0x80) return status(resp, cap, SW_REFERENCE_NOT_FOUND);
  if (apdu->p1 == 0xFF && apdu->lc == 0) { pin_verified = false; return status(resp, cap, SW_OK); }
  if (apdu->p1 != 0x00) return status(resp, cap, SW_INCORRECT_P1P2);
  if (apdu->lc == 0) {
    if (pin_verified) return status(resp, cap, SW_OK);
    return status(resp, cap, retries ? (uint16_t)(SW_RETRIES | retries) : SW_AUTH_BLOCKED);
  }
  if (apdu->lc != PIN_LEN) return status(resp, cap, SW_WRONG_LENGTH);
  uint16_t sw = try_pin(apdu->data);
  if (sw == SW_OK) pin_verified = true;
  return status(resp, cap, sw);
}

static size_t change_reference_data(uint8_t *resp, size_t cap, const apdu_t *apdu) {
  if (apdu->p1 != 0x00 || apdu->p2 != 0x80) return status(resp, cap, SW_INCORRECT_P1P2);
  if (apdu->lc != 2 * PIN_LEN) return status(resp, cap, SW_WRONG_LENGTH);
  if (!pin_well_formed(apdu->data + PIN_LEN)) return status(resp, cap, SW_WRONG_DATA);
  uint16_t sw = try_pin(apdu->data);
  if (sw != SW_OK) return status(resp, cap, sw);
  memcpy(pin, apdu->data + PIN_LEN, PIN_LEN);
  nvs_set_blob(store, "pin", pin, sizeof(pin));
  nvs_commit(store);
  pin_verified = true;
  return status(resp, cap, SW_OK);
}

// The dynamic authentication template 7C: for 9A a challenge in 81 to sign,
// for 9D a public point in 85 to agree on; 82 00 asks for the response.
static bool parse_authentication(const apdu_t *apdu, uint8_t wanted, const uint8_t **value, size_t *value_len) {
  if (apdu->lc < 2 || apdu->data[0] != 0x7C) return false;
  size_t off = 1, outer;
  if (apdu->data[off] & 0x80) {
    size_t n = apdu->data[off] & 0x7F;
    if (n == 0 || n > 2 || off + 1 + n > apdu->lc) return false;
    outer = 0;
    for (size_t i = 0; i < n; i++) outer = outer << 8 | apdu->data[off + 1 + i];
    off += 1 + n;
  } else {
    outer = apdu->data[off++];
  }
  if (off + outer != apdu->lc) return false;
  *value = NULL;
  bool asked = false;
  while (off < apdu->lc) {
    uint8_t tag = apdu->data[off++];
    if (off >= apdu->lc) return false;
    size_t len = apdu->data[off++];
    if (len & 0x80) {
      size_t n = len & 0x7F;
      if (n == 0 || n > 2 || off + n > apdu->lc) return false;
      len = 0;
      for (size_t i = 0; i < n; i++) len = len << 8 | apdu->data[off++];
    }
    if (off + len > apdu->lc) return false;
    if (tag == wanted && len > 0) { *value = apdu->data + off; *value_len = len; }
    else if (tag == 0x82 && len == 0) asked = true;
    else return false;
    off += len;
  }
  return *value != NULL && asked;
}

static size_t authentication_reply(uint8_t *resp, size_t cap, const uint8_t *value, size_t len) {
  uint8_t out[8 + 80];
  size_t n = 0;
  out[n++] = 0x7C;
  n += put_len(out + n, 1 + (len < 0x80 ? 1 : 2) + len);
  out[n++] = 0x82;
  n += put_len(out + n, len);
  memcpy(out + n, value, len);
  n += len;
  return reply(resp, cap, out, n, 0);
}

static size_t general_authenticate(uint8_t *resp, size_t cap, const apdu_t *apdu) {
  if (apdu->p1 != 0x11) return status(resp, cap, SW_INCORRECT_P1P2);  // only ECC P-256
  slot_t *slot = apdu->p2 == 0x9A ? &auth_slot : apdu->p2 == 0x9D ? &key_mgmt_slot : NULL;
  if (!slot) return status(resp, cap, SW_INCORRECT_P1P2);
  if (!identity_loaded) return status(resp, cap, SW_CONDITIONS_NOT_SATISFIED);
  if (!pin_verified) return status(resp, cap, SW_SECURITY_STATUS);

  const uint8_t *value;
  size_t value_len;
  if (slot == &auth_slot) {
    if (!parse_authentication(apdu, 0x81, &value, &value_len) || value_len > 64) return status(resp, cap, SW_WRONG_DATA);
    uint8_t sig[MBEDTLS_ECDSA_MAX_LEN];
    size_t sig_len = 0;
    int rc = mbedtls_ecdsa_write_signature(mbedtls_pk_ec(slot->key), MBEDTLS_MD_SHA256, value, value_len,
                                           sig, sizeof(sig), &sig_len, rng, NULL);
    if (rc != 0) { ESP_LOGE(TAG, "sign failed -0x%x", -rc); return status(resp, cap, SW_UNKNOWN); }
    return authentication_reply(resp, cap, sig, sig_len);
  }

  if (!parse_authentication(apdu, 0x85, &value, &value_len)) return status(resp, cap, SW_WRONG_DATA);
  mbedtls_ecp_group grp;
  mbedtls_ecp_point peer;
  mbedtls_mpi d, z;
  mbedtls_ecp_group_init(&grp); mbedtls_ecp_point_init(&peer); mbedtls_mpi_init(&d); mbedtls_mpi_init(&z);
  uint8_t shared[32];
  int rc = mbedtls_ecp_export(mbedtls_pk_ec(slot->key), &grp, &d, NULL);
  if (rc == 0) rc = mbedtls_ecp_point_read_binary(&grp, &peer, value, value_len);
  if (rc == 0) rc = mbedtls_ecdh_compute_shared(&grp, &z, &peer, &d, rng, NULL);
  if (rc == 0) rc = mbedtls_mpi_write_binary(&z, shared, sizeof(shared));
  mbedtls_ecp_group_free(&grp); mbedtls_ecp_point_free(&peer); mbedtls_mpi_free(&d); mbedtls_mpi_free(&z);
  if (rc != 0) { ESP_LOGE(TAG, "key agreement failed -0x%x", -rc); return status(resp, cap, SW_WRONG_DATA); }
  size_t n = authentication_reply(resp, cap, shared, sizeof(shared));
  memset(shared, 0, sizeof(shared));
  return n;
}

size_t piv_apdu(const uint8_t *cmd, size_t len, uint8_t *resp, size_t cap) {
  if (cap < 2) return 0;
  apdu_t apdu;
  if (!parse_apdu(cmd, len, &apdu)) return status(resp, cap, SW_WRONG_LENGTH);
  if (apdu.cla != 0x00) return status(resp, cap, SW_CLA_NOT_SUPPORTED);
  xSemaphoreTake(lock, portMAX_DELAY);
  if (apdu.ins != 0xC0) pending_len = pending_off = 0;
  size_t n;
  switch (apdu.ins) {
    case 0xA4: n = select_application(resp, cap, &apdu); break;
    case 0xCB: n = get_data(resp, cap, &apdu); break;
    case 0xC0: n = get_response(resp, cap, &apdu); break;
    case 0x20: n = verify(resp, cap, &apdu); break;
    case 0x24: n = change_reference_data(resp, cap, &apdu); break;
    case 0x87: n = general_authenticate(resp, cap, &apdu); break;
    default: n = status(resp, cap, SW_INS_NOT_SUPPORTED); break;
  }
  xSemaphoreGive(lock);
  return n;
}

void piv_session_reset(void) {
  if (!lock) return;
  xSemaphoreTake(lock, portMAX_DELAY);
  pin_verified = false;
  pending_len = pending_off = 0;
  xSemaphoreGive(lock);
}

void piv_init(void) {
  lock = xSemaphoreCreateMutex();
  configASSERT(lock);
  ESP_ERROR_CHECK(nvs_open("piv", NVS_READWRITE, &store));
  mbedtls_pk_init(&auth_slot.key);
  mbedtls_pk_init(&key_mgmt_slot.key);
  load_identity();
  load_pin();
  ESP_LOGI(TAG, "%s", identity_loaded ? "card ready with identity" : "card ready, no identity yet");
}

#include "piv.h"

#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "mbedtls/sha256.h"

static const char *TAG = "piv";

// Status words.
#define SW_OK 0x9000
#define SW_MORE 0x6100
#define SW_WRONG_LENGTH 0x6700
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
// issuer signature. The GUID is filled in by piv_set_token_id.
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
  // Certificates arrive with the key in docs/PIV.md step 3.
  if (tag_is(apdu, tag_auth_cert, sizeof(tag_auth_cert)) || tag_is(apdu, tag_key_mgmt_cert, sizeof(tag_key_mgmt_cert)))
    return status(resp, cap, SW_REFERENCE_NOT_FOUND);
  return status(resp, cap, SW_REFERENCE_NOT_FOUND);
}

size_t piv_apdu(const uint8_t *cmd, size_t len, uint8_t *resp, size_t cap) {
  if (cap < 2) return 0;
  apdu_t apdu;
  if (!parse_apdu(cmd, len, &apdu)) return status(resp, cap, SW_WRONG_LENGTH);
  if (apdu.cla != 0x00) return status(resp, cap, SW_CLA_NOT_SUPPORTED);
  if (apdu.ins != 0xC0) pending_len = pending_off = 0;
  switch (apdu.ins) {
    case 0xA4: return select_application(resp, cap, &apdu);
    case 0xCB: return get_data(resp, cap, &apdu);
    case 0xC0: return get_response(resp, cap, &apdu);
    case 0x20:  // VERIFY
    case 0x24:  // CHANGE REFERENCE DATA
    case 0x87:  // GENERAL AUTHENTICATE
      return status(resp, cap, SW_CONDITIONS_NOT_SATISFIED);  // no key yet, step 3
    default:
      return status(resp, cap, SW_INS_NOT_SUPPORTED);
  }
}

// The CHUID's GUID is what CryptoTokenKit files the card under, so it must
// change whenever the identity does. Until there is a certificate it comes
// from the chip's address, so an unprovisioned board is at least stable.
static void set_token_id(const uint8_t *seed, size_t len) {
  uint8_t digest[32];
  mbedtls_sha256(seed, len, digest, 0);
  uint8_t *guid = chuid + CHUID_GUID_OFFSET;
  memcpy(guid, digest, 16);
  guid[6] = (guid[6] & 0x0F) | 0x40;  // RFC 4122 version 4 shape
  guid[8] = (guid[8] & 0x3F) | 0x80;
}

void piv_init(void) {
  uint8_t mac[6];
  if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) set_token_id(mac, sizeof(mac));
  ESP_LOGI(TAG, "card ready, no identity yet");
}

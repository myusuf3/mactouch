#define __STDC_WANT_LIB_EXT1__ 1
#include "approve.h"

#include <CommonCrypto/CommonHMAC.h>
#include <ctype.h>
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

// Time the daemon gets past the identify timeout to relay the device's answer.
#define MT_REPLY_GRACE_MS 5000

static int nibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static void hex_encode(const uint8_t *in, size_t len, char *out) {
  static const char digits[] = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) {
    out[i * 2] = digits[in[i] >> 4];
    out[i * 2 + 1] = digits[in[i] & 0xf];
  }
  out[len * 2] = '\0';
}

bool mt_parse_key(const char *hex, uint8_t key[MT_KEY_LEN]) {
  if (!hex || strlen(hex) != MT_KEY_LEN * 2) return false;
  for (size_t i = 0; i < MT_KEY_LEN; i++) {
    int hi = nibble(hex[i * 2]), lo = nibble(hex[i * 2 + 1]);
    if (hi < 0 || lo < 0) return false;
    key[i] = (uint8_t)(hi << 4 | lo);
  }
  return true;
}

bool mt_read_key_file(const char *path, uint8_t key[MT_KEY_LEN]) {
  FILE *f = fopen(path, "r");
  if (!f) return false;
  char line[MT_KEY_LEN * 2 + 4] = {0};
  bool ok = fgets(line, sizeof line, f) != NULL;
  fclose(f);
  if (ok) {
    line[strcspn(line, "\r\n")] = '\0';
    ok = mt_parse_key(line, key);
  }
  memset_s(line, sizeof line, 0, sizeof line);
  return ok;
}

void mt_sign(const uint8_t key[MT_KEY_LEN], const char *nonce_hex, unsigned slot, char mac_hex[MT_MAC_HEX + 1]) {
  // The firmware lower-cases the nonce before signing; mirror that.
  char nonce[MT_NONCE_HEX + 1] = {0};
  for (size_t i = 0; i < MT_NONCE_HEX && nonce_hex[i]; i++) nonce[i] = (char)tolower((unsigned char)nonce_hex[i]);
  char material[MT_NONCE_HEX + 32];
  snprintf(material, sizeof material, "IDENTIFY|%s|%u", nonce, slot);
  uint8_t mac[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, key, MT_KEY_LEN, material, strlen(material), mac);
  hex_encode(mac, sizeof mac, mac_hex);
}

bool mt_verify(const uint8_t key[MT_KEY_LEN], const char *nonce_hex, unsigned slot, const char *mac_hex) {
  if (!nonce_hex || strlen(nonce_hex) != MT_NONCE_HEX) return false;
  if (!mac_hex || strlen(mac_hex) != MT_MAC_HEX) return false;
  char expected[MT_MAC_HEX + 1];
  mt_sign(key, nonce_hex, slot, expected);
  unsigned diff = 0;
  for (size_t i = 0; i < MT_MAC_HEX; i++) {
    diff |= (unsigned)expected[i] ^ (unsigned)tolower((unsigned char)mac_hex[i]);
  }
  return diff == 0;
}

static int64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// Reads one newline-terminated line, byte by byte; lines are short and this
// runs once per sudo. False on deadline, EOF or error.
static bool read_line(int fd, char *buf, size_t cap, int64_t deadline) {
  size_t len = 0;
  while (len + 1 < cap) {
    int64_t remaining = deadline - now_ms();
    if (remaining <= 0) return false;
    struct pollfd p = {.fd = fd, .events = POLLIN};
    int ready = poll(&p, 1, (int)(remaining > INT32_MAX ? INT32_MAX : remaining));
    if (ready < 0 && errno == EINTR) continue;
    if (ready <= 0) return false;
    char c;
    ssize_t n = read(fd, &c, 1);
    if (n <= 0) return false;
    if (c == '\n') break;
    if (c != '\r') buf[len++] = c;
  }
  buf[len] = '\0';
  return true;
}

static bool write_all(int fd, const char *buf, size_t len) {
  while (len > 0) {
    ssize_t n = write(fd, buf, len);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return false;
    buf += n;
    len -= (size_t)n;
  }
  return true;
}

// Copies the value of ` key=` from a reply line, or returns false.
static bool field(const char *line, const char *key, char *out, size_t cap) {
  char needle[32];
  snprintf(needle, sizeof needle, " %s=", key);
  const char *p = strstr(line, needle);
  if (!p) return false;
  p += strlen(needle);
  size_t n = strcspn(p, " ");
  if (n == 0 || n >= cap) return false;
  memcpy(out, p, n);
  out[n] = '\0';
  return true;
}

mt_result_t mt_request_approval(const char *socket_path, const uint8_t key[MT_KEY_LEN],
                                unsigned timeout_s, const char *reason, char err[MT_ERR_LEN]) {
  err[0] = '\0';
  struct sockaddr_un addr = {.sun_family = AF_UNIX};
  if (strlen(socket_path) >= sizeof addr.sun_path) {
    snprintf(err, MT_ERR_LEN, "socket path too long");
    return MT_UNAVAILABLE;
  }
  strcpy(addr.sun_path, socket_path);

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0 || connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
    snprintf(err, MT_ERR_LEN, "cannot reach mactouchd: %s", strerror(errno));
    if (fd >= 0) close(fd);
    return MT_UNAVAILABLE;
  }

  uint8_t nonce[MT_NONCE_HEX / 2];
  arc4random_buf(nonce, sizeof nonce);
  char nonce_hex[MT_NONCE_HEX + 1];
  hex_encode(nonce, sizeof nonce, nonce_hex);

  // The reason runs to the end of the line, so it must not contain one.
  char clean_reason[96];
  snprintf(clean_reason, sizeof clean_reason, "%s", reason ? reason : "sudo");
  for (char *c = clean_reason; *c; c++) if (*c == '\n' || *c == '\r') *c = ' ';

  char request[256];
  int n = snprintf(request, sizeof request, "identify timeout=%u nonce=%s reason=%s\n", timeout_s, nonce_hex, clean_reason);
  if (n <= 0 || (size_t)n >= sizeof request || !write_all(fd, request, (size_t)n)) {
    snprintf(err, MT_ERR_LEN, "cannot send the request: %s", strerror(errno));
    close(fd);
    return MT_UNAVAILABLE;
  }

  int64_t deadline = now_ms() + (int64_t)timeout_s * 1000 + MT_REPLY_GRACE_MS;
  char line[512];
  while (read_line(fd, line, sizeof line, deadline)) {
    if (strncmp(line, "evt ", 4) == 0) continue;
    if (strncmp(line, "ok identify", 11) == 0) {
      close(fd);
      char slot_text[16], mac[MT_MAC_HEX + 1];
      if (!field(line, "slot", slot_text, sizeof slot_text) || !field(line, "mac", mac, sizeof mac)) {
        snprintf(err, MT_ERR_LEN, "reply without a slot or a signature");
        return MT_DENIED;
      }
      unsigned slot = (unsigned)strtoul(slot_text, NULL, 10);
      if (mt_verify(key, nonce_hex, slot, mac)) return MT_APPROVED;
      snprintf(err, MT_ERR_LEN, "signature did not verify for slot %u", slot);
      return MT_DENIED;
    }
    if (strncmp(line, "err identify", 12) == 0) {
      close(fd);
      const char *r = strstr(line, "reason=");
      snprintf(err, MT_ERR_LEN, "mactouchd: %s", r ? r + 7 : line);
      return MT_UNAVAILABLE;
    }
  }
  close(fd);
  snprintf(err, MT_ERR_LEN, "no answer from mactouchd within %u s", timeout_s + MT_REPLY_GRACE_MS / 1000);
  return MT_UNAVAILABLE;
}

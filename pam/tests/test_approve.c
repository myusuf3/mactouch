// Pins approve.c to docs/protocol-vectors.json through the same header the
// firmware compiles in, then drives mt_request_approval against a fake
// daemon on a unix socket.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include "approve.h"
#include "vectors.h"

static int failures = 0;
#define CHECK(cond, name) do { if (cond) printf("ok   %s\n", name); else { printf("FAIL %s\n", name); failures++; } } while (0)

static void hex(const uint8_t *in, size_t n, char *out) {
  for (size_t i = 0; i < n; i++) sprintf(out + i * 2, "%02x", in[i]);
}

static void test_vectors(void) {
  char key_hex[MT_KEY_LEN * 2 + 1];
  hex(VECTOR_DEVICE_KEY, MT_KEY_LEN, key_hex);
  uint8_t key[MT_KEY_LEN];
  CHECK(mt_parse_key(key_hex, key) && memcmp(key, VECTOR_DEVICE_KEY, MT_KEY_LEN) == 0, "parses the vector key");
  CHECK(!mt_parse_key("abc", key), "rejects a short key");
  CHECK(!mt_parse_key("zz00000000000000000000000000000000000000000000000000000000000000", key), "rejects non-hex");

  char mac[MT_MAC_HEX + 1];
  mt_sign(VECTOR_DEVICE_KEY, VECTOR_NONCE, VECTOR_SLOT, mac);
  CHECK(strcmp(mac, VECTOR_MAC) == 0, "signature matches docs/protocol-vectors.json");
  CHECK(mt_verify(VECTOR_DEVICE_KEY, VECTOR_NONCE, VECTOR_SLOT, VECTOR_MAC), "verify accepts the vector");
  CHECK(!mt_verify(VECTOR_DEVICE_KEY, VECTOR_NONCE, VECTOR_SLOT + 1, VECTOR_MAC), "verify rejects another slot");
  char tampered[MT_MAC_HEX + 1];
  strcpy(tampered, VECTOR_MAC);
  tampered[MT_MAC_HEX - 1] = tampered[MT_MAC_HEX - 1] == '0' ? '1' : '0';
  CHECK(!mt_verify(VECTOR_DEVICE_KEY, VECTOR_NONCE, VECTOR_SLOT, tampered), "verify rejects a flipped digit");
  CHECK(!mt_verify(VECTOR_DEVICE_KEY, VECTOR_NONCE, VECTOR_SLOT, "zz"), "verify rejects malformed hex");

  char path[] = "/tmp/mt-key-XXXXXX";
  int fd = mkstemp(path);
  write(fd, key_hex, MT_KEY_LEN * 2);
  write(fd, "\n", 1);
  close(fd);
  uint8_t from_file[MT_KEY_LEN];
  CHECK(mt_read_key_file(path, from_file) && memcmp(from_file, key, MT_KEY_LEN) == 0, "reads a key file");
  unlink(path);
  CHECK(!mt_read_key_file(path, from_file), "missing key file fails");
}

typedef enum { FAKE_GOOD, FAKE_REPLAY, FAKE_WRONG_SLOT, FAKE_ERR_TIMEOUT, FAKE_HANG_UP } fake_t;

// Binds before forking so the parent can connect at once; the child answers
// one request the way a daemon would, then exits.
static pid_t start_fake(const char *path, fake_t kind) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  struct sockaddr_un addr = {.sun_family = AF_UNIX};
  strcpy(addr.sun_path, path);
  unlink(path);
  if (bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 1) != 0) { perror("fake bind"); exit(2); }
  pid_t pid = fork();
  if (pid != 0) { close(fd); return pid; }

  int c = accept(fd, NULL, NULL);
  char line[512] = {0};
  size_t len = 0;
  while (len + 1 < sizeof line && read(c, line + len, 1) == 1) { if (line[len] == '\n') break; len++; }
  line[len] = '\0';
  char nonce[MT_NONCE_HEX + 1] = {0};
  const char *p = strstr(line, "nonce=");
  if (p) strncpy(nonce, p + 6, MT_NONCE_HEX);

  const char *event = "evt request state=pending\n";
  write(c, event, strlen(event));
  char mac[MT_MAC_HEX + 1], reply[256];
  switch (kind) {
  case FAKE_GOOD:
    mt_sign(VECTOR_DEVICE_KEY, nonce, 3, mac);
    snprintf(reply, sizeof reply, "ok identify score=100 slot=3 mac=%s\n", mac);
    break;
  case FAKE_REPLAY:
    snprintf(reply, sizeof reply, "ok identify score=100 slot=%u mac=%s\n", VECTOR_SLOT, VECTOR_MAC);
    break;
  case FAKE_WRONG_SLOT:
    mt_sign(VECTOR_DEVICE_KEY, nonce, 3, mac);
    snprintf(reply, sizeof reply, "ok identify score=100 slot=4 mac=%s\n", mac);
    break;
  case FAKE_ERR_TIMEOUT:
    snprintf(reply, sizeof reply, "err identify reason=timeout\n");
    break;
  case FAKE_HANG_UP:
    reply[0] = '\0';
    break;
  }
  if (reply[0]) write(c, reply, strlen(reply));
  close(c);
  close(fd);
  _exit(0);
}

static void test_socket(void) {
  char dir[] = "/tmp/mt-sock-XXXXXX";
  if (!mkdtemp(dir)) { perror("mkdtemp"); exit(2); }
  char path[128];
  snprintf(path, sizeof path, "%s/control.sock", dir);

  struct { fake_t kind; mt_result_t want; const char *name; } cases[] = {
    {FAKE_GOOD, MT_APPROVED, "fresh signature is approved"},
    {FAKE_REPLAY, MT_DENIED, "signature from an old nonce is denied"},
    {FAKE_WRONG_SLOT, MT_DENIED, "signature claiming another slot is denied"},
    {FAKE_ERR_TIMEOUT, MT_UNAVAILABLE, "daemon timeout falls back to the password"},
    {FAKE_HANG_UP, MT_UNAVAILABLE, "daemon hanging up falls back to the password"},
  };
  for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
    pid_t pid = start_fake(path, cases[i].kind);
    char err[MT_ERR_LEN];
    mt_result_t got = mt_request_approval(path, VECTOR_DEVICE_KEY, 5, "test", err);
    waitpid(pid, NULL, 0);
    unlink(path);
    if (got != cases[i].want) printf("     got %d, err: %s\n", got, err);
    CHECK(got == cases[i].want, cases[i].name);
    if (got != MT_APPROVED) CHECK(err[0] != '\0', "  ...with an explanation for the log");
  }
  char err[MT_ERR_LEN];
  CHECK(mt_request_approval(path, VECTOR_DEVICE_KEY, 1, "test", err) == MT_UNAVAILABLE, "missing daemon falls back to the password");
  rmdir(dir);
}

int main(void) {
  test_vectors();
  test_socket();
  printf("%s\n", failures ? "FAILED" : "all passed");
  return failures ? 1 : 0;
}

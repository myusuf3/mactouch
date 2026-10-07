// Host tests for unlock.c (ADR-0022): the unlock mode names and how a
// password becomes keystrokes.
#include <stdio.h>
#include <string.h>

#include "unlock.h"

static int failures = 0;
#define CHECK(cond, name) do { if (cond) printf("ok   %s\n", name); else { printf("FAIL %s\n", name); failures++; } } while (0)

#define SHIFT 0x02
#define RETURN 0x28

static void test_names(void) {
  unlock_mode_t mode = UNLOCK_PASSWORD;
  CHECK(unlock_parse_mode("pin", &mode) && mode == UNLOCK_PIN, "parses pin");
  CHECK(unlock_parse_mode("password", &mode) && mode == UNLOCK_PASSWORD, "parses password");
  CHECK(!unlock_parse_mode("touch", &mode) && !unlock_parse_mode("PASSWORD", &mode) && !unlock_parse_mode("", &mode),
        "rejects other spellings");
  CHECK(strcmp(unlock_mode_name(UNLOCK_PIN), "pin") == 0 && strcmp(unlock_mode_name(UNLOCK_PASSWORD), "password") == 0,
        "names the modes");
  CHECK(strcmp(unlock_mode_name((unlock_mode_t)7), "pin") == 0, "an unknown stored mode reads as pin");
}

static bool keys_are(const typing_key_t *keys, size_t n, const typing_key_t *want, size_t want_n) {
  if (n != want_n) return false;
  for (size_t i = 0; i < n; i++) {
    if (keys[i].modifier != want[i].modifier || keys[i].code != want[i].code) return false;
  }
  return true;
}

static void test_text_keys(void) {
  typing_key_t keys[UNLOCK_MAX_KEYS];
  const char *text = "aZ0 9!";
  const typing_key_t want[] = {
    {0, 0x04}, {SHIFT, 0x1D}, {0, 0x62}, {0, 0x2C}, {0, 0x61}, {SHIFT, 0x1E}, {0, RETURN},
  };
  size_t n = unlock_text_keys((const uint8_t *)text, strlen(text), keys);
  CHECK(keys_are(keys, n, want, sizeof(want) / sizeof(want[0])), "letters, keypad digits, space and shifted symbols, then Return");

  const char *symbols = "-_=+[{]}\\|;:'\",<.>/?`~@#$%^&*()";
  const typing_key_t want_symbols[] = {
    {0, 0x2D}, {SHIFT, 0x2D}, {0, 0x2E}, {SHIFT, 0x2E}, {0, 0x2F}, {SHIFT, 0x2F}, {0, 0x30}, {SHIFT, 0x30},
    {0, 0x31}, {SHIFT, 0x31}, {0, 0x33}, {SHIFT, 0x33}, {0, 0x34}, {SHIFT, 0x34}, {0, 0x36}, {SHIFT, 0x36},
    {0, 0x37}, {SHIFT, 0x37}, {0, 0x38}, {SHIFT, 0x38}, {0, 0x35}, {SHIFT, 0x35}, {SHIFT, 0x1F}, {SHIFT, 0x20},
    {SHIFT, 0x21}, {SHIFT, 0x22}, {SHIFT, 0x23}, {SHIFT, 0x24}, {SHIFT, 0x25}, {SHIFT, 0x26}, {SHIFT, 0x27},
    {0, RETURN},
  };
  n = unlock_text_keys((const uint8_t *)symbols, strlen(symbols), keys);
  CHECK(keys_are(keys, n, want_symbols, sizeof(want_symbols) / sizeof(want_symbols[0])), "every US symbol");

  char longest[UNLOCK_MAX_TEXT + 2];
  memset(longest, 'x', sizeof(longest));
  CHECK(unlock_text_keys((const uint8_t *)longest, UNLOCK_MAX_TEXT, keys) == UNLOCK_MAX_TEXT + 1, "takes the longest password");
  CHECK(unlock_text_keys((const uint8_t *)longest, UNLOCK_MAX_TEXT + 1, keys) == 0, "refuses a longer one");
  CHECK(unlock_text_keys((const uint8_t *)"", 0, keys) == 0, "refuses an empty password");
  CHECK(unlock_text_keys((const uint8_t *)"caf\xc3\xa9", 5, keys) == 0, "refuses what it cannot type");
  CHECK(unlock_text_keys((const uint8_t *)"a\tb", 3, keys) == 0, "refuses control characters");
}

int main(void) {
  test_names();
  test_text_keys();
  if (failures) {
    printf("%d failed\n", failures);
    return 1;
  }
  printf("all passed\n");
  return 0;
}

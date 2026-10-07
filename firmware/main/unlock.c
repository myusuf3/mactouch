#include "unlock.h"

#include <string.h>

// HID usage IDs, keyboard page.
#define SHIFT 0x02
#define KEY_A 0x04
#define KEY_1 0x1E
#define KEY_0 0x27
#define KEY_KEYPAD_1 0x59
#define KEY_KEYPAD_0 0x62
#define KEY_RETURN 0x28
#define KEY_SPACE 0x2C

// The US symbols: the character, whether it takes Shift, and its key.
static const struct { char c; bool shift; uint8_t code; } symbols[] = {
  {'-', false, 0x2D}, {'_', true, 0x2D}, {'=', false, 0x2E}, {'+', true, 0x2E},
  {'[', false, 0x2F}, {'{', true, 0x2F}, {']', false, 0x30}, {'}', true, 0x30},
  {'\\', false, 0x31}, {'|', true, 0x31}, {';', false, 0x33}, {':', true, 0x33},
  {'\'', false, 0x34}, {'"', true, 0x34}, {'`', false, 0x35}, {'~', true, 0x35},
  {',', false, 0x36}, {'<', true, 0x36}, {'.', false, 0x37}, {'>', true, 0x37},
  {'/', false, 0x38}, {'?', true, 0x38},
  {'!', true, KEY_1}, {'@', true, KEY_1 + 1}, {'#', true, KEY_1 + 2}, {'$', true, KEY_1 + 3},
  {'%', true, KEY_1 + 4}, {'^', true, KEY_1 + 5}, {'&', true, KEY_1 + 6}, {'*', true, KEY_1 + 7},
  {'(', true, KEY_1 + 8}, {')', true, KEY_0},
};

const char *unlock_mode_name(unlock_mode_t mode) { return mode == UNLOCK_PASSWORD ? "password" : "pin"; }

bool unlock_parse_mode(const char *name, unlock_mode_t *out) {
  if (strcmp(name, "pin") == 0) { *out = UNLOCK_PIN; return true; }
  if (strcmp(name, "password") == 0) { *out = UNLOCK_PASSWORD; return true; }
  return false;
}

static bool key_for(uint8_t c, typing_key_t *key) {
  if (c >= 'a' && c <= 'z') { *key = (typing_key_t){0, (uint8_t)(KEY_A + c - 'a')}; return true; }
  if (c >= 'A' && c <= 'Z') { *key = (typing_key_t){SHIFT, (uint8_t)(KEY_A + c - 'A')}; return true; }
  if (c == '0') { *key = (typing_key_t){0, KEY_KEYPAD_0}; return true; }
  if (c >= '1' && c <= '9') { *key = (typing_key_t){0, (uint8_t)(KEY_KEYPAD_1 + c - '1')}; return true; }
  if (c == ' ') { *key = (typing_key_t){0, KEY_SPACE}; return true; }
  for (size_t i = 0; i < sizeof(symbols) / sizeof(symbols[0]); i++) {
    if ((uint8_t)symbols[i].c == c) {
      *key = (typing_key_t){symbols[i].shift ? SHIFT : 0, symbols[i].code};
      return true;
    }
  }
  return false;
}

size_t unlock_text_keys(const uint8_t *text, size_t len, typing_key_t keys[UNLOCK_MAX_KEYS]) {
  if (len == 0 || len > UNLOCK_MAX_TEXT) return 0;
  for (size_t i = 0; i < len; i++) {
    if (!key_for(text[i], &keys[i])) return 0;
  }
  keys[len] = (typing_key_t){0, KEY_RETURN};
  return len + 1;
}

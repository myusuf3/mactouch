#include "piv.h"

// Step 1 of docs/PIV.md: a card that is present and answers nothing, so the
// reader can be brought up and checked against the Mac before the applet
// exists. 6D00 is "instruction not supported".
size_t piv_apdu(const uint8_t *cmd, size_t len, uint8_t *resp, size_t cap) {
  (void)cmd;
  (void)len;
  if (cap < 2) return 0;
  resp[0] = 0x6D;
  resp[1] = 0x00;
  return 2;
}

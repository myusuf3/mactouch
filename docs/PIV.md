# PIV screen unlock plan

ADR-0013 decided that unlocking the Mac goes through PIV smart card emulation
on the device, PIN plus finger, with the daemon out of the path. This is the
plan for building it: what the device pretends to be, what macOS needs from
it, what was checked on this Mac, and the order the work lands in.

## What it is

The board adds a USB CCID interface beside its serial link, so the Mac sees a
smart card reader with one card always inserted. The card is a PIV applet in
firmware: one ECC P-256 key generated on the device and never exported, a
self-signed certificate for it, a PIN, and the handful of commands macOS's
own PIV token driver sends. macOS pairs the card to the account with its
built-in smart card support, which works at the lock screen and at the login
window after a restart, before any daemon exists.

The finger gates signing. `GENERAL AUTHENTICATE` succeeds if an enrolled
finger matched in the last few seconds, and otherwise waits for one while the
ring breathes, holding the host off with CCID time extensions; without a
finger it fails. So touch then PIN and PIN then touch both work. The PIN
stays a real PIN that the user types and the card verifies. tinyTouch instead
fixes the PIN and types it itself over a USB keyboard interface once the
finger matches; this project has no keyboard (ADR-0006) and wants two
factors (ADR-0013), so the PIN is real.

## What was checked on this Mac (macOS 26.6.2)

- The CCID reader driver is Apple's build of libccid 1.5.1, installed as a
  class driver (`CFBundleName` is `CCIDCLASSDRIVER`). Its plist lists 555
  readers by vendor and product ID and Espressif's vendor ID is not among
  them. libccid built as a class driver also matches any interface of class
  0x0B. tinyTouch, the project this one grew out of, pairs with macOS using
  Espressif's vendor ID and TinyUSB's default product ID, and step 1
  confirmed it for this board on 2026-09-21: macOS listed "mactouch smart
  card" with our ATR and `pcsctest` connected over T=1 with no driver
  installed.
- `com.apple.CryptoTokenKit.pivtoken` is present, so no token driver is
  needed on the Mac side. `sc_auth` has `pair`, `unpair`, `identities`,
  `changepin`, `verifypin` and `list`.
- TinyUSB 0.19 has no CCID class; a custom class driver registers through
  `usbd_app_driver_get_cb`, which nothing else in the build defines.
- ESP-IDF's mbedtls has ECDSA on P-256 and PK and X.509 writing.
- The board has neither flash encryption nor secure boot yet. ADR-0013 makes
  them the gate before a real pairing; they burn eFuses and cannot be undone,
  so that step waits for an explicit go.

## What macOS's PIV token asks of the card

From SP 800-73-4, the behaviour of the built-in token, and tinyTouch's
working applet (`../tinyTouch/firmware/tiny_touch_unified/main/piv.c`), the
card answers:

- `SELECT` the PIV AID `A0 00 00 03 08 00 00 10 00 01 00` with the application
  property template.
- `GET DATA` for the CHUID (`5FC102`), the card capability container
  (`5FC107`), the discovery object (`7E`), the key history object (`5FC10C`,
  all zeros), and two certificates in the `70`/`71`/`FE` wrapping: PIV
  Authentication (`5FC105`, key 9A) and Key Management (`5FC10B`, key 9D).
  Pairing needs both: macOS wraps the login keychain with the key management
  key and uses it more than once while pairing. Other slots answer `6A88`.
  Responses longer than the host's `Le` use `61xx` and `GET RESPONSE`.
- The CHUID's GUID is the token identifier CryptoTokenKit caches objects
  under. It is derived from the authentication certificate, so a regenerated
  identity is a new token and never inherits a stale cache. After `GENKEY`
  the device drops off USB and re-enumerates so the Mac rescans the card.
- `VERIFY` (`00 20 00 80`) with the PIN padded to eight bytes, a retry counter
  in `63Cx`, and `CHANGE REFERENCE DATA` (`00 24 00 80`) so `sc_auth
  changepin` works. Three tries, then the card is blocked until a
  finger-gated reset from the CLI, which also destroys the key.
- `GENERAL AUTHENTICATE` (`00 87 11 9A`) with the `7C` template: challenge in
  `81`, ECDSA signature back in `82`, algorithm `11` for P-256. For 9D the
  same command carries the host's public point in `85` and the card answers
  the ECDH shared secret in `82`. ADR-0013 chose P-256 for both keys and the
  built-in token accepts that: it imports the ECC key management identity
  with derive, decrypt and unwrap usage, so RSA, which tinyTouch uses for
  both slots, is not needed anywhere. Command chaining is not implemented;
  macOS has not sent it.
- `GENERATE ASYMMETRIC KEY PAIR` and `PUT DATA` are not exposed to the host.
  Key and certificate come from the device link (`PIV GENKEY`), so nothing on
  the Mac can replace the key.

Pairing is local account pairing: the dialog appears when the card is
inserted, asks for an admin password and the PIN, and `sc_auth pair -h` does
the same from a shell. The certificate is self-signed; local pairing keys on
the public key hash, not on a chain.

## Firmware shape

- `ccid.c` is the USB class driver: one bulk OUT and one bulk IN endpoint, no
  interrupt endpoint (card is never removed), the 54-byte CCID class
  descriptor, and the message set the host uses: power on and off, slot
  status, parameters, abort, transfer block. It receives on the USB task and
  hands each APDU to its own task, so a signature that waits for a finger
  never blocks the serial link or the stack. A reply whose USB length is a
  multiple of 64 is followed by a zero-length packet, or the host waits
  forever; tinyTouch works around the same thing by shortening responses.
- `piv.c` is the card: APDU dispatch, the data objects, PIN state, and
  signing. It takes the sensor lock like `IDENTIFY` does and shares the ring.
- `piv_store` in NVS: key, certificate, PIN, retry counter, enabled flag. The
  flag is off by default; with it off the reader still enumerates but the card
  reports absent, so an unpaired device is invisible to macOS.
- The serial link gains `PIV STATUS|ON|OFF|GENKEY|RESET|CERT` and STATUS gains
  `piv=on|off`. Events `EVT PIV state=pending|done` mirror `EVT REQUEST`, so
  the daemon and app can show the request panel for a PIV touch too.

## Checking the card

`scripts/apdu.py` talks to the card through PC/SC with no packages and no
entitlement: `select`, `get <tag>` with chaining handled, a raw hex APDU, or
one APDU per line on stdin. It is how every step below is checked before
`sc_auth` is involved.

## Mac shape

- `mactouch piv status|on|off|genkey|reset` pass through the daemon.
- `mactouch piv pair|unpair` wrap `sc_auth`: list identities, find ours by
  the certificate's key hash, pair it to the current user, and print the
  recovery notes first: never turn on smart card enforcement, keep the
  password, keep a second admin.
- doctor gets a `piv` row: off, on but unpaired, paired, or blocked.
- The app gets a PIV pane later: state, on/off, pair, change PIN.

## Order of work

Each step ships on its own and is verified on the real hardware and this Mac.

1. **CCID reader skeleton.** Composite CDC plus CCID, class descriptor, the
   message set, an ATR, a card that rejects every APDU. Verify: the reader
   appears in `system_profiler SPSmartCardsDataType`, `pcsctest` connects
   and prints the ATR, `mactouch status` still works over the serial link.
   This is the step that settles the driver question.
2. **PIV data objects.** `SELECT`, `GET DATA` for CHUID, discovery, card
   capability container and key history, `GET RESPONSE` chaining, extended
   APDUs, `6A88` for the certificates until there is a key. Verify with
   `scripts/apdu.py`, and macOS's PIV token must claim the card:
   `system_profiler SPSmartCardsDataType` lists `com.apple.pivtoken:<GUID>`
   with the CHUID's GUID. Done 2026-09-21; the token appeared with no
   certificate present.
3. **Keys, certificates and PIN.** `PIV GENKEY` makes the two P-256 keys
   and self-signed certificates on the device, `VERIFY` with a retry
   counter, `CHANGE REFERENCE DATA`, `GENERAL AUTHENTICATE` signing for 9A
   and key agreement for 9D. Verify: `sc_auth identities` lists the card,
   `sc_auth verifypin` accepts the PIN, and the token shows both identities
   in `system_profiler SPSmartCardsDataType`. Done 2026-09-21: macOS
   imported both, the authentication key as "Sign" and the key management
   key as "Derive Decrypt Unwrap", so ECC P-256 is accepted for key
   management and the RSA fallback is not needed. A signature and a key
   agreement checked out through `scripts/apdu.py`. `ssh-keygen -D
   /usr/lib/ssh-keychain.dylib` reports "cannot read public key from
   pkcs11" against an unpaired token; it is not a check this step relies on.
4. **Finger gate.** Signing and key agreement need a match: one inside the
   ten-second window a touch opens, good for four operations, or a fresh one
   waited for up to fifteen seconds with CCID time extensions while the ring
   breathes white; `EVT PIV state=pending|done` on the link, and the daemon
   takes the ring back afterwards. Verify with `scripts/apdu.py`: a
   signature waits for a touch and fails with `6982` without one. Done
   2026-09-21: with a touch the wait ended in a match and a signature; with
   none the host was held fifteen seconds, PC/SC did not time out, and the
   card answered `6982`. The app's panel for PIV waits is step 8.
5. **CLI, daemon and doctor.** `mactouch piv on|off` with the card off by
   default and the slot reported empty while off, `piv=off|none|identity`
   in status, the doctor `unlock` row, `pair` and `unpair` around `sc_auth`
   with the recovery notes printed first. Done 2026-09-22: off, macOS lists
   no smart card and doctor says so; on, the token is back and doctor says
   "identity ready, not paired". `pair` itself is exercised in step 7.
   Lesson from this step: every CCID reply helper built a 3 KB message on
   the task stack, and one more of them overflowed it, so the board
   reboot-looped and never enumerated; replies are now written straight
   into the USB buffer and the task has a 12 KB stack.
6. **Flash encryption and secure boot.** Development mode first, release
   mode when the recovery path is written down; `PIV ON` refuses on a board
   without flash encryption. This burns eFuses and waited for a go, given
   2026-09-22 for development mode: flash encryption with NVS encryption and
   the `nvs_key` partition, download-mode encryption kept so the board stays
   reflashable, `flash.sh` writing encrypted from then on. The first
   encrypted boot wipes NVS, so the device key, the PIV identity and the
   settings start over (BUILDING.md says what to rerun). Release mode and
   secure boot v2 stay ahead of any board leaving the bench.
7. **Pair the account.** Second admin account in place, password kept, then
   pair. Verify: lock the screen, PIN then touch unlocks; restart, PIN then
   touch logs in; `sc_auth unpair` restores the password-only state.
   Paired 2026-09-25 with `mactouch piv pair`: `sc_auth list` shows the
   identity used for authentication and doctor's unlock row is green. The
   PIN was changed from the default with `sc_auth changepin`; the card only
   takes 6 to 8 digits and rejects anything else before it looks at the old
   PIN, so a malformed new PIN costs no try. The lock screen and restart
   checks are the owner's to run.
8. **App.** A Smart Card tab in Settings shows the card on or off, flash
   encryption, identity, PIN state and pairing, with Generate Identity,
   Pair with This Account (behind the administrator prompt, refused while
   the PIN is the default), Unpair, and Reset Card with a destructive
   confirmation. The PIN itself is changed with `sc_auth changepin`, since
   macOS asks for it in its own prompt. When the card waits for a finger
   the request panel shows "Smart card sign-in" without a Cancel button,
   because a waiting card cannot be interrupted. Doctor and `piv pair` both
   refuse to treat a card on the default PIN as ready.

Steps 1 to 5 risk nothing: the card is off by default and unpaired. Step 6
is the irreversible one. Step 7 is where the device becomes a credential.

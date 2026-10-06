# ADR-0022: Password Mode Types the Password After a Touch

## Status

Accepted. Amends [ADR-0006](0006-approval-primitive-not-credentials.md), which ruled out password typing, and [ADR-0013](0013-piv-for-screen-unlock.md), whose smart card stays the default.

## Context

ADR-0013 unlocks the Mac through the device's PIV card: macOS shows a PIN field, the user types the card's PIN, then touches. The owner wants what tinyTouch's HID mode gives instead: at the lock screen, or anywhere else a password is asked for, touch the sensor and the password is typed. macOS always asks a smart card for its PIN, so no card-based mode removes typing; the field the owner wants is the password field itself.

ADR-0006 ruled password typing out for two reasons. The device cannot see what has focus, so a match typed into a chat window types the password into the chat. And a password that crosses USB as keystrokes can be read by a hardware keylogger. tinyTouch accepts both and types on every match.

## Decision

The device gets an unlock mode, `pin` or `password`, persisted beside the card's other state and reset to `pin` with it. `pin` is ADR-0013 unchanged and the default.

In `password` mode the reader reports no card, so macOS shows its ordinary password field; the card's keys and the account's pairing are kept, so switching back to `pin` needs no re-pairing. The board also enumerates as a boot keyboard. The interface set is fixed at enumeration, so a change of mode that adds or removes the keyboard restarts the board, and is refused while a new image is on probation, because a restart then rolls it back.

The Mac decides when to type, because the Mac can see what the device cannot:

- mactouchd polls which process holds macOS's secure input, which is on exactly while a password field has focus, and treats the locked screen as a field too. MacTouch's own password sheet does not count.
- While a field has focus, mactouchd arms the sensor with a fresh nonce (`ARM nonce=…`), the ring breathes white, and the request panel names the app asking. When focus leaves, it disarms. Cancel in the panel disarms until focus moves on.
- The armed device runs a match on the next touch and reports it signed with the device key over the nonce, the identify signature of ADR-0009, then disarms itself. Only a match that verifies against the stored key and the current nonce gets the password, so a USB device posing as the sensor never receives it.
- mactouchd sends the password with `TYPE`. The device accepts it only within five seconds of its own armed match, once, types it and Return, and wipes it.

The password lives in the login keychain of mactouchd, which checks it against the account with Open Directory before keeping it. The device key comes from `PAIR` with a touch the first time and is kept beside it. The device never stores the password.

Characters are typed as a US keyboard layout types them, with digits on the keypad because those are the same in every layout. A password with other characters is refused when it is saved.

Typing waits whole scheduler ticks for the host to take each report, since at 100 Hz any shorter wait rounds to none, and always ends by sending every key up: a key left down auto-repeats into whatever has focus. `firmware/main/typing.c` holds that sequence, and its host tests drive it against a slow and a failing host. `firmware/main/unlock.c` holds the mode names and the character table; `PasswordArming` in MacTouchKit holds the Mac side's decisions; all three are tested without hardware.

## Consequences

In `password` mode the sensor unlocks with one factor: anyone with an enrolled finger, or with the case open and the sensor's serial line spoofed, gets the password typed. Enrolling a finger needs no existing match, so someone at an unlocked Mac can enrol their own. The app says this before switching.

The password crosses USB, on the serial link and as keystrokes, where a hardware keylogger can read it. That is ADR-0006's objection, accepted here by the owner.

Secure input is a good sign of a password field, not a perfect one. An app that keeps it on, such as Terminal with Secure Keyboard Entry enabled, counts as a field the whole time it has focus, and a touch types the password and Return into it. The request panel names the app so this is visible.

After a restart there is no session and no mactouchd, so the first login is typed by hand. FileVault's pre-boot screen is the same.

The password follows the account only when it is saved again; a changed Mac password needs `mactouch password set` or the app's Change….

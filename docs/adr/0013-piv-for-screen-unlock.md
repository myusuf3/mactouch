# ADR-0013: Screen Unlock Goes Through PIV Smart Card Emulation

## Status

Accepted

## Context

ADR-0006 made the device an approval primitive and gave up one thing: unlocking the Mac by finger. It named the two routes, typing the password over USB or emulating a PIV smart card, ruled the first out, deferred the second, and asked for a revisit "when the device and daemon are boring". The PAM module now runs sudo and su on a touch, and the attempt to extend it to the lock screen failed for a reason no signature can fix: `loginwindow` is a platform binary with library validation, and the kernel refuses to map any non-Apple library into it (ADR-0012). PAM cannot reach the lock screen. The revisit is due.

## Decision

Screen unlock will be a PIV mode on the device. The board adds a USB CCID interface beside its serial one and answers the subset of PIV that macOS needs: select, verify PIN, general authenticate for signing, and reading the certificate. macOS pairs the card to the account with its own smart card support, which works at the lock screen and at the login window after a restart, before any user session or daemon exists. The daemon is not in the unlock path.

The finger gates the signing command. A `GENERAL AUTHENTICATE` succeeds only if an enrolled finger matched within a short window, and the ring shows the wait. The PIN stays a real PIN, verified by the card, and is not waived by a match. Unlocking is therefore PIN plus finger, two factors, not finger alone. This is the same shape as a hardware security key with a touch requirement.

Password typing stays out. Nothing in this decision revisits that part of ADR-0006.

Prerequisites, in order, before the mode ships:

1. Flash encryption and secure boot enabled on the board. A PIV private key readable from flash would make the device a stolen credential, so these stop being advice and become the gate for the feature.
2. The key pair generated on the device and never exported. ECC P-256, which macOS accepts and mbedtls signs quickly on the ESP32-S3.
3. A pairing and unpairing flow through the CLI that wraps `sc_auth`, with a recovery path documented before the first pairing: never enable smart card enforcement, keep the password as fallback, and keep a second admin account.

## Consequences

The device becomes a credential. ADR-0006's consequence that a stolen device yields nothing that logs in narrows to: a stolen device yields nothing without the PIN and the paired Mac, and with flash encryption nothing that can be copied. Publishing the code still weakens nothing.

The finger replaces the password, not the PIN, so the gesture is type a short PIN then touch. Apple offers no API to do better without a platform entitlement.

This is the first mactouch feature where a firmware bug is a security hole rather than a wrong colour on the ring. CCID and PIV are well specified and testable against `pcsctest` and `sc_auth` without a Mac account at risk, and the mode ships behind a device setting that is off by default.

Sequencing: after the menu bar app (APP.md), since the app is where pairing state, PIN changes and the ring's PIV prompts will be surfaced.

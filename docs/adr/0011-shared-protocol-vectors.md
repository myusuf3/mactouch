# ADR-0011: Shared Test Vectors Pin the Approval Signature

## Status

Accepted

## Context

ADR-0009 puts an HMAC on every nonce-bearing identify. The firmware computes it in C over `IDENTIFY|<nonce>|<slot>`; the Mac side verifies it in Swift. Two implementations of one construction drift silently: a changed separator, an upper-case nonce, a slot printed with padding. None of those break the build or any existing test, and the first place the mismatch shows up is a PAM module rejecting a genuine touch, which locks the user out of `sudo` until they fall back to the password. The PAM install will also take a copy of the device key, so the verifier has to be trustworthy before that code exists, not after.

Dashboard Touch solved the same problem for its pairing HMAC with a generated vectors file that both sides must reproduce, and that approach carries over directly.

## Decision

`docs/protocol-vectors.json` is the normative example of the signature: a fixed device key and nonce that are counting byte patterns, a fixed slot, the exact material string, and its HMAC-SHA256. `scripts/gen-vectors.py` writes the file from Python's standard library and `--check` fails when the committed file is stale, which CI runs. The construction is documented in PROTOCOL.md next to the file, and any change to it starts by changing the generator.

The Mac side has one verifier, `ApprovalMAC` in MacTouchKit, and a test that loads the vectors file and requires the material, the computed MAC, and constant-time verification to match. Every consumer of the signature on the Mac, PAM first, calls that type rather than building the string itself.

The firmware is bound to the same file by `firmware/main/vectors.h`, which the generator writes alongside the JSON, and a `SELFTEST` command that signs the compiled-in vector with the vector key and compares. `mactouch doctor` runs it whenever the board is connected, so a mismatched flash shows up as a red row rather than a rejected `sudo`.

## Consequences

Drift between firmware and Swift becomes a red test instead of a field failure, and a third implementation, for example a Go SSH agent, has a fixture to build against on day one. The vectors are public and the key in them is a byte pattern, so the file reveals nothing about any real device.

The cost is a second source of truth beside the prose in PROTOCOL.md and ADR-0009. The generator is the tie-break: if the prose and the file disagree, the file is what the code checks, and the prose is what gets fixed.

The self-test proves the firmware's HMAC routine, not the key in the device's flash. A verifier that holds a stale copy of the device key still fails, and that failure is what the PAM module's pairing row in doctor will report.

Verified on hardware: the flashed firmware answers `SELFTEST` with `OK`, and the previous firmware's `ERR COMMAND reason=unknown` shows in doctor as "cannot check" rather than a failure.

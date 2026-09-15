# ADR-0009: A Device Key Signs Matches So Root Need Not Trust the Daemon

## Status

Accepted

## Context

The PAM module (planned) runs as root and must decide whether to grant sudo. It cannot hold the serial port itself, because the daemon does, so it must ask the daemon. But the daemon is user-space code running as the user. If PAM simply believed the daemon's "yes", then any malware running as the user could impersonate the daemon, or replace it, and obtain sudo without a physical touch. That would make the finger worth less than the password it is meant to supplement.

## Decision

The device generates a 32-byte key on first boot and stores it in NVS. `PAIR` returns the key once per boot, only after a fingerprint match, so a verifier can take a copy at install time and store it root-only. `IDENTIFY` accepts a 16-byte nonce; on a match the reply carries HMAC-SHA256 with the device key over `IDENTIFY|<nonce>|<slot>`. The verifier checks the HMAC against its copy. The daemon is a transport and cannot forge the answer.

## Consequences

A compromised user session cannot mint approvals. It can still relay: if malware forwards a PAM nonce to the device while the user is touching the sensor for some other reason, the device signs it. The ring shows white for nonce requests and blue for others so a user has a chance to notice, and the PAM window is short. This residual risk is accepted and is the same as tinytouch's PIV mode carries.

The key is readable from flash by anyone with the board and a cable until flash encryption is enabled. Enable secure boot and flash encryption before relying on this for anything that matters; re-pair to rotate.

Verified on hardware: key export, refusal of a second export in the same boot, and an HMAC computed on the Mac matching the device's.

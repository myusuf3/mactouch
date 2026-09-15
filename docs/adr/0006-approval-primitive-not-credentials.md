# ADR-0006: The Device Is an Approval Primitive, Not a Credential

## Status

Accepted

## Context

macOS gives third parties no way to plug into Touch ID. A fingerprint device therefore has to unlock things by some other route, and the reference project tinytouch offers two: type the user's real password over USB as a keyboard, or emulate a PIV smart card so login and sudo accept a signature instead of a password.

Both were weighed for the first version. Password typing works everywhere a password is accepted, but the device cannot see what has focus, so a match while a chat window is active posts the password into the chat, and a hardware keylogger between device and Mac captures it every time. PIV has the best security posture and is the only route to screen unlock, but the reference project's recent history is a run of CryptoTokenKit edge cases, and a bad state can lock the user out of sudo.

## Decision

The first version does one thing: answer "is an enrolled finger on the sensor right now?" for whoever asks, with a signed answer when a nonce is supplied. The Mac decides what that unlocks. Consumers in scope are scripts and shell aliases, AI-agent hooks, and a PAM module for sudo that keeps the password as fallback.

Password typing is out. PIV is deferred, not rejected: it is the one thing this design gives up, screen unlock by finger, and it can be added as a mode later because the protocol already carries the match result the applet would gate on.

## Consequences

Nothing on the device unlocks anything by itself, so a stolen or dumped device yields templates and a key that only matters together with the paired Mac. Publishing the code weakens nothing.

Login remains password or Touch ID. sudo, agents and scripts get the finger. The trade was made knowingly; revisit when the device and daemon are boring.

# Ideas backlog

Things the hardware makes possible once the approval primitive, the policy
stack and the CLI exist. Roughly ordered by how little new machinery each one
needs.

## Light

- Meeting countdown from Calendar: yellow fading in over the last five
  minutes, flash on start.
- Build and deploy status from any script: `mactouch notify green --for 30`.
- Pomodoro: the ring is the timer, tap to start or stop.
- Battery low, Time Machine running, downloads finished.
- Unread count above a threshold, read from the Dock badge through the
  Accessibility API.

## Touch and gestures

- Tap dismisses the current notify layer.
- Double tap toggles mute in the frontmost call.
- Hold locks the screen.
- Per-finger actions: the match reports the slot, so a middle finger can run
  a different Shortcut from an index finger.
- Presence: first touch of the day runs a morning Shortcut.

## Approval consumers

- SSH agent with touch-to-sign, keys in the Secure Enclave, a finger per
  signature.
- `git push` to protected branches through a pre-push hook.
- 1Password CLI session unlock where its CLI allows a custom prompt.
- Screen unlock, which requires PIV. Later.

## Device

- Second sensor for two-hand gestures.
- Haptic or piezo click on match.
- BLE so the device works with a laptop docked elsewhere.

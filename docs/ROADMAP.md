# Status and roadmap

- **Done:** firmware, protocol, CLI, daemon with policy stack, monitors for
  lock, Focus, microphone and camera, key export and signed identify, launch
  agent install, shared protocol vectors with a firmware self-test, `doctor`,
  and the PAM module with its install script. All verified on hardware,
  including a passwordless `su` on a touch.
- **Next:** the menu bar app, planned in [APP.md](APP.md).
- **Later:** AI-agent hooks that demand a fingerprint before destructive shell
  commands, tap and hold gestures mapped to Shortcuts, per-finger actions, Calendar countdowns, an SSH agent
  with touch-to-sign, and possibly smart card emulation for login.

Known limitation: entering download mode from software does not work on this
board revision, so every reflash needs the BOOT button.


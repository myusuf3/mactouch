# Status and roadmap

- **Done:** firmware, protocol, CLI, daemon with policy stack, monitors for
  lock, Focus, microphone and camera, key export and signed identify, launch
  agent install, shared protocol vectors with a firmware self-test, `doctor`,
  and the PAM module with its install script. All verified on hardware,
  including a passwordless `su` on a touch.
- **In progress:** the menu bar app, planned in [APP.md](APP.md). The daemon
  groundwork and the app skeleton are in; the menu shows daemon, device and
  ring state. Menu actions, Settings, notifications and login item follow.
- **Later:** AI-agent hooks that demand a fingerprint before destructive shell
  commands, tap and hold gestures mapped to Shortcuts, per-finger actions, Calendar countdowns, an SSH agent
  with touch-to-sign, and PIV smart card emulation for unlocking the screen
  (ADR-0013). PAM cannot reach the lock screen; see ADR-0012.

Known limitation: entering download mode from software does not work on this
board revision, so every reflash needs the BOOT button.


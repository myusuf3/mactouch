# Status and roadmap

- **Done:** firmware, protocol, CLI, daemon with policy stack, monitors for
  lock, Focus, microphone and camera, key export and signed identify, launch
  agent install, shared protocol vectors with a firmware self-test, `doctor`,
  and the PAM module with its install script. All verified on hardware,
  including a passwordless `su` on a touch.
- **Done, app:** the menu bar app in [APP.md](APP.md), all seven steps: menu
  with state and actions, Settings with General, Fingers and Diagnostics, the
  fingerprint request panel (ADR-0016), launch at login, and the bundle that
  carries the daemon and the CLI so install is one script and uninstall is
  deleting the app.
- **Done, screen unlock:** PIV smart card emulation on the device (ADR-0013,
  [PIV.md](PIV.md)): PIN then touch unlocks the lock screen and logs in
  after a restart, verified on hardware. Flash encryption is on in
  development mode; release mode and secure boot come before a board ships.
- **Later:** AI-agent hooks that demand a fingerprint before destructive shell
  commands, tap and hold gestures mapped to Shortcuts, per-finger actions, Calendar countdowns, an SSH agent
  with touch-to-sign. PAM cannot reach the lock screen; see ADR-0012.

Known limitation: entering download mode from software does not work on this
board revision, so every reflash needs the BOOT button.


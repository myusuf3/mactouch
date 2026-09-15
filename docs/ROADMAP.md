# Status and roadmap

- **Done:** firmware, protocol, CLI, daemon with policy stack, monitors for
  lock, Focus, microphone and camera, key export and signed identify, launch
  agent install. All verified on hardware.
- **Next:** AI-agent hooks. A pre-tool hook that demands a fingerprint before
  destructive shell commands, plus attention colours for sessions waiting on
  you.
- **Then:** a PAM module so `sudo` asks for a touch, verifying the HMAC against
  a root-only copy of the device key, with the password as fallback.
- **Later:** a menu bar app as a client of the daemon, tap and hold gestures
  mapped to Shortcuts, per-finger actions, Calendar countdowns, an SSH agent
  with touch-to-sign, and possibly smart card emulation for login.

Known limitation: entering download mode from software does not work on this
board revision, so every reflash needs the BOOT button.


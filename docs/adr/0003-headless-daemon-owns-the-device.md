# ADR-0003: A Headless Daemon Owns the Device; the UI Is a Client

## Status

Accepted

## Context

The design put the device manager, the LED policy stack, the monitors and the control socket inside a menu bar app. Building that app properly wants Xcode, which is not installed, while everything except the menu itself builds fine with the command line tools. The user chose to build the brain first and leave the UI for later.

That choice exposes a question the original design glossed over. Only one process can hold the serial device. If the app holds it, the app is a single point of failure for every integration: quitting or restarting the UI drops the device, and a crash in a view takes the PAM path down with it.

## Decision

The brain is a headless daemon, `mactouchd`, started by launchd at login. It owns the serial device, runs the policy stack and the monitors, and serves the control socket. The future menu bar app is one more client of that socket, with no special access. Restarting the UI never touches the device.

The socket protocol in `docs/PROTOCOL.md` is unchanged. Three details are settled here:

**The CLI picks its transport automatically.** If the daemon's socket exists, `mactouch` talks to it. If not, it opens the serial device directly, as it did in Phase 1. `--direct` forces the serial device and, when the daemon holds it, fails with a message that says so rather than a bare busy error. Scripts, hooks and the PAM module therefore work identically whether the daemon is running or not, except that identify prompts and ring policy exist only with the daemon.

**The reason for a fingerprint request is shown as a macOS notification.** The design had the app draw its own HUD. Until there is an app, the daemon posts a standard notification with the requester's text, and the ring colour says a request is pending: blue for an ordinary request, white for one carrying a nonce, which is how PAM asks. The UI can take over this job later without a protocol change.

**Flashing stops the daemon.** `scripts/flash.sh` unloads the launch agent before touching the port and loads it again afterwards, so the daemon never fights esptool for the device.

## Consequences

The menu bar app shrinks to a view over daemon state plus a few socket commands, which is the part that genuinely needs Xcode and can wait. Enrolment, deletion and settings are all reachable from the CLI meanwhile.

Two processes now need to agree on a socket path and a protocol version. The path is fixed at `~/Library/Application Support/MacTouch/control.sock`, mode 0600, and the daemon reports its protocol version in `status`.

The daemon has no window, so a failure to reach the device shows up only in its log and in `mactouch status`. The launch agent keeps it alive across crashes.

Notifications from an unbundled binary go through `osascript`, which cannot attach actions or icons. Acceptable for a reason line; a proper notification with an approve button is a UI-phase feature.

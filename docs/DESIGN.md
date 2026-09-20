# mactouch design

A fingerprint sensor on your desk that macOS can ask "is that you?" and that
shows you things with light. Built around a Seeed XIAO ESP32-S3 and a ZW101
fingerprint module with an RGB ring.

## Principles

1. **Dumb firmware, smart Mac.** The device drives the sensor, the ring, and
   touch detection. It never decides what a colour means or what a match
   unlocks. All policy lives in the Mac app, where it can be changed without
   reflashing.
2. **No secrets on the device that unlock anything by themselves.** The
   device holds fingerprint templates (inside the sensor) and one device key
   used only to prove that a match really came from the device. No passwords,
   no login credentials.
3. **Text on the wire.** Every link is newline-delimited ASCII. You can drive
   the device from `screen`, and the app from `nc`.
4. **One abstraction for light.** Every integration is a layer in a priority
   stack. The highest active layer owns the ring. Nothing talks to the ring
   directly.

## What a fingerprint unlocks

The first version is an **approval primitive plus a PAM module**:

- Any process on the Mac can ask "get me a fingerprint within N seconds" and
  receives yes or no. Claude Code hooks, shell scripts, Shortcuts, an SSH
  agent later.
- `sudo` asks through PAM. The password remains a fallback.

Deliberately out of scope for v1, with the reasoning recorded so it does not
get re-argued:

- **Password typing over HID.** Types your real password into whatever has
  focus, and a hardware keylogger sees it every time. Convenient, but the
  failure modes are the ones that hurt in daily use.
- **PIV smart card.** Best security, but weeks of CryptoTokenKit edge cases.
  Screen unlock by finger is the one thing v1 gives up. Revisit after the
  device and app are solid.

## Security model

Threats we accept, matching the reference tinytouch project:

- The sensor talks to the ESP over unauthenticated UART. Anyone who opens the
  case can inject "match" packets. Mitigation is physical: pot the case.
- The device is on your desk. Someone with your finger, or a good print, gets
  in. Same as Touch ID.

Threats we design against:

- **A compromised user-space process on the Mac** must not be able to obtain
  sudo without a physical touch. Therefore the PAM module does not trust the
  app. It sends a random nonce; the device returns HMAC-SHA256 over
  `nonce|slot` with a device key; the module verifies with a copy of that key
  in a root-only file. The app is only a transport. Residual risk: malware can
  relay a sudo nonce while you touch the sensor for some other reason. The
  ring shows a distinct colour for sudo requests to make that visible.
- **A stolen or dumped device** must not yield anything that logs in. It
  yields the device key, which only lets an attacker forge PAM approvals if
  they also have your Mac. Rotate by re-pairing. Enable flash encryption and
  secure boot before relying on this.
- **Replay** of approvals is prevented by the nonce.

## Components

```
+-------------------+  USB CDC (text lines)  +-------------------+
|  firmware (ESP)   | <--------------------> |  mactouchd        |
|  zw101 driver     |                        |  MacTouchKit      |
|  ring + touch     |                        |  LED policy stack |
|  link protocol    |                        |  monitors         |
+-------------------+                        |  control socket   |
                                             +---------+---------+
                                                       | unix socket (text lines)
                          +----------------+-----------+-----------+----------------+
                          |                |                       |                |
                    mactouch CLI    pam_mactouch.so        Claude Code hooks    MacTouch.app
                                    (root, verifies         (via the CLI)       (later)
                                     device HMAC)
```

### Firmware (`firmware/`, ESP-IDF 5.5, C)

| module | responsibility |
| -- | -- |
| `board.h` | GPIO numbers. The only place wiring lives. |
| `zw101.c` | Sensor packet protocol: verify, image, search, enrol, delete, index table, ring control. Mutex-guarded. |
| `led.c` | Ring state: idle colour, temporary states, result flashes. Thin over `zw101`. |
| `touch.c` | Presence via TouchOut pin or polling. Edge detection, tap and hold gestures, optional auto-identify (watch mode). |
| `link.c` | USB CDC line reader, command dispatch, event emission, one long-running command at a time, `CANCEL`. |
| `usb.c`, `usb_descriptors.c` | TinyUSB composite device, CDC only in v1. |
| `main.c` | Boot order, device key in NVS, tasks. |

The device key is 32 random bytes generated on first boot and stored in NVS.
`PAIR` returns it once per boot, and only after a fingerprint match.

### MacTouchKit (`app/Sources/MacTouchKit`, Swift, no UI)

- `Protocol`: `Command` encoding, `Response` and `Event` parsing. Pure and
  unit-tested.
- `SerialPort`, `DeviceLocator`: POSIX termios transport, USB VID/PID
  discovery through IOKit, reconnection by polling once per second while
  disconnected.
- `Device`: request/response with timeouts, event delivery, cancellation.
- `LEDPolicy`: priority layers resolved to one ring state. Pure and tested.
- `Monitors`: screen lock (distributed notifications), Focus mode, microphone
  (CoreAudio running-somewhere on every input device), camera (CoreMediaIO
  running-somewhere on every camera). Focus prefers the assertion store in
  `~/Library/DoNotDisturb/DB`, which names the mode but needs Full Disk
  Access; without it the monitor polls whether Control Center is showing the
  Focus menu bar item, which macOS does by default only while a Focus is on.
  The privacy layer drops one second after the last device stops, because
  devices flap while an app opens them.
- `ControlSocket`: server for the app, client for the CLI and PAM.

### mactouchd (`app/Sources/MacTouchDaemon`, headless)

Owns the device. Runs the monitors and the policy stack, serves the control
socket, and is started by launchd at login. When something asks for a
fingerprint it posts a macOS notification with the requester's reason, so you
know what you are approving, unless the app has said `hello ui=1` on the
socket and shows the request itself (ADR-0014). See ADR-0003 for why this is a
daemon and not the app.

### MacTouch.app (`app/Sources/MacTouchApp` and `MacTouchModel`, SwiftUI menu bar)

A client of the daemon's socket like any other. `DaemonModel`, in its own
library target so it can be tested against a fake daemon, keeps one
connection on `events`, reconnecting when the daemon restarts, and runs menu
actions as socket requests off the main queue. The `MenuBarExtra` menu
renders it: status and ring lines, the idle colour submenu, monitor toggles,
and a clear for the notify layer. The Settings window has a Fingers pane
(enrol into the first free slot with the daemon's live steps, name slots in
the app's defaults, delete with confirmation) and a Diagnostics pane that
shows the `HealthReport` rows doctor prints. Real notifications for requests
and the login item follow. Built by
`scripts/bundle-app.sh` with the command line tools, no Xcode project
(ADR-0015); see [APP.md](APP.md) for the plan.

### mactouch CLI (`app/Sources/MacTouchCLI`)

Talks to the daemon over the socket when it is running, otherwise straight to
the serial port. `--direct` forces the serial port and fails clearly if the
daemon holds it.

```
mactouch status
mactouch led red --mode breathe
mactouch notify yellow --for 120         # transient layer
mactouch idle cyan
mactouch identify --timeout 15 --reason "deploy to prod"   # exit 0 on match
mactouch enroll 2 / delete 2 / slots
mactouch events                          # stream device events
```

### pam_mactouch (`pam/`, C)

`auth sufficient pam_mactouch.so` in `/etc/pam.d/sudo`. Connects to the
target user's control socket, sends a nonce, verifies the HMAC against
`/etc/mactouch/<user>.key` (root, 0600). Any failure falls through to the
password prompt. Hard 20 second timeout.

## LED policy stack

| priority | layer | source | ring |
| -- | -- | -- | -- |
| 0 | idle | user setting | chosen colour, steady, or off |
| 10 | locked | screen lock monitor | off |
| 20 | focus | Focus mode monitor | colour per mode (Do Not Disturb magenta by default) |
| 30 | privacy | mic or camera live | red, breathe |
| 40 | notify | CLI and hooks, with expiry | as requested |
| 50 | prompt | identify in progress | blue breathe; sudo requests white breathe |

Rules: highest active layer wins; a layer that clears reveals the next; the
app sends `LED` only when the effective state changes; on reconnect it resends.
The device itself owns only the transient match result flash (green or red for
350 ms) so feedback stays instant.

## Claude Code integration

Three hooks, all shell one-liners over the CLI (`examples/claude-code/`):

- `Notification` (permission needed or idle): `mactouch notify yellow --for 300`
- `Stop`: `mactouch notify green --for 3`
- `PreToolUse` on `Bash` matching a dangerous pattern: `mactouch identify
  --timeout 20 --reason "$CMD"`; exit 0 allows, exit 2 denies with a message.

## Phases

1. **Firmware and direct CLI.** Sensor driver, ring, touch, protocol. Verify
   on hardware with `mactouch --direct`. Confirm TouchOut on this board.
2. **Daemon.** MacTouchKit, `mactouchd`, control socket, policy stack, the
   monitors, launch agent. Menu bar UI deferred to a later phase (ADR-0003).
3. **PAM.** Module and install script with rollback notes, on top of the
   shared vectors and firmware self-test (ADR-0011).
4. **Later.** Claude Code hooks, tap gestures to Shortcuts, per-finger
   actions, SSH agent with touch-to-sign, Calendar countdown, PIV.

## Prerequisites on this machine

- ESP-IDF 5.5 comes from the dotfiles nix-darwin config (nixpkgs-esp-dev, see
  dotfiles ADR-0012). `idf.py` is on PATH after a rebuild.
- Xcode is not installed; the command line tools with Swift 6.3 are. The Mac
  side is a SwiftPM package for that reason. `scripts/bundle-app.sh` wraps the
  executable in a `.app` for login items.

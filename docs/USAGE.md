# Using mactouch

## Commands

Every command below works with the daemon running. Most also work without it,
talking to the device directly; `--direct` forces that even when the daemon is
running and fails with a clear message if the daemon holds the port.

### Fingers

```
mactouch enroll 1            # slots 1..20; touch, lift, touch again
mactouch slots               # which slots hold a template
mactouch delete 1
mactouch delete all
mactouch identify --timeout 20 --reason "deploy to production"
```

`identify` exits 0 on a match and prints `slot=N score=S`, exits 2 on timeout
or cancel, and 1 on any other error. The score is the module's similarity
number; higher is a better match, anything reported has already passed the
module's own threshold. A flat press held for about a second matches far more
reliably than a quick tap.

Add `--nonce <32 hex chars>` to get `mac=<64 hex chars>` in the reply:
HMAC-SHA256 with the device key over the string `IDENTIFY|<nonce>|<slot>`.
`mactouch pair` prints the device key once per boot, after a touch, for a
verifier to store somewhere root-only.

### The ring

```
mactouch idle cyan                      # resting colour, saved on the device
mactouch led breathe magenta            # until the next led or clear
mactouch led flash red blue 5           # two colours, five cycles
mactouch notify yellow --for 30         # temporary layer, then falls back
mactouch notify green --for 3 --mode flash
mactouch clear                          # drop the notify layer
```

Colours: `off blue green cyan red magenta yellow white`. Modes: `off on
breathe flash fadein fadeout`.

The daemon resolves the ring from a stack of layers; the highest active layer
wins and lower ones show through when it clears:

| priority | layer | when | ring |
| -- | -- | -- | -- |
| lowest | idle | always | your idle colour |
| | locked | screen locked | off |
| | focus | a Focus mode is on | magenta |
| | privacy | microphone or camera live | breathing red |
| | notify | `led` and `notify` commands | as requested |
| highest | request | an identify is waiting | breathing blue, or white for a nonce request |

### Touches and gestures

```
mactouch watch on            # match every touch and report it
mactouch events              # stream: touch down/up, tap count, hold, match, nomatch
mactouch watch off
```

Events also carry the daemon's own `device connected|absent` and `ring` lines,
and a `request pending|done` pair around every fingerprint request with the
requester's reason.
Touch events pause while the sensor is being polled for images, which is why
none appear during an identify or enrolment.

### Menu bar app

`scripts/bundle-app.sh` installs `MacTouch.app` in `~/Applications`. The app
carries the daemon and the CLI, starts the daemon at login, and puts
`mactouch` on your PATH through `~/.local/bin`; uninstalling is deleting the
app and, if you set it up, `sudo scripts/pam-uninstall.sh`. Its menu
shows the daemon, device and ring state, sets the idle colour, toggles the
monitors and clears the notify layer. Settings (⌘,) has General for the
idle colour, launch at login (on from the first run; turn it off there) and
hiding the icon (open MacTouch again to bring it back), Fingers, where you enrol, name and delete fingers, and
Diagnostics, the doctor rows kept live.
While the app runs, a fingerprint request shows as a small floating panel in
the centre of the screen with the requester's reason and a Cancel button, in
place of the daemon's plain popup, and it stays visible under a Focus mode. Everything the app does the CLI does too; it is
a view over the daemon.

### Monitors

```
mactouch monitor mic off
mactouch monitor camera on
mactouch monitor lock on
mactouch monitor focus on
```

- **lock** uses the screen lock notifications macOS posts. No permission needed.
- **mic** asks CoreAudio whether any input device is in use by some process.
  Headsets that combine input and output report in use while only playing
  audio; the built-in microphone does not.
- **camera** asks CoreMediaIO the same question for every camera.
- **focus** reads the Do Not Disturb assertion store when it can, which names
  the active mode but sits behind Full Disk Access. Without that permission it
  falls back to checking whether Control Center is showing the Focus item in
  the menu bar, which macOS does only while a Focus is active under the
  default "when active" setting. Grant `mactouchd` Full Disk Access in System
  Settings to get the richer source.

Settings persist across daemon restarts. `mactouch doctor` reports which
source the focus monitor ended up with.

### Diagnostics

```
mactouch doctor              # verdicts with a fix each: daemon, device, sensor, fingers, focus source
mactouch status              # daemon, device, firmware, sensor, ring, layers, monitors
mactouch ping
mactouch gpio                # levels of the unused XIAO pins
mactouch selftest            # firmware signs the shared protocol vector; doctor runs this too
mactouch touch pin|poll      # how the firmware detects a finger
mactouch cancel              # abort a running identify or enrolment
mactouch reboot
```

## sudo with a fingerprint

```
sudo scripts/pam-install.sh                 # pair, store the key root-only, enable for sudo
sudo scripts/pam-install.sh --service su    # any other PAM service
sudo scripts/pam-install.sh --repair        # pair again after a reflash that lost the key
sudo scripts/pam-uninstall.sh [--purge]     # remove; --purge also deletes the stored key
```

The module is `auth sufficient`, so `sudo` asks the daemon for a fingerprint
first. The ring breathes white; touch and the command runs. Wait it out,
have no daemon running, or let anything else go wrong and sudo falls through
to the password as before. A signature that fails to verify is logged and
also falls through. Twenty seconds per request.

Pairing needs a touch and the device releases its key once per boot, so a
failed install means a replug before retrying. The key lives at
`/etc/mactouch/<user>.key`, root only. Reflashing does not change it;
erasing NVS does, and then `--repair` pairs again.

On macOS the sudo stack includes `/etc/pam.d/sudo_local`, which survives OS
updates, so that is where the line goes. If a configuration manager such as
nix-darwin owns that file, the script puts the line in `/etc/pam.d/sudo`
itself. An OS update can reset that file; `mactouch doctor` shows which
services carry the line, and re-running the install script puts it back.

**Not the lock screen.** The lock screen is drawn by `loginwindow`, an Apple
platform binary that loads only Apple-signed code. It rejects every
third-party PAM module, this one included, and logs
`Library Validation failed ... mapping process is a platform binary, but
mapped file is not`. `sudo` and `su` carry an entitlement that lifts that
check, which is why they work. The install script refuses
`--service screensaver` for this reason. Unlocking the Mac by touch needs a
different mechanism; see the roadmap.

Keep a root shell open while enabling this for sudo, and test from another
terminal with `sudo -k && sudo true` before closing it. The install script
prints the one-line rollback.

## Security model

What the device holds: fingerprint templates, inside the sensor module, and a
32-byte device key generated on first boot. No passwords, no login
credentials, nothing that unlocks anything on its own.

What a match proves: that an enrolled finger was on this sensor within the
request window. With a nonce, the HMAC proves the answer came from this device
for this request, so a compromised process on the Mac cannot forge an approval
by faking the daemon.

What is not defended: the serial line between module and ESP32-S3 is
unauthenticated, so anyone who opens the case can inject a "match". Potting
the case is the mitigation. Anyone with your finger, or a good copy of your
print, gets in, exactly as with any consumer fingerprint sensor. The device
key can be read from flash unless flash encryption is enabled; enable secure
boot and flash encryption before relying on it for anything serious.

By design there is no password typing and no smart card emulation. The
approval primitive gates things you choose to gate; it does not replace your
login password.

## Troubleshooting

**`mactouch status` says the device is not responding, or hangs, or the
daemon logs timeouts.** The board's USB link has died; the yellow heartbeat
LED tells you whether the firmware itself is alive. Unplug and replug the
board. If it recurs, open an issue with the log.

**`--direct` says the port is held by another process.** The daemon has it,
as intended. Drop `--direct`, or `scripts/daemon.sh stop` first.

**Every touch reports no match.** Press flat and hold for a second rather
than tapping, and make sure it is the finger you enrolled. Enrol the same
finger again in another slot at a slightly different angle to improve scores.

**The ring stays cyan when I try to enter download mode.** The ring does not
indicate download mode. Check the USB device list instead: "USB JTAG/serial
debug unit" means download mode, "mactouch" means the application.

**esptool says "No serial data received".** The application owns the USB
port. Use the BOOT button as described above.

**After flashing, the board stays in download mode.** esptool's default hard
reset over USB-JTAG leaves this board in download mode; the scripts use the
RTC watchdog reset instead. Run `scripts/rom-reset.py` to boot the application.

**Focus never shows.** Without Full Disk Access the monitor relies on the
Focus menu bar item being set to "show when active" in System Settings under
Control Center. Or grant the daemon Full Disk Access.

**The sensor is offline right after flashing.** The module keeps power across
a reset of the ESP32 and can miss the first handshake; the firmware retries
and recovers on its own within a few seconds. A replug always fixes it.


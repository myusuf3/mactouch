# mactouch

A fingerprint sensor for your desk that macOS can ask "is that you?", with an
RGB ring that shows you what your Mac is doing.

Touch it to approve a `sudo`, a deploy script, or a risky command an AI agent
wants to run. Glance at it to see that your microphone is live, your screen is
locked, or a Focus mode is on. Everything the device does is decided on the
Mac; the device itself only reads fingers, drives its ring, and reports
touches over USB.

The hardware is the same as [tinytouch](https://github.com/ZimengXiong/tinyTouch)
by Zimeng Xiong, whose design this project builds on. See Credits.

## How it works

The device is a Seeed XIAO ESP32-S3 wired to a ZW101 capacitive fingerprint
module. The module stores fingerprint templates in its own memory, matches a
live finger against them itself, and drives a ring of RGB LEDs around the
sensor. The ESP32-S3 talks to the module over a serial line and presents
itself to the Mac as a plain USB serial port.

Three pieces of software share the work:

- **Firmware** on the ESP32-S3. A thin peripheral: it exposes the sensor and
  the ring through a newline-delimited text protocol, detects touches and
  gestures, and holds one secret, a device key it uses to sign matches. It
  never decides what a colour means or what a match unlocks.
- **`mactouchd`**, a background daemon on the Mac started at login. It owns
  the USB connection, keeps the ring in sync with a stack of policy layers
  (idle colour, screen locked, Focus, privacy, notifications, pending
  request), watches the Mac for signals, and serves a local socket.
- **`mactouch`**, the command line tool. It talks to the daemon when it is
  running and straight to the device otherwise. Scripts, shell aliases, PAM
  and AI-agent hooks all use it.

A fingerprint request works like this: a program runs
`mactouch identify --reason "deploy to production"`. The daemon posts a macOS
notification with that reason, the ring breathes blue, and the device polls
the sensor. You press a finger; the module reports which template matched and
how well. The command exits 0 on a match and 2 on a timeout, so any script can
gate on it. With a nonce supplied, the reply also carries an HMAC over the
nonce and slot computed with the device key, which lets a verifier that holds
a copy of the key, such as a PAM module running as root, trust the answer
without trusting the daemon.

## Bill of materials

| part | notes |
| -- | -- |
| Seeed Studio XIAO ESP32-S3 | The plain XIAO ESP32-S3, not the Sense variant. Native USB, 8 MB flash. About $8. |
| ZW101 fingerprint module | Capacitive sensor with an RGB ring, UART at 57600 baud, the common `0xEF01` packet protocol. Sold under ZW101, ZW111 and similar names by several vendors. About $10 to $15. |
| Wire | Five connections between module and board. Thin silicone-insulated wire is easiest inside the case. |
| USB-C cable | Data, not charge-only. |
| Printed case | Two parts, top and bottom, from tinytouch (see Credits). Any PLA works. |
| Solder and iron, or a small breadboard | The XIAO has castellated pads and through-holes; the module comes with a small ribbon connector or bare pads depending on vendor. |

Other ESP32-S3 boards with native USB work if you adjust the pin numbers.
Other fingerprint modules work if they speak the same packet protocol.

## Wiring

The ESP32-S3 routes its serial peripheral through an internal pin matrix, so
the sensor can hang off any GPIOs. This project's boards are wired as follows;
the right-hand column is the XIAO's printed label.

| signal | module pin | GPIO | XIAO label |
| -- | -- | -- | -- |
| module RX, driven by the board (board TX) | 5 | 1 | D0 |
| module TX, read by the board (board RX) | 4 | 2 | D1 |
| TouchOut, high while a finger is present | 2 | 4 | D3 |
| 3.3 V | 6 | | 3V3 |
| GND | 1 | | GND |

tinytouch's reference wiring is different: it uses D6 and D7 (GPIO43 and
GPIO44) for the serial pair and D1 (GPIO2) for TouchOut. If you build to that
layout, or land wires anywhere else, change the three numbers in
`firmware/main/board.h`. Nothing else in the firmware knows a pin number. The
`mactouch gpio` command reports the level of every unused XIAO pin, so you can
touch the sensor while polling and see which pin follows without opening the
case.

XIAO label to GPIO map: D0=1, D1=2, D2=3, D3=4, D4=5, D5=6, D6=43, D7=44,
D8=7, D9=8, D10=9. The small yellow LED on the board is GPIO21, active low; the
firmware blinks it once a second as a heartbeat.

TouchOut is optional. Without it, `mactouch touch poll` tells the firmware to
ask the module for an image every 150 ms instead, at the cost of slower
reaction and no touch events while another command is using the sensor.

## Prerequisites

You need a Mac and two toolchains.

**macOS 13 or later** with the Xcode command line tools. Xcode itself is not
required; the Mac side is a Swift package that builds with
`xcode-select --install`. Swift 5.9 or later.

**ESP-IDF 5.5.x** for the firmware, with the ESP32-S3 toolchain. Either:

- Espressif's installer. Follow the ESP-IDF "Get Started" guide for macOS,
  install to `~/esp/esp-idf`, and run `. ~/esp/esp-idf/export.sh` in any shell
  where you build. Select the `esp32s3` target when asked.
- Nix. The `nixpkgs-esp-dev` flake packages ESP-IDF and the toolchain for
  Apple silicon. Its `esp-idf-xtensa` package is meant for `nix develop`;
  a small wrapper that captures its setup hook lets `idf.py` and `esptool.py`
  run from any shell, which is how this project's author has it installed.

Check with `idf.py --version`; it should print `ESP-IDF v5.5.x`.

Optional: `jq` for the AI-agent hooks, `ffmpeg` if you want to exercise the
microphone and camera monitors from the command line.

## Build and flash the firmware

```
cd firmware
idf.py set-target esp32s3
idf.py build
```

The build pulls `espressif/esp_tinyusb` from the component registry on the
first run. If `idf.py` created the project directory from a template in a
read-only location, `chmod -R u+w .` first.

Flashing needs the board in download mode, and that needs the BOOT button
once per flash. While the mactouch firmware, or tinytouch's, is running, it
owns the USB port and esptool cannot reset the chip itself. Two ways in:

- Unplug the board, press and hold **B** (BOOT), plug it in while holding,
  hold for three seconds, release.
- With the board plugged in, hold **B**, press and release **R** (RESET),
  release **B**.

Both buttons are next to the USB-C connector, labelled B and R on the
silkscreen. In download mode the Mac sees a device called "USB JTAG/serial
debug unit". The sensor ring says nothing about which mode you are in: the
module keeps its power and its last colour across a reset of the ESP32.

Then, from the repository root:

```
scripts/flash.sh
```

It backs up the entire 8 MB flash to `backups/`, writes the bootloader,
partition table and application, and resets the board into the new firmware
through the RTC watchdog. Pass `--no-backup` to skip the backup. The script
stops the daemon before flashing and restarts it afterwards. To restore what
was there before:

```
esptool.py --chip esp32s3 --port /dev/cu.usbmodemXXXX write_flash 0 backups/flash-<date>.bin
```

If you would rather not stare at the port list, `scripts/wait-for-bootloader.py`
prints the port the moment a board appears in download mode:

```
eval "$(idf-env)"   # or source ESP-IDF's export.sh
port=$(python scripts/wait-for-bootloader.py) && scripts/flash.sh "$port"
```

After the first flash the board enumerates as "mactouch" and the yellow LED
blinks once a second.

## Build and install the Mac side

```
cd app
swift build
../scripts/test.sh
.build/debug/mactouch status
```

`scripts/test.sh` exists because the command line tools install Swift Testing
outside the toolchain's search path; the script passes the framework paths
that `swift test` needs.

To run the daemon at login and put the CLI on your PATH:

```
scripts/install.sh
```

This builds release binaries into `~/.local/bin`, writes a launch agent named
`dev.mactouch.daemon` to `~/Library/LaunchAgents`, and starts it. The daemon
restarts automatically if it crashes and reconnects when the board is
replugged. Logs go to `~/Library/Logs/mactouch/mactouchd.log`. Re-run the
script after changing the daemon. `scripts/daemon.sh start|stop|restart|status`
controls the agent.

## Using it

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

Events also carry the daemon's own `device connected|absent` and `ring` lines.
Touch events pause while the sensor is being polled for images, which is why
none appear during an identify or enrolment.

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

Settings persist across daemon restarts.

### Diagnostics

```
mactouch status              # daemon, device, firmware, sensor, ring, layers, monitors
mactouch ping
mactouch gpio                # levels of the unused XIAO pins
mactouch touch pin|poll      # how the firmware detects a finger
mactouch cancel              # abort a running identify or enrolment
mactouch reboot
```

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

## Status and roadmap

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

## Credits

The hardware design is [tinytouch](https://github.com/ZimengXiong/tinyTouch)
by Zimeng Xiong, MIT licensed: the choice of the XIAO ESP32-S3 and the ZW101
module, the wiring concept, the printed case (STLs in that repository under
`hardware/case`, with the CAD on Onshape linked from its README), and the
[build guide video](https://www.youtube.com/watch?v=YsP1hRg28Gw). tinytouch
also served as the reference for the sensor's packet protocol and the USB
descriptor layout. Its firmware and Mac helper take a different approach,
typing your password or emulating a smart card, and are worth reading for a
second opinion on the trade-offs.

mactouch is MIT licensed; see `LICENSE`.

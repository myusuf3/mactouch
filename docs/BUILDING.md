# Building and flashing

Everything needed to go from parts to a working device, and to work on the
code.

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

**macOS 14 or later** with the Xcode command line tools. Xcode itself is not
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

## Build the PAM module

```
make -C pam all test
```

`pam/build/pam_mactouch.so` links only libpam and libSystem. The test pins
the module to `docs/protocol-vectors.json` through the same header the
firmware compiles in, then drives it against a fake daemon on a unix socket.
`scripts/pam-install.sh` builds and installs it; see [USAGE](USAGE.md).

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

## Build the menu bar app

```
scripts/bundle-app.sh
open ~/Applications/MacTouch.app
```

There is no Xcode project (ADR-0015). The script builds the `MacTouchApp`
product in release, lays out `MacTouch.app` around the binary with an
`Info.plist` that hides the Dock icon, signs it ad hoc and copies it to
`~/Applications`, quitting a running copy first. The app is a client of the
daemon's socket, so it needs `mactouchd` running to show anything beyond
"Daemon not running". Ad-hoc signing is enough on the Mac that built it;
another Mac needs a Developer ID.


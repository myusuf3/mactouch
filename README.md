# mactouch

A desk fingerprint sensor that macOS can ask "is that you?", with an RGB ring
that shows you what your Mac is doing.

Hardware is a Seeed XIAO ESP32-S3 and a ZW101 fingerprint module, the same
parts as [tinytouch](https://github.com/ZimengXiong/tinyTouch). The firmware,
protocol and Mac software are written from scratch around one idea: keep the
device dumb and put every decision in the Mac app.

- `docs/DESIGN.md` architecture, security model, phases
- `docs/PROTOCOL.md` the two text protocols
- `docs/HARDWARE.md` this board's wiring and the sensor commands
- `docs/IDEAS.md` backlog
- `docs/adr/` decisions, with the reasoning that led to them

## Building

Firmware (ESP-IDF 5.5 comes from the dotfiles nix config):

```
cd firmware && idf.py set-target esp32s3 && idf.py build
../scripts/flash.sh            # backs up the whole flash, then flashes
```

Mac side:

```
cd app && swift build          # library and the mactouch CLI
../scripts/test.sh             # unit tests
.build/debug/mactouch status
```

Status: Phase 1 complete and verified on hardware. Enrol, identify, watch mode,
gestures, ring control, key export and the signed identify all work from the
CLI. Phase 2 (menu bar app, policy stack, monitors) is next.

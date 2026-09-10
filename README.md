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
cd app && swift build          # library, mactouchd, and the mactouch CLI
../scripts/test.sh             # unit tests
.build/debug/mactouch status
```

Install the daemon as a launch agent and the CLI into `~/.local/bin`:

```
scripts/install.sh
mactouch status                # via the daemon
mactouch notify green --for 5
mactouch identify --reason "deploy"
```

Status: Phase 2 in progress. The daemon owns the device, resolves the ring
policy, runs the lock, Focus, microphone and camera monitors, and serves the
control socket the CLI uses. Menu bar UI deferred (ADR-0003).

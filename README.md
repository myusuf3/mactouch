# mactouch

A fingerprint sensor for your desk that macOS can ask "is that you?", with an
RGB ring that shows you what your Mac is doing.

Touch it to approve a `sudo`, a deploy, or a risky command an AI agent wants to
run. Glance at it to see that your microphone is live, your screen is locked,
or a Focus mode is on. The device only reads fingers, drives its ring, and
reports touches; every decision is made on the Mac.

The hardware is [tinytouch](https://github.com/ZimengXiong/tinyTouch) by
Zimeng Xiong: the same board, sensor, wiring concept and printed case. mactouch
is new firmware and new Mac software for it, built around keeping the device
dumb and the Mac smart.

## What you need

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


## Install

TBD. Until there is a packaged release, see [building and flashing](docs/BUILDING.md).

## Documentation

- [How it works](docs/HOW-IT-WORKS.md)
- [Building and flashing](docs/BUILDING.md)
- [Using mactouch](docs/USAGE.md)
- [Wire protocols](docs/PROTOCOL.md)
- [Hardware notes](docs/HARDWARE.md)
- [Status and roadmap](docs/ROADMAP.md)
- [Menu bar app plan](docs/APP.md)
- [Screen unlock plan](docs/PIV.md)
- [Onboarding and updates plan](docs/ONBOARDING.md)
- [Design](docs/DESIGN.md) and [decision records](docs/adr/)

## Credits

The hardware design is [tinytouch](https://github.com/ZimengXiong/tinyTouch)
by Zimeng Xiong, MIT licensed: the parts, the wiring concept, the printed case
(STLs under `hardware/case` in that repository, CAD on Onshape linked from its
README), and the [build guide video](https://www.youtube.com/watch?v=YsP1hRg28Gw).
tinytouch's firmware and Mac helper take a different approach, typing your
password or emulating a smart card, and are worth reading for a second opinion.

mactouch is MIT licensed; see `LICENSE`.

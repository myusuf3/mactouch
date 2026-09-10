# Hardware

## Parts

- Seeed XIAO ESP32-S3 (native USB, hardware UART on any pin via GPIO matrix)
- ZW101-class capacitive fingerprint module, UART at 57600 baud, `0xEF01`
  packet protocol, RGB ring, TouchOut line
- Printed case from the tinytouch project

## This board's wiring

Both units were assembled off the tinytouch reference wiring. The UART pair was
confirmed with a pin sweep and TouchOut by touch events from mactouch on the
second board. The reasoning is in `adr/0002-sensor-pinout.md`.

| signal | sensor pin | XIAO label | GPIO | reference build |
| -- | -- | -- | -- | -- |
| sensor RX (board TX) | 5 | D0 | 1 | D6 / GPIO43 |
| sensor TX (board RX) | 4 | D1 | 2 | D7 / GPIO44 |
| TouchOut | 2 | D3 | 4 | D1 / GPIO2 |
| 3V3, GND | 6, 1 | 3V3, GND | | |

All of this lives in `firmware/main/board.h`. Nothing else in the firmware
knows a GPIO number.

XIAO ESP32-S3 label to GPIO map for reference: D0=1 D1=2 D2=3 D3=4 D4=5 D5=6
D6=43 D7=44 D8=7 D9=8 D10=9. User LED is GPIO21, active low.

## Sensor commands used

| code | name | use |
| -- | -- | -- |
| 0x13 | VfyPwd | liveness check at boot and after errors |
| 0x01 | GetImage | 0x00 finger captured, 0x02 no finger |
| 0x02 | GenChar | image to template in buffer 1 or 2 |
| 0x04 | Search | match buffer against pages, returns page and score |
| 0x05 | RegModel | merge buffers 1 and 2 |
| 0x06 | StoreChar | save merged template to a page |
| 0x0C | DeleteChar | delete N pages from a start page |
| 0x0D | Empty | delete all |
| 0x1D | TemplateNum | count of stored templates |
| 0x1F | ReadIndexTable | bitmap of used pages |
| 0x3C | LED control | function, start colour, end colour, cycles |

Ring control: functions 1 breathe, 2 flash, 3 steady on, 4 off, 5 fade in,
6 fade out. Colours are a 3-bit mask: 1 blue, 2 green, 4 red, so cyan 3,
magenta 5, yellow 6, white 7.

## Toolchain

- ESP-IDF 5.5 with `espressif/esp_tinyusb` 2.2.1, installed through the
  dotfiles nix-darwin config (nixpkgs-esp-dev). `idf.py` is on PATH.
- Flash over the XIAO's USB port. The ZW101 keeps power across an MCU reset,
  so unplug and replug once after flashing.

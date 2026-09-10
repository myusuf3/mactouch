# ADR-0002: Sensor Pinout Is D0/D1/D3, Confined to board.h

## Status

Accepted

## Context

The tinytouch reference design wires the ZW101 fingerprint module's UART to the XIAO ESP32-S3's D6 and D7 (GPIO43 and GPIO44) and its TouchOut line to D1 (GPIO2). The stock tinytouch firmware hard-codes those numbers.

Both of the boards on hand were assembled differently. A pin sweep on the first board found the sensor answering on D0 and D1 (GPIO1 and GPIO2), with TouchOut on D3 (GPIO4) recalled from the build and later confirmed. The second board, which tinytouch reported as `sensor=offline`, turned out to be wired the same way: mactouch found its sensor ready immediately and received touch events on GPIO4. The sensor was never faulty; the firmware was looking at the wrong pins.

The ESP32-S3 routes UART through a GPIO matrix, so any pin can carry either signal. TouchOut is a plain GPIO input. There is nothing electrically special about D6/D7 versus D0/D1, and no reason for the firmware to assume either.

| signal | sensor pin | XIAO label | GPIO | tinytouch reference |
| -- | -- | -- | -- | -- |
| sensor RX, driven by the board | 5 | D0 | 1 | D6 / GPIO43 |
| sensor TX, read by the board | 4 | D1 | 2 | D7 / GPIO44 |
| TouchOut, high while touched | 2 | D3 | 4 | D1 / GPIO2 |
| 3V3 | 6 | 3V3 | | |
| GND | 1 | GND | | |

XIAO ESP32-S3 label to GPIO map, for the next time a wire lands somewhere unexpected: D0=1 D1=2 D2=3 D3=4 D4=5 D5=6 D6=43 D7=44 D8=7 D9=8 D10=9. The on-board yellow LED is GPIO21, active low.

## Decision

The firmware targets this wiring: UART TX on GPIO1, RX on GPIO2, TouchOut on GPIO4, 57600 baud.

Every GPIO number lives in `firmware/main/board.h` and nowhere else. A board wired to the reference layout, or any other, is a three-line change there. The `GPIO` protocol command reports the level of every unused XIAO pin so a wire can be traced from the host without opening the case or reflashing: touch the sensor while polling and see which pin follows.

TouchOut is used for presence and gestures but is not required. `TOUCH poll` switches the firmware to asking the sensor for an image every 150 ms, which works with the TouchOut wire absent or on the wrong pin, at the cost of a slower reaction and no touch events while another command holds the sensor.

## Consequences

Stock tinytouch firmware will not see the sensor on these boards, and neither would a tinytouch update. The first board's tinytouch install carries the same three-pin change, uncommitted, in the tinyTouch checkout.

TouchOut goes quiet while the sensor is being polled for images, because the module's touch detection only runs when it is idle. Touch events therefore do not arrive during `IDENTIFY` or `ENROLL`; those commands detect the finger through the image poll instead. Nothing is lost, but a host must not wait for a touch event to know a finger is present during a long command.

Pull-down is enabled on GPIO4 so an unwired TouchOut reads as "not touched" rather than floating.

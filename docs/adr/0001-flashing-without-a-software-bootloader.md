# ADR-0001: Flashing Uses the BOOT Button; the Software Bootloader Command Is Compiled Out

## Status

Accepted

## Context

The XIAO ESP32-S3 has one USB-C port wired to the chip's internal USB PHY. That PHY serves either the USB-Serial/JTAG controller, through which esptool can reset the chip into download mode, or the USB-OTG controller, which TinyUSB uses for the mactouch link. Once the application starts TinyUSB, the JTAG path is gone and esptool cannot reset the chip. The ROM briefly enumerates the JTAG port at power-on, but on a board with a working sensor the application claims the PHY before macOS finishes enumerating it; two fast catch attempts saw only the application's port, 3 ms after the node appeared. A board whose sensor was missing exposed the ROM port for several seconds because tinyTouch retried its sensor probe first, which is how the first mactouch flash got in.

tinyTouch's own OTA path was tried as a button-free route and refused the image at commit, consistent with update signing being enforced in its production build.

A `BOOTLOADER` command was added so that, once mactouch is running, no button would ever be needed again. It sets `RTC_CNTL_FORCE_DOWNLOAD_BOOT` and resets, the mechanism both ESP-IDF's USB CDC console and the Arduino core use. Three variants were tested on this board (chip revision v0.2):

| variant | sequence | result |
| -- | -- | -- |
| persist | `usb_dc_prepare_persist`, `USBDC_PERSIST_ENA`, set request, `esp_restart` from a shutdown handler | application booted; USB link dead until power cycle |
| cpu | reset USB module, set request, `RTC_CNTL_SW_PROCPU_RST` from a task | no reset observed; USB link dead until power cycle |
| shutdown-handler cpu | as above, from an `esp_restart` shutdown handler | untested |

The request register read back as zero from download mode, so a stale request was not the cause of a separate problem: esptool's plain "hard reset" over USB-Serial/JTAG left this board in download mode every time, while `--after watchdog_reset` booted the application every time.

Each failed variant leaves the device enumerated but deaf, and the macOS serial driver then blocks inside `open()` regardless of `O_NONBLOCK`, which took the CLI down with it until it learned to open on a helper thread with a timeout.

## Decision

Flashing is a manual step: hold BOOT while applying power, or hold BOOT and tap RESET on a powered board. `scripts/wait-for-bootloader.py` watches for the ROM's USB identity and `scripts/flash.sh` backs up the entire flash, writes, and resets through the RTC watchdog, never through the JTAG hard reset. `scripts/rom-reset.py` boots the application from download mode the same way.

The `BOOTLOADER` command stays in the protocol as reserved and replies `ERR BOOTLOADER reason=unsupported`. The shutdown-handler implementation remains in `link.c` behind `MACTOUCH_EXPERIMENTAL_BOOTLOADER` for whoever investigates next, and must not ship enabled while a failed attempt can wedge the device.

The ring is not an indicator of download mode. The sensor module keeps its power and its last colour across an MCU reset, so it stays lit whatever the chip is doing. The only reliable indicator is the USB identity on the bus: product ID `0x1001` is the ROM, `0x4d54` is mactouch.

## Consequences

Reflashing costs a button press, and someone has to be at the board. The scripts remove every other manual step and make the reset back into the application reliable.

Two lines of investigation are open. The ESP32-S3 ROM's handling of the force-download request after a software reset on this revision, and whether the USB persist path can work with TinyUSB rather than the ROM's own USB driver. Either would revive the command. Until then `tinyTouch`'s approach of never needing a reflash, updating over its own OTA path instead, is the alternative worth copying if reflashing becomes frequent.

The first board, still running tinyTouch with the pin fix, keeps its own recovery path: `backups/flash-20260910-110903.bin` is a full image of the second board's tinyTouch install and restores either unit to stock with one esptool command.

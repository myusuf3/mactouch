# ADR-0018: Firmware Is Installed by the App and Updated Over the Link

## Status

Accepted

## Context

Every firmware change so far has meant holding the BOOT button, because the running firmware owns the USB port through TinyUSB and esptool cannot reset the chip into download mode behind it (BUILDING.md, the known limitation in ROADMAP.md). For the author that is an annoyance. For anyone else it is a wall: the menu bar app is about to onboard new boards through its own UI (docs/ONBOARDING.md) and will ship updates through Sparkle (ADR-0019), and neither story survives "now unplug the board and hold a button you cannot see".

Three facts shape the answer. A blank ESP32-S3 runs Espressif's ROM with the built-in USB-Serial/JTAG peripheral, which a host can reset into download mode on its own, so the very first flash needs no button. Once mactouch firmware runs, it owns a text link to the daemon and can write its own flash. And the stack overflow that reboot-looped the board during PIV step 5 showed what a bad image costs today: the link is gone, and only the button brings it back.

## Decision

**First install through esp-serial-flasher.** The app flashes a blank board itself with Espressif's esp-serial-flasher, an Apache-2.0 C library built to embed the ROM bootloader protocol in host programs. It becomes a SwiftPM C target with a port layer over the Kit's serial code, so there is no Python, no esptool binary to sign, and no Xcode project. The app carries the firmware image, bootloader and partition table it installs. This path runs once per board.

**Every later update over the link.** The firmware gets two app slots and rollback. An update is `FW BEGIN size=<n> sha256=<hex>`, a stream of `FW WRITE off=<n> data=<base64>` lines, and `FW END`; the firmware writes the spare slot with the OTA API, checks the digest and the image header, switches the boot slot and restarts. The chip's bootloader is not involved, the lines fit the existing 256-byte protocol, and on an encrypted board the OTA API encrypts on the way in.

**A touch starts every update.** `FW BEGIN` waits for an enrolled finger with the ring breathing white before it erases anything. Firmware that runs on the chip can read everything the chip holds, the PIV keys and the device key included, so installing it is the most privileged act the device has; it gets the same gate as generating a key. The digest guards against a damaged transfer, not a hostile one. Image signing arrives with secure boot v2 in release mode, when the bootloader refuses unsigned images on its own; until then a board on the bench accepts any image its owner touches for.

**Rollback by default.** The bootloader boots a new image once in a pending state. The image marks itself valid only after the host link has been up for fifteen seconds without a restart; if it crashes first, the next boot returns to the previous slot. A reboot loop like the one in PIV step 5 would have ended in seconds with the old firmware running.

**The layout keeps what the board already holds.** The new partition table keeps `nvs` at 0x9000 and `nvs_key` at 0x187000 exactly where they are, and fits otadata and the two 1.4 MB slots around them. Moving either would make the encrypted NVS unreadable and cost the device key, the PIV identity and the pairing, as the first encrypted boot did. The current image is about 400 KB.

**BOOT stays as the last resort.** Moving an existing board to the two-slot layout takes one more download-mode flash, which is the last one planned. After that the button is for a board with both slots broken or a broken bootloader, and BUILDING.md keeps the procedure.

## Consequences

Onboarding a new board is "plug it in, click Install", and keeping it current is a button in the app or `mactouch firmware update`. The developer loop moves to the link too, so `flash.sh` becomes the recovery path rather than the daily one.

The firmware grows an update state machine, a base64 decoder use and a digest check; the Mac side grows an updater in the Kit and, for first installs, a vendored C library with a small port layer. The app bundle carries a firmware image for each release, so app and firmware versions travel together and the app can offer an update when the board is older than the image it carries.

The first-install path cannot be tested on the author's board, which is already encrypted; it needs a blank board. That the ROM resets into download mode without the button is expected from how the S3's USB-Serial/JTAG works and is checked on that board before the app relies on it.

Until release mode, a touch is all that stands between a local process and new firmware. That is the same bar as generating a smart card key and is acceptable on the bench; it is not acceptable on a board that leaves it.

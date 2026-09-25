# Onboarding and updates plan

How a new board goes from the box to unlocking a Mac through the app alone,
and how board and app stay current afterwards. The decisions are ADR-0018
(firmware install and update without the BOOT button) and ADR-0019 (app
releases through Sparkle, still without an Xcode project).

## The experience

1. Install MacTouch.app from a notarised download and open it.
2. Plug in the board. If it is blank, the app says so and offers **Install
   Firmware**; a minute later it is running mactouch. If it already runs
   mactouch, the app moves on, offering an update if the board is older than
   the firmware the app carries.
3. A setup window walks through the rest, each step skippable and each
   marked done from the device's own state: enrol a finger, turn on sudo by
   fingerprint (one administrator prompt), set up the smart card (make the
   keys with a touch, set a PIN, pair), and grant Full Disk Access for the
   Focus monitor.
4. Later, Sparkle offers new versions of the app. After one installs, the
   app restarts its daemon and offers the matching firmware, which installs
   over the link after a touch.

No step asks for the BOOT button or a terminal.

## Order of work

Each step ships on its own and is verified on hardware.

1. **Two slots, rollback and updates over the link.** New partition table
   with otadata and ota_0/ota_1 around the existing `nvs` and `nvs_key`,
   rollback on, the image marking itself valid after fifteen seconds of
   healthy link. `FW BEGIN|WRITE|END|ABORT` in the firmware with the touch
   gate and a SHA-256 check; `fw` through the daemon; `mactouch firmware
   update <image>` in the CLI; `scripts/update.sh` for the developer loop.
   Verify: one last BOOT flash moves this board to the new layout with its
   identity, pairing and device key intact; an update over the link then
   installs with a touch and no button; a deliberately broken image rolls
   back on its own.
2. **Firmware in the app.** The bundle carries the firmware image and its
   version; the app offers an update when the board is older, with progress
   and the touch prompt in the request panel. Verify: bump the version,
   rebuild the app, and update the board from Settings.
3. **First install on a blank board.** Vendor esp-serial-flasher as a C
   target with a port over the Kit's serial code; detect a board in ROM
   download mode; flash bootloader, partition table, otadata and app.
   Verify on a blank board: the ROM resets into download mode without the
   button, and the app installs and the board comes up as mactouch.
4. **Setup window.** The guided steps above, driven by the health report so
   it resumes where it stopped, with the in-app installs for the PAM module
   and the CLI symlink behind an administrator prompt.
5. **Sparkle and the release script.** The dependency, the menu item and
   setting, the daemon restart on version change, `scripts/release.sh` with
   Developer ID signing, notarisation and the appcast. Verify: install a
   release on a clean user account, publish a newer one, and update to it.
6. **Release-mode encryption and secure boot.** Before any board leaves the
   bench: signed images only, download mode encryption closed. With it, the
   update path gains signature checking from the bootloader itself.

Steps 1 and 2 need only this board. Step 3 needs a blank board. Step 5 needs
the Developer ID credentials and a notarisation profile on this Mac.

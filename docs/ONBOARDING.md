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
   keys with a touch, set a PIN, pair). Nothing asks for a privacy
   permission; the Focus monitor that needed Full Disk Access is gone
   (ADR-0020).
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
   back on its own. Done 2026-09-26: the move kept the device key, the
   identity, the PIN and the pairing; 0.2.1 installed over the link in 17
   seconds and confirmed itself; a crash-test image booted, crashed and the
   board came back on 0.2.1 by itself, reported as a rollback.
2. **Firmware in the app.** The bundle carries the firmware image and its
   version; the app offers an update when the board is older, with progress
   and the touch prompt in the request panel. Verify: bump the version,
   rebuild the app, and update the board from Settings. Done 2026-09-26:
   "Update Firmware to 0.2.2" appeared in the menu and the Firmware section
   of Settings → General, the panel asked for the touch, and the board came
   back on 0.2.2 in the other slot, confirmed, with the smart card and its
   pairing untouched.
3. **First install on a blank board.** Vendor esp-serial-flasher as a C
   target with a port over the Kit's serial code; detect a board in ROM
   download mode; flash bootloader, partition table, otadata and app.
   Verify on a blank board: the ROM resets into download mode without the
   button, and the app installs and the board comes up as mactouch.
4. **Setup window.** The guided steps above, driven by the health report so
   it resumes where it stopped, with the in-app installs for the PAM module
   and the CLI symlink behind an administrator prompt. Built 2026-09-27:
   welcome, connect, firmware, a finger, sudo and the smart card (optional),
   one page each, ticked off from the sensor and the health report. It
   opens on its own once, the first time the app finds sudo not set up, and
   from "Set Up MacTouch…" in the menu after that. Sudo runs the bundled
   `pam-install.sh` behind the administrator prompt (ADR-0021). Verified:
   the model's tests, every page rendered against the live sensor and a
   fresh one, the bundle carrying the signed module and script, and the
   window staying shut on a Mac already set up. Still to do: a run of the
   sudo step on a Mac without it, and the CLI symlink, which only
   `bundle-app.sh` makes today.
5. **Sparkle and the release script.** The dependency, the menu item and
   setting, the daemon restart on version change, `scripts/release.sh` with
   Developer ID signing, notarisation and the appcast. Verify: install a
   release on a clean user account, publish a newer one, and update to it.
6. **Release-mode encryption and secure boot.** Before any board leaves the
   bench: signed images only, download mode encryption closed. With it, the
   update path gains signature checking from the bootloader itself.

Steps 1 and 2 need only this board. Step 3 needs a blank board. Step 5 needs
the Developer ID credentials and a notarisation profile on this Mac.

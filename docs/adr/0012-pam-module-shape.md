# ADR-0012: How the PAM Module Reaches the Daemon and Where It Lives

## Status

Accepted

## Context

ADR-0009 settled the cryptography: the module verifies a device HMAC with a root-only copy of the key. Building the module raised the questions that ADR left open. Where does the module file go on a system with SIP, where does the key go, how does root find a user's daemon socket, which PAM service file gets the line, and what does the module return when it cannot help.

## Decision

**Path and file.** The module is built as a Mach-O bundle with the command line tools, ad-hoc signed, and installed at `/usr/local/lib/pam/pam_mactouch.so`, root-owned. `/usr/lib/pam` is under SIP. The PAM line names the module by absolute path so it does not depend on OpenPAM's search list.

**Key.** `/etc/mactouch/<user>.key`, a hex line, directory 0700 and file 0600, root-owned. One key per user because one Mac can pair with more than one device. The install script obtains it by running `mactouch pair` as the invoking user and never prints it.

**Socket.** The module takes `PAM_USER`, resolves that user's home through the directory service, and connects to `~/Library/Application Support/MacTouch/control.sock` as root. The socket is 0600 to the user, which root passes. For sudo `PAM_USER` is the invoking user, which is the person whose finger and daemon are wanted.

**A typed password wins.** If `PAM_AUTHTOK` is already set when the module runs, a password was collected before the stack started, as in `use_first_pass` stacks. The module returns `PAM_IGNORE` immediately so entering a password never waits on the ring. Sudo prompts through the conversation instead of presetting the token, so its behaviour is unchanged.

**Not the lock screen.** The lock screen was tried and cannot work this way. `loginwindow` is a platform binary with library validation, and the kernel refuses to map any non-Apple library into it: `Library Validation failed: Rejecting pam_mactouch.so for process loginwindow, reason: mapping process is a platform binary, but mapped file is not`. `sudo` and `su` are exempt through the `com.apple.private.security.clear-library-validation` entitlement. No signature available to a third party changes this, so PAM covers sudo, su and other exempt services only; unlocking the screen needs either password typing over USB HID, which ADR-0006 rejects, or smart card emulation, which macOS supports natively at the lock screen.

**Return codes.** A verified signature is `PAM_SUCCESS`. A reply whose signature fails to verify is `PAM_AUTH_ERR` and is logged as a warning, because it means something answered with the wrong key. Everything else, including no key file, no daemon, a daemon error and no touch in time, is `PAM_IGNORE`, so the stack continues to the password with no visible change. The line is `auth sufficient`, so the module can only add a way in, never remove one.

**Which file.** On macOS `/etc/pam.d/sudo` includes `sudo_local`, which Apple ships as a template precisely so local additions survive OS updates. The install script targets `sudo_local` for sudo and the named file for any other service, inserting the line ahead of the existing auth modules and keeping a `.mactouch-backup` copy. If `sudo_local` is a symlink a configuration manager owns it, and fighting the manager for that file would lose on every rebuild, so the script writes the line into `/etc/pam.d/sudo` itself. That file can be reset by an OS update; the trade was made so that sudo-by-fingerprint is something mactouch installs on any Mac rather than a per-machine config change, and `doctor` names the services that carry the line so a reset is visible. On the author's machine nix-darwin generates `sudo_local`, so this is the path taken there.

**Testing.** The module's core is a separate translation unit with no PAM dependency. Its test includes the same `vectors.h` the firmware compiles in, so the third implementation of the signature is pinned to the same bytes as the other two, and a forked fake daemon exercises approval, replay, a signature for another slot, a daemon timeout and a hang-up. The live check is `su <user> -c true` from a shell with no terminal, which can only succeed if the module approved.

## Consequences

Installing is one command plus a touch, and the password never stops working. Uninstalling is one command. Rotating the key after an NVS erase is `--repair`.

Because the key is root-only, `mactouch doctor` running as a user can report whether the module is installed and which services name it, but not whether the stored key still matches the device. A mismatch shows up as a warning in the auth log and a password prompt, not as a red doctor row. Running doctor as root to close that gap is possible later.

The 20 second window is per PAM conversation. A tool that opens several sudo sessions in a row asks for several touches, as Touch ID would.

Verified on hardware: `su` obtained a shell with no password on a fingerprint match, with the match visible on the daemon's event stream, and `sudo -k && sudo true` returned on a touch with the line in `/etc/pam.d/sudo`. Attempts with no touch fell through to the password after 20 seconds as designed. Note for testers: `sudo -n` never reaches PAM unless sudoers sets `noninteractive_auth`, so it cannot be used to exercise the module.

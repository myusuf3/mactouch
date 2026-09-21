# ADR-0017: The App Ships the Daemon and Owns Its Launch Agent

## Status

Accepted

## Context

ADR-0003 made `mactouchd` a headless daemon and the app one of its clients, and left the daemon's installation to `scripts/install.sh`: release binaries in `~/.local/bin` and a hand-written launch agent plist in `~/Library/LaunchAgents`. That was right when there was no app. With the app built (APP.md steps 1 to 6), a user of the app had two installs to run and two things to keep in step, and an uninstall meant knowing about a plist, two binaries and a symlink.

The alternatives were a separate installer package, a Homebrew formula, or leaving install.sh as the path for everyone. All three keep the daemon's lifecycle outside the app that the user actually sees.

## Decision

**One bundle.** `MacTouch.app` carries three executables: the app and `mactouchd` in `Contents/MacOS`, and the `mactouch` CLI in `Contents/Helpers`. The daemon's launch agent plist lives in `Contents/Library/LaunchAgents` with `BundleProgram` pointing at the daemon inside the bundle, so the agent follows the app wherever it is moved. `scripts/bundle-app.sh` builds and lays all of this out; it is the install path.

**The app owns the agent.** On every launch the app registers the agent through `SMAppService.agent(plistName:)`. That starts the daemon and lists MacTouch under Login Items in System Settings, where the user can turn it off. The menu offers "Start Daemon" when the daemon is down and "Allow MacTouch in Login Items" when macOS is waiting for approval. `mactouch doctor` asks launchd whether the agent is loaded and says which install it came from.

**The app retires the old install.** If the plist install.sh wrote is present at launch, the app unloads it and deletes it, because two agents cannot share a label and the bundled one must win. install.sh stays as the developer path for a checkout without the app and refuses to run while the app is installed. `daemon.sh start` opens the app when the bundled agent is the one in use, since registering is the app's job.

**The process boundary does not move.** The daemon still owns the device and the app still only talks to the socket. What moved is deployment: the app installs and supervises the daemon, it does not become it. Quitting the app still changes nothing about the ring, sudo or monitors.

**What stays outside the bundle.** The PAM module and its key are root-owned under `/usr/local/lib/pam` and `/etc/mactouch`, installed by `pam-install.sh` as ADR-0012 decided. Installing them from the app behind an admin prompt, installing the CLI symlink from the app, and a notarised disk image for other Macs are the onboarding work that follows this decision; none of it is decided here.

## Consequences

Install is one script and uninstall is deleting the app, plus `pam-uninstall.sh` if sudo was set up. The socket path, the protocol, the PAM module and the CLI are unchanged.

Three constraints of launchd and SMAppService now bind the build, found by hitting each:

- The helpers must be signed with the same identity as the app. An agent whose executable is signed differently never spawns; `launchctl print` shows `OS_REASON_CODESIGNING` and exit 78. Ad hoc therefore stops being enough for the install path, and the bundle script signs helpers and bundle with the "Apple Development" identity when one is present.
- `register()` keeps the registration it already has. A changed plist or binary only takes effect after the agent is unloaded, which the bundle script does before reopening the app. An app update mechanism will have to do the same after a relaunch.
- On a case-insensitive volume `Contents/MacOS/mactouch` is `Contents/MacOS/MacTouch`. The CLI lives in `Contents/Helpers` for that reason alone, and the app product is `MacTouchApp` for the same reason (ADR-0015).

Full Disk Access is granted per binary, so a grant made for `~/.local/bin/mactouchd` does not carry to the daemon inside the app; the Focus monitor drops to its menu bar fallback until it is granted again, and doctor says so.

The app deletes a file the user's own script created. That is deliberate and one-directional: the app is the install once it is present, and a developer who wants the script path again deletes the app first.

Distribution to another Mac still needs a Developer ID and notarisation. Whichever identity signs the first build others install must sign every later one, because update mechanisms and macOS both compare them; that choice is made when the first release is, not here.

# ADR-0021: The App Turns On sudo with the Install Script

## Status

Accepted

## Context

Sudo by fingerprint is the thing MacTouch is for, and until now it needed a source checkout and `sudo scripts/pam-install.sh` in Terminal. The setup window (docs/ONBOARDING.md) has to offer it as one step, which means the app has to put a module in `/usr/local/lib/pam`, a root-only key in `/etc/mactouch` and a line in `/etc/pam.d`, all as root.

A mistake in a PAM file can lock someone out of sudo, and the script already gets the details right: it prefers `sudo_local` so OS updates keep the line, refuses symlinked files that a config manager owns, backs the file up, adds the line once as `auth sufficient` so everything short of a verified touch falls through to the password, and pairs with the sensor as the user rather than as root.

The ways for an app to act as root are a privileged helper registered through `SMAppService.daemon`, which stays installed and running as root for the sake of one step, the deprecated `AuthorizationExecuteWithPrivileges`, or AppleScript's `do shell script … with administrator privileges`, which the app already uses for `sc_auth` when pairing the smart card.

## Decision

**The app runs the same script.** `bundle-app.sh` builds the module and puts it, signed like the helpers, in `Contents/Resources/pam` next to a copy of `pam-install.sh`. The setup window's step runs that script once through `do shell script` behind the administrator prompt, with `SUDO_USER` set to the person at the prompt, `--module` pointing at the built module so nothing compiles on the user's Mac, and `--cli` pointing at the bundled CLI it pairs with. Each word goes through `quoted form of`, and the prompt names what it is for rather than osascript.

**The Mac's state decides whether it worked.** The step reads the same health check as `mactouch doctor`: the module is installed and a PAM service names it. The script's own output is only used to say why it failed.

## Consequences

One implementation writes to `/etc/pam.d`, whether from Terminal or the app, and it is the one that has been run on hardware. Nothing stays running as root afterwards.

Root runs a script from inside the app bundle, which lives in a folder the user can write to. That is the same trust as running it from a checkout today: anything that can rewrite the bundle as the user could also have waited for the next Terminal run. A notarised build in `/Applications` narrows it; the admin prompt is the gate either way.

The script pairs over the daemon, so the step needs mactouchd running and, unless a key is already stored, a touch while the ring breathes white. The sensor releases its key once per boot, so a second attempt after a failure needs a replug, and the step says so from the script's message.

Turning sudo off works the same way with the bundled `pam-uninstall.sh`, which keeps the stored key so turning it on again needs no touch. The same prompt puts the `mactouch` command in `/usr/local/bin`, which is on every Mac's PATH, as a link into the bundle; the app replaces or removes only a link that points into a MacTouch.app.

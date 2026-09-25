# ADR-0019: App Releases Ship Through Sparkle, Still Without an Xcode Project

## Status

Accepted

## Context

ADR-0015 built the app with SwiftPM and a bundle script instead of an Xcode project, and ADR-0017 made that bundle the install path. Both left distribution open: the app is signed with an "Apple Development" identity that only this Mac trusts, and there is no update mechanism. Onboarding new boards through the app (docs/ONBOARDING.md) only matters if other people can install the app, and firmware updates over the link (ADR-0018) only reach them if the app itself updates.

The question raised was whether Sparkle, the standard update framework for Mac apps outside the App Store, forces an Xcode project after all. It does not. Sparkle 2 is a Swift package, and everything Xcode would do around it is a command: `codesign` for nested code, `notarytool` and `stapler` for notarisation, both of which ship with the command line tools, and Sparkle's own `generate_appcast` and `sign_update` for the feed. What Xcode would add is doing those steps implicitly, which is also where signing bugs hide.

## Decision

**Sparkle 2 as a SwiftPM dependency of the app target.** One `SPUStandardUpdaterController`, "Check for Updates…" in the menu, and "Check for updates automatically" in Settings → General. `bundle-app.sh` copies `Sparkle.framework` into `Contents/Frameworks` and writes `SUFeedURL` and `SUPublicEDKey` into the Info.plist.

**A release script owns what Xcode would.** `scripts/release.sh` builds in release, lays out the bundle, signs inside-out with the Developer ID Application identity and the hardened runtime (Sparkle's XPC services and Autoupdate helper, then `mactouchd` and the CLI, then the app), notarises with `notarytool` using a stored keychain profile, staples, zips, signs the zip with Sparkle's EdDSA key, and updates the appcast. It never uses `codesign --deep`. The EdDSA private key stays in the keychain; the public key is in the plist.

**Developer ID from the first public build.** Sparkle refuses an update whose signing identity differs from the running app, and so does Gatekeeper's notion of the same developer. The first build anyone else installs is signed with "Developer ID Application" and every later one with the same identity. `bundle-app.sh` keeps signing local builds with "Apple Development" for the author's machine.

**Updates restart the daemon.** The app compares its bundle version with the last one it ran; on a change it unloads and re-registers the daemon's agent, because `SMAppService.register()` keeps a stale registration (ADR-0017), and offers a firmware update if the board is older than the image the new app carries (ADR-0018).

**The feed is static.** The appcast and the zips are release assets on GitHub, served over HTTPS, with no server of our own.

## Consequences

Still one build system and no Xcode project; ADR-0015 holds. The price is that signing order, entitlements and notarisation live in a script, and mistakes there show up only on a clean Mac, so every release is checked by installing it on a user account that has never seen the app.

The EdDSA key and the Developer ID certificate become things that must not be lost: losing the EdDSA key strands every installed copy on its current version, and changing the Developer ID does the same.

Notarisation needs credentials on the building machine (an App Store Connect API key or an app-specific password in a `notarytool` keychain profile). CI can run the release later; it does not have to at first.

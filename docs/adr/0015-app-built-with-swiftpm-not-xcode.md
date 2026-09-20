# ADR-0015: The App Is a SwiftPM Target Wrapped by a Script, Not an Xcode Project

## Status

Accepted

## Context

ADR-0003 deferred the menu bar app on the premise that "building that app properly wants Xcode". That premise was never tested. When the app's turn came, a probe on the current toolchain showed that a SwiftUI app using `MenuBarExtra`, `Settings`, `UserNotifications` and `ServiceManagement` compiles with `swift build` alone. What Xcode adds is the bundle: `Info.plist`, the `.app` layout, signing, and an icon.

The rest of the project is a Swift package with three targets and a test target, built and tested by `swift build` in CI on a plain macOS runner. Adding an `.xcodeproj` would introduce a second build system, a generated file that fights `git diff`, and a dependency that the repository's own build instructions say is not needed.

## Decision

The app is two targets. `MacTouchModel` is a library holding the daemon-facing model, so tests can import it; `MacTouchApp` is the `executableTarget` with the SwiftUI scenes and views, depending on MacTouchKit and the model. The split is not taste: the command line tools' SwiftPM cannot link a test bundle against an `@main` executable, and a library is the standard shape for a testable SwiftPM app. `scripts/bundle-app.sh` turns the binary into `MacTouch.app`: it writes an `Info.plist` with `CFBundleIdentifier dev.mactouch.app` and `LSUIElement` so there is no Dock icon, ad-hoc codesigns the bundle, and installs it in `~/Applications`, quitting a running copy first. This is the same shape as `install.sh` for the daemon: a script owns the install, the package owns the code.

The deployment floor stays at macOS 13, which the package already declares and which `MenuBarExtra` requires. `@Observable` needs macOS 14, so the app's model is an `ObservableObject`; the floor is raised when a feature needs it, not for a nicer macro.

Ad-hoc signing is enough for the machine that built the app. Distribution to another Mac needs a Developer ID and notarisation, which is a release concern and out of scope until there is a release.

## Consequences

One build system, one command, one CI job. `swift build` still builds everything, and the SwiftUI target compiles on the CI runner without change.

Product names must differ case-insensitively. Xcode's build engine, which the Xcode toolchain's `swift build` uses, folds `MacTouch` and `mactouch` into one build folder and merges their sources; the command line tools' engine does not, so the collision showed up only on one toolchain. The app product is therefore `MacTouchApp`, renamed to `MacTouch` by the bundle script.

Anything Xcode would have done through a checkbox is a line in the script: an entitlement, a URL scheme, an icon. The icon is the first gap; a menu-bar-only app shows it only in Finder and Login Items, so the skeleton ships without one and it is added when the login item lands.

SwiftUI previews and the Xcode debugger are not available for the app. The model is plain Swift over the Kit's socket client and is exercised against the real daemon, which is how the rest of the project is tested too.

ADR-0003's reason for deferring the app is void. Its decision stands on its own merits: the daemon owns the device because the UI must be allowed to quit, not because the UI was hard to build.

# MacTouch.app plan

The menu bar app is the last big client of the daemon. This is the plan for
it: what it shows, what it does not, how it is built without Xcode, and the
order the work lands in. API facts below were checked against Apple's
documentation and Human Interface Guidelines through sosumi.ai.

## What it is

A SwiftUI `MenuBarExtra` app, macOS 14 and later, that is one more client of
`mactouchd`'s control socket (ADR-0003). It never touches the serial device.
Quitting or crashing it changes nothing about approvals, monitors or the ring.

Three surfaces:

1. **The menu.** A glance at state and the handful of actions you reach for
   often. The HIG says to show a menu, not a popover, when people click a
   menu bar extra, so this is a plain menu, not a window.
2. **A Settings window.** Fingers, monitors, ring colour, login item,
   diagnostics. Opened from the menu and with the standard shortcut.
3. **The request panel.** When something asks for a fingerprint, a floating
   panel in the centre of the screen with the reason and a Cancel button,
   modelled on the system Touch ID prompt, replacing the daemon's `osascript`
   fallback. It was going to be a notification; ADR-0016 says why it is not.

Non-goals, so they do not creep in: no approve button anywhere (the finger is
the approval, ADR-0006), no second copy of the CLI. Anything the app can do,
the CLI can do; the app is a view.

## The menu

```
[touchid symbol]
● Connected · 2 Fingers                         (dot in the ring's colour)
Breathing red · Privacy                         (the owning layer, unless idle)
───────────────
Ring Colour            ▸  ● Off ● Blue ● Green ● Cyan ● Red ● Magenta …
MONITORS
  ✓ Screen Lock
  ✓ Microphone
  ✓ Camera
───────────────
Clear Notification Light                        (only when a notify layer is active)
Update Firmware to 0.2.3…                       (only when the board is older)
───────────────
Set Up MacTouch…
Settings…                                        ⌘,
Quit MacTouch                                    ⌘Q
```

The symbol is SF Symbols `touchid`, a template image so the system colours it
for light and dark menu bars. State does not change the symbol; the status
lines carry it. When the daemon is unreachable the first line reads "Daemon
not running" and the menu offers "Start daemon", which runs
`scripts/daemon.sh start`'s launchctl call.

The extra can be hidden from Settings through the `isInserted` binding, per
the HIG rule that people decide whether an extra sits in their menu bar. The
app keeps running without it and still shows the request panel; checked on
macOS 26, hiding through the binding does not terminate the app, only
dragging the extra out does. The way back is to open MacTouch again from
Finder or Spotlight: the reopen event turns the icon back on, and the
Settings footer says so.

## Settings window

A `Settings` scene with a sidebar: General on its own, then the panes
under three headers, Light, Security and MacTouch. The pane's icon and name
sit in the title bar instead of a banner, so each pane opens on its
settings; the window title still follows the pane and the last pane is
restored, as the HIG asks. Eight panes are too many for toolbar tabs.
Toggles and selections take the ring's colour, so the window matches the
sensor, except where the colour has no hue to lend (off, white) or is too
light for white text (yellow).

The device is drawn, not pictured: `DeviceView` renders the sensor with its
ring lit from the daemon's `ring` state, breathing and flashing in step
with the real one (steady under Reduce Motion). It is the General card,
the About and Firmware heroes, each colour tile and the request panel's
icon, so the screen always matches the desk.

- **General.** The sensor with its state, launch at login and show in menu
  bar, and the command line tool: a link at `/usr/local/bin/mactouch` to
  the bundled CLI, installed and removed behind the administrator prompt. Launch at login is turned on the first time the app runs,
  because an app whose job is to be there when sudo asks is no use absent;
  the toggle is the opt-out and the choice is not touched again.
- **Ring.** The resting colour as tiles, each a small lit sensor, and the
  layer stack from request down to idle, marking the one showing.
- **Monitors.** The three toggles, screen lock, microphone and camera, with a
  line each on what they show.
- **Fingers.** Use for sudo, which runs the bundled install or uninstall
  script and shows what `/etc/pam.d` says; the slots from `slots`, a name per
  slot stored in the app's defaults, delete with confirmation, and
  enrolment in a sheet that fills a fingerprint as the daemon streams
  `evt enroll step=...`.
- **Smart Card.** Screen unlock through the device's PIV card (docs/PIV.md)
  as three steps ticked off from the card's state: keys, PIN, pairing.
- **Firmware.** The sensor, its version in a capsule (`0.2.2 → 0.2.3` when
  the app carries newer), one Install button with progress, and how
  updates and rollback work.
- **Diagnostics.** The same rows as `mactouch doctor`, live.
- **About.** Version and credits.

Doctor's checks move from the CLI into MacTouchKit as a `HealthReport` so the
CLI and the app render one list.

## Setup window

The guided first run from docs/ONBOARDING.md: a window of its own, one page
per step, with the live sensor at the top, dots that turn green as steps
are done, and Back and Continue (or Skip) at the bottom. Steps are ticked
off from the sensor and the health report, so reopening it from "Set Up
MacTouch…" starts at the first one still to do. AppKit owns the window, as
it does the request panel, because a SwiftUI `Window` scene would open at
every login on macOS 14; the app opens it on its own once, when it first
finds sudo not set up. The sudo step runs the bundled install script behind
the administrator prompt (ADR-0021).

## Request panel

A borderless non-activating `NSPanel` at `.floating` level, on every Space,
centred on the screen with the pointer. It never becomes key, so a password
being typed into the terminal that asked keeps going there. It shows the
requester's reason, a title that says whether it is an ordinary request or a
signed one such as sudo, "try again" after a failed attempt, and a Cancel
button that sends `cancel` on the socket. It appears on `evt request
state=pending` and disappears on `state=done`, however the request ended:
match, timeout or Cancel. A Focus mode cannot hide it, which is why it is a
panel and not a notification (ADR-0016).

Handoff from the daemon needs one protocol addition: the daemon emits
`evt request state=pending|done kind=plain|nonce reason=<text>` on the events
stream, and a client that sends `hello ui=1` on its events connection
suppresses the `osascript` fallback while it stays connected. If the app is
not running, the daemon behaves exactly as now.

## Building without Xcode

ADR-0003 deferred the app because it "needs Xcode". It does not. A SwiftUI
app with `MenuBarExtra`, `Settings`, `UserNotifications` and
`ServiceManagement` compiles with the command line tools alone; this was
checked with a probe on the current toolchain. The pieces:

- A fourth SwiftPM target, `MacTouchApp`, depending on MacTouchKit.
- `scripts/bundle-app.sh` builds it in release, lays out `MacTouch.app` with an
  `Info.plist` carrying `CFBundleIdentifier dev.mactouch.app`, `LSUIElement`
  true so there is no Dock icon, and the `touchid` symbol as the icon, then
  ad-hoc codesigns it and copies it to `~/Applications`.
- Launch at login through `SMAppService.mainApp.register()`, which lists the
  app under Login Items in System Settings. The daemon keeps its own launchd
  plist from `install.sh`; folding it into the bundle as
  `SMAppService.agent(plistName:)` is a later step, once the app is the
  normal install path.

Ad-hoc signing is fine on the machine that built it. Distribution to another
Mac needs a Developer ID, which is out of scope until there is a release.

## Packaging: the app ships the daemon

The app bundles the daemon and the CLI without changing the process
boundary. `MacTouch.app` carries three executables, `MacTouch` and
`mactouchd` in `Contents/MacOS` and `mactouch` in `Contents/Helpers` (on a
case-insensitive volume `MacOS/mactouch` would be the app), plus
`Contents/Library/LaunchAgents/dev.mactouch.daemon.plist` whose
`BundleProgram` points at the daemon inside the bundle. On every launch the
app calls `SMAppService.agent(plistName:)` and `register()`, and macOS lists
MacTouch under Login Items. The CLI gets a symlink into `~/.local/bin`.

Two things launchd insists on, found the hard way: the helpers must be
signed with the same identity as the app, or every spawn dies with
`OS_REASON_CODESIGNING`, and `register()` keeps the registration it already
has, so a changed plist or binary needs the agent unloaded first, which
`bundle-app.sh` does before reopening the app.

One artifact, one signature over all three binaries, uninstall by deleting
the app. The socket path, the protocol, the PAM module and the CLI address
the daemon by its socket, so none of them change. ADR-0003 holds: the app is
a client, quitting it never touches the device.

What stays outside the bundle: the PAM module and the key, root-owned under
`/usr/local/lib/pam` and `/etc/mactouch`, installed by `pam-install.sh`,
later triggered from Settings behind an admin prompt. The scripted install
path (`install.sh`, `daemon.sh`) stays for checkouts without the app, running
the same daemon binary; doctor's autostart row recognises either.

Costs: moving the app breaks the agent until the app is launched again and
re-registers, which it does on every launch. Full Disk Access is granted per
binary, so the bundled daemon needs its own entry as today.

Bundling is the last step, once the app exists to do the registering, so the
working sudo setup does not move until the app is worth installing.

## Kit changes the app needs

`ControlClient` is synchronous and blocks the calling thread, which suits the
CLI. The app needs:

- An `@Observable` `DaemonModel` in the app target that owns two connections:
  one subscribed to `events` with reconnect on disconnect, one for requests.
  Requests run on a background task so the main actor never waits on the
  socket. Enrol and identify are long commands and run one at a time, as the
  daemon already enforces.
- `HealthReport` in MacTouchKit, extracted from `Doctor.swift`.
- The `evt request` event and `hello` handshake above.

## Order of work

Each step ships on its own and is verified against the running daemon.

1. **Kit and daemon groundwork.** `HealthReport`, `evt request`, `hello ui=1`
   suppression. Verify: doctor unchanged, `mactouch events` shows request
   events during an identify, the notification stops when a `hello ui=1`
   client is connected.
2. **App skeleton.** Target, bundle script, `MenuBarExtra` with the two status
   lines and Quit, `DaemonModel` streaming events. Verify: plug and unplug
   the board and watch the line change; kill and restart the daemon.
3. **Menu actions.** Idle colour, monitor toggles, clear. Verify against
   `mactouch status` after each click.
4. **Settings: Fingers and Diagnostics.** Enrol with live steps, delete,
   names, health rows, self-test button. Verify: enrol a finger from the app,
   see it in `mactouch slots`, delete it.
5. **Request panel.** Panel, Cancel, daemon handoff. Verify: run
   `mactouch identify --reason test`, see the panel, press Cancel, see exit
   code 2.
6. **Login item and General pane.** `SMAppService.mainApp`, show-in-menu-bar.
   Verify: the app appears under Login Items; log out and in.
7. **Bundle the daemon.** Move the agent into the bundle, `bundle-app.sh`
   writes the plist, the app registers it, `install.sh` becomes the dev path.
   Verify: delete the hand-written plist, reboot, doctor is green and sudo
   asks the ring.

Steps 1 and 2 are small and unblock the rest. Step 5 is the one that changes
what the user sees during a sudo, so it lands after the PAM module is stable.

## Decisions to record

Two of these deserve ADRs when the work starts: building the app with SwiftPM
and a bundle script instead of an Xcode project, which revises the premise of
ADR-0003, and the `hello ui=1` handoff for notifications, which is the first
time a socket client identifies itself.

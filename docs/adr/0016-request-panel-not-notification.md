# ADR-0016: A Fingerprint Request Shows a Panel, Not a Notification

## Status

Accepted

## Context

APP.md planned a `UserNotifications` notification for each fingerprint request, with a Cancel action, and listed "no on-screen HUD" among the app's non-goals. ADR-0014 gave the daemon the events and the `hello ui=1` handoff to make that possible. Building it exposed two problems.

A notification is the wrong tool for a request with a fifteen-second deadline. Focus modes hide banners by default, and the user asked exactly this: what good is a request that cannot be seen under Do Not Disturb? Time-sensitive notifications punch through Focus but need an entitlement and still leave a banner, which is small, top-right and gone in seconds. Apple's own Touch ID prompt for sudo is not a notification either; it is a small floating dialog.

And macOS refused the app: `requestAuthorization` answered "Notifications are not allowed for this application" for the ad-hoc signed bundle, and even with an Apple Development identity the permission prompt had to be answered before anything showed. A request UI that depends on a permission the user may have dismissed is a request UI that sometimes is not there.

## Decision

**A panel.** The app shows a borderless non-activating `NSPanel` at `.floating` level, on every Space and over full-screen apps, centred on the screen with the pointer. It carries the requester's reason, a title that distinguishes an ordinary request from a signed one such as sudo, a "try again" line after a failed attempt, and a Cancel button. It appears on `evt request state=pending` and goes away on `state=done`, whatever ended the request: a match, a timeout or Cancel. Nothing else dismisses it and nothing else is needed.

**Never key.** The panel does not activate the app or take keyboard focus. The terminal that ran sudo keeps focus, so a password typed during the request lands where it was meant to. Cancel works by click.

**Hello unconditionally.** With no permission to wait for, the app says `hello ui=1` as soon as its events connection is up, and again after every reconnect. While the app runs the daemon's `osascript` popup is silent; when it quits the popup returns, exactly as ADR-0014 designed.

**Cancel works during a request.** The Cancel button relies on `cancel` reaching the device while `identify` is in flight, and it did not: the daemon refused with `busy`, and the Kit's request lock would have serialised it behind the identify anyway. The device link protocol always said CANCEL is out of band, so the Kit now writes it without taking the lock or waiting, drops the `OK CANCEL` acknowledgement rather than handing it to the waiting command, and the daemon skips the busy check for it. The interrupted command fails with `reason=cancelled` and its caller sees exit code 2, as the CLI documents.

**The non-goal is revised.** "No on-screen HUD" was there to keep the app a view over the daemon. The panel is still that: it draws two socket events and sends one socket command. The approve button non-goal stands; the panel has no way to approve.

## Consequences

The request UI is present whenever the app is, on any Focus, with no permission step and no dependence on the signing identity. The `UserNotifications` code is gone; the bundle script keeps preferring an Apple Development identity because it is stable across builds.

A signed request over SSH while the screen is locked shows no panel, because no window can show on the lock screen; the ring still breathes white and the request still works by touch. A notification would have appeared there. The trade is accepted: the lock screen is not where sudo is typed.

`mactouch cancel` now interrupts a running identify, enrolment or pairing from any shell, which the protocol promised and the daemon did not deliver until now.

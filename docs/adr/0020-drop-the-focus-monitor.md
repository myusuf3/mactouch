# ADR-0020: Drop the Focus Monitor

## Status

Accepted. Supersedes the Focus source in [ADR-0005](0005-monitor-signal-sources.md).

## Context

ADR-0005 gave the Focus monitor two sources. The Do Not Disturb assertion store names the active mode but sits behind Full Disk Access. Without that grant the monitor polls Control Center's preferences every three seconds for the Focus menu bar item, which cannot say which Focus is on and stops working if the item is set to always or never show.

In practice the grant was the weak point. It is per binary, so it was lost when the daemon moved into the app bundle (ADR-0017), and the onboarding plan needed a step of its own to ask for it again. The Settings pane needed a warning row and a button into System Settings for the fallback case, and doctor needed three verdicts for one light. What the user got in return was a steady magenta ring, which is also one of the resting colours and so often looked like nothing had changed.

## Decision

**Remove the Focus monitor.** The daemon watches the screen lock, the microphone and the camera. `focus` is no longer a monitor name, the `focus` ring layer is gone from the policy stack, `status` no longer reports a `focus` source, and doctor has no Focus row. The app, CLI and docs lose the toggle, the Full Disk Access prompt and the troubleshooting entry.

## Consequences

MacTouch asks for no privacy permission at all: everything it watches works without a prompt. Onboarding has one step fewer.

The ring no longer shows that a Focus is on. Anyone who wants that can drive the notify layer from a Shortcuts automation, `mactouch led on magenta` when a Focus turns on and `mactouch clear` when it turns off, which puts the colour and the rule in their hands.

`mactouch monitor focus on` is now refused with `err monitor reason=value`, like any other unknown name. A daemon from before this change still lists `focus` among its monitors; the app and doctor skip names they do not know, so a mixed install during an update shows nothing wrong. The `monitor.focus` key left in the daemon's defaults is ignored.

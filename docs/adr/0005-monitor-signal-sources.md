# ADR-0005: Where the Monitors Get Their Signals

## Status

Accepted

## Context

The policy stack needs four facts about the Mac: is the screen locked, is a Focus mode on, is the microphone live, is the camera live. macOS offers no single API for any of them, and the obvious sources differ a lot in reliability and permissions.

## Decision

**Screen lock** uses the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` distributed notifications. They are undocumented but have been stable for over a decade and need no permission. They are delivered on the main run loop, so the daemon runs one.

**Microphone** asks CoreAudio whether any device with input streams reports `DeviceIsRunningSomewhere`, and listens for that property on every such device plus for the device list changing. This is the same signal the menu bar's orange dot is based on. Devices that have both input and output, such as USB headsets, report running when only playing audio, so those can produce a false red; the built-in microphone and speakers are separate devices and do not.

**Camera** does the same through CoreMediaIO on every capture device.

**Focus** has two sources. The Do Not Disturb assertion store in `~/Library/DoNotDisturb/DB` names the active mode, but macOS puts it behind Full Disk Access, which a launch agent does not have unless the user grants it. Without that permission the monitor polls, every three seconds, whether Control Center is currently showing the Focus item in the menu bar, read from the `com.apple.controlcenter` preferences. macOS shows that item only while a Focus is active under the default "when active" setting, so it is a usable proxy, though it cannot say which Focus is on and breaks if the user sets the item to always or never show. The monitor picks the store when it can read it and logs which source it is using.

Microphone and camera share the privacy layer. Turning red is immediate; turning back waits one second, because devices flap on and off while an application opens them and the ring should not flicker.

## Consequences

Everything works out of the box with no permission prompts. Granting mactouchd Full Disk Access upgrades Focus detection from "some Focus" to the named mode, which is what a per-mode colour needs.

All four sources are unofficial. A macOS release can change any of them, and the failure mode is a monitor that silently never fires, so each one logs its transitions and `mactouch status` lists which monitors are enabled. A monitor can be switched off with `mactouch monitor <name> off` if it misbehaves.

The USB headset false positive is accepted for now. A refinement is to check the input scope's running state per stream once a real case shows up.

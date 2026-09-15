# ADR-0007: Dumb Firmware, Smart Mac

## Status

Accepted

## Context

Policy can live on the device or on the Mac. tinytouch puts a lot on the device: mode selection, the HID password flow, the PIV applet, an OTA channel. That made its firmware large, made behaviour changes a reflash, and, on this hardware, every reflash needs the BOOT button.

## Decision

The firmware is a peripheral. It drives the sensor, the ring and the touch line, speaks a text protocol, and keeps one secret. It never decides what a colour means, what a touch does, or what a match unlocks. The only ring behaviour it owns is the 350 ms green or red result flash after a match attempt, because that feedback has to be instant and would feel wrong with a round trip in it.

Everything else is the daemon's: the idle colour is a setting the device stores but the Mac chooses, all other ring states come from the policy stack, watch mode is switched on and off by the host, and every integration is Mac code that can change without touching the board.

## Consequences

Firmware changes are rare, which matters when each one costs a button press. Integrations are a Swift or shell change with no flashing.

The device is useless without a host and shows only its idle colour when unplugged from meaning. That is intended; ADR-0003 makes the host a daemon so the meaning is always there while the Mac is on.

The device still has to be trusted for one thing, the match itself, and ADR-0009 covers how a verifier can trust it without trusting the daemon in between.

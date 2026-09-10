# ADR-0004: One Firmware Task Owns the USB Link

## Status

Accepted

## Context

The first firmware let any task write to the host: the console task sent replies, the worker task sent match and enrolment events, and the touch task sent touch and gesture events. Each call went straight into TinyUSB's CDC write and flush functions behind a mutex of our own.

The device went deaf three times in one afternoon. Each time it stayed enumerated but answered nothing, not even the READY line it sends when a host connects, and only a power cycle brought it back. Two of the three followed experiments with the software bootloader, which muddied the picture, but the third happened during ordinary use: watch mode on, a client streaming events, the client stopped. The macOS serial driver then blocked inside `open()` for any process that tried the port, which took the CLI down with it.

TinyUSB's class-driver API is not safe to call from several tasks. Its FIFOs are guarded, but a flush from an application task races the USB device task's own transfer completion, and a double-claimed endpoint stays stuck until reset. tinyTouch shares this structure and carries a `USB RECONNECT` command, which reads like the same problem seen from the other side.

## Decision

Only the console task touches the CDC endpoints. `link_send` formats a line and places it on a queue; the console task drains that queue between reads and performs every write and flush. Senders wait at most 20 ms for queue space and otherwise drop the line, so a host that has stopped reading can never stall the sensor or touch tasks. The device also blinks the XIAO's yellow LED from the console task: a stopped blink means the firmware is stuck, a blink with a silent host means the USB link is.

## Consequences

Events and replies leave in queue order, which can put a touch event ahead of a command reply by a few milliseconds. Clients already treat events as unsolicited, so nothing changes for them.

With the change in place the scenario that wedged the old firmware, a streaming client killed mid-session with watch mode on, left the device healthy. That is one data point, not proof, and the heartbeat exists so the next occurrence, if any, can be classified at a glance.

The CLI now opens the serial port on a helper thread with a timeout, so a deaf device produces "not responding; replug the device" in a few seconds instead of a hang.

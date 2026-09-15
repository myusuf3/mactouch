# ADR-0008: Newline-Delimited Text on Both Links

## Status

Accepted

## Context

Two links carry commands: USB serial between the daemon and the device, and a unix socket between the daemon and its clients. Binary framing with checksums would be more compact and stricter; the sensor itself speaks such a protocol.

## Decision

Both links are UTF-8 text, one message per line, verb first, then `key=value` fields, with a final free-text `reason=` allowed to contain spaces. Replies start with `OK`/`ERR` on the device link and `ok`/`err` on the socket; unsolicited lines start with `EVT`/`evt`. One response per command, in order.

## Consequences

The device can be driven from `screen` and the daemon from `nc`, which is how most of the hardware debugging in this project actually happened. Logs are readable as written. Clients in any language need only split on newlines.

Lines are capped at 256 bytes on the device and the reader drops overlong lines rather than buffering forever. Values cannot contain spaces except the trailing reason, and there is no checksum: USB CDC and unix sockets are reliable transports, so none was added.

# ADR-0010: USB Identity

## Status

Accepted, with a known gap

## Context

A USB device needs a vendor and product ID. The daemon finds the board by that pair, so it must be stable and distinct from tinytouch, which uses Espressif's vendor ID `0x303A` with product `0x4001`, and from the ROM's own identities.

## Decision

Vendor `0x303A`, Espressif's, and product `0x4D54`, the letters "MT", chosen by this project. The serial number is derived from the chip's MAC address so two boards can be told apart. The product string is `mactouch`.

## Consequences

The daemon and CLI match on the exact pair and never mistake another serial device for the board.

The product ID is not allocated. Espressif issues product IDs under their vendor ID to open-source projects free of charge through their `usb-pids` repository on GitHub. A request should be filed before anyone else builds a board, and the firmware and `DeviceLocator` updated to the assigned number. Until then a collision with another hobby project using the same made-up value is possible but harmless in practice.

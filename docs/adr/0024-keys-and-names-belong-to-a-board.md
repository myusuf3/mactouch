# ADR-0024: Keys and Names Belong to a Board

## Status

Accepted. Amends [ADR-0012](0012-pam-module-shape.md) on the key directory's mode.

## Context

The Mac keeps three things that only make sense for one board: the device key sudo verifies with (`/etc/mactouch/<user>.key`, ADR-0012), the device key password mode verifies with (mactouchd's keychain, ADR-0022), and the names people give fingers (the app's defaults). None of them said which board they came from. Plugging in a different board left all three in place: sudo quietly fell back to the password while the app showed it as on, password mode stopped typing, and the new board's slot 1 wore the old board's name. The finger list itself stayed on the old board until the Fingers pane was opened again.

Each board already has an identity the Mac can read without asking the board: its USB serial number, derived from the chip's MAC address (ADR-0010).

## Decision

mactouchd reads the serial number from the USB registry and reports it as `serial=` in `status`, in `evt device state=connected` and in the `pair` reply. Whatever stores a key stores the serial beside it, and a key counts only while that board is attached:

- `pam-install.sh` writes the serial to `/etc/mactouch/<user>.sensor` and keeps a stored key only when it names the attached board; otherwise it pairs again. The directory becomes 0755 so the app can read the `.sensor` file; the key file stays root-only 0600.
- mactouchd keeps the serial of its keychain key in its defaults. With another board attached, `password status` says `stored=no` and nothing is armed until `password set` pairs again.
- The app keeps finger names per serial, re-reads the finger list whenever a board connects, and clears what it showed when one goes.
- The app remembers the last board it saw. When another one is attached it opens the setup window on the first step that board still needs.

Keys and names stored before this had no serial and are treated as another board's: sudo and password mode ask to pair again, and old names are dropped.

## Consequences

Swapping boards is noticed and leads to the steps that fix it, instead of failing quietly at the next sudo. Sudo still holds one key per user, so moving between two boards means pairing again each time; keeping a key per board would need the PAM module to choose among them. A smart card pairing made with an old board stays on the account until it is unpaired; `sc_auth identities` only lists inserted cards, so the app already judges the attached board's card on its own.

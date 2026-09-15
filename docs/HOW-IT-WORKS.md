# How it works

The device is a Seeed XIAO ESP32-S3 wired to a ZW101 capacitive fingerprint
module. The module stores fingerprint templates in its own memory, matches a
live finger against them itself, and drives a ring of RGB LEDs around the
sensor. The ESP32-S3 talks to the module over a serial line and presents
itself to the Mac as a plain USB serial port.

Three pieces of software share the work:

- **Firmware** on the ESP32-S3. A thin peripheral: it exposes the sensor and
  the ring through a newline-delimited text protocol, detects touches and
  gestures, and holds one secret, a device key it uses to sign matches. It
  never decides what a colour means or what a match unlocks.
- **`mactouchd`**, a background daemon on the Mac started at login. It owns
  the USB connection, keeps the ring in sync with a stack of policy layers
  (idle colour, screen locked, Focus, privacy, notifications, pending
  request), watches the Mac for signals, and serves a local socket.
- **`mactouch`**, the command line tool. It talks to the daemon when it is
  running and straight to the device otherwise. Scripts, shell aliases, PAM
  and AI-agent hooks all use it.

A fingerprint request works like this: a program runs
`mactouch identify --reason "deploy to production"`. The daemon posts a macOS
notification with that reason, the ring breathes blue, and the device polls
the sensor. You press a finger; the module reports which template matched and
how well. The command exits 0 on a match and 2 on a timeout, so any script can
gate on it. With a nonce supplied, the reply also carries an HMAC over the
nonce and slot computed with the device key, which lets a verifier that holds
a copy of the key, such as a PAM module running as root, trust the answer
without trusting the daemon.


import Foundation
import MacTouchKit

// mactouchd: owns the device, runs the ring policy and the monitors, serves
// the control socket. Started by launchd; logs to stderr.

signal(SIGPIPE, SIG_IGN)

let daemon = Daemon(socketPath: ControlSocketPath.default)
do {
  try daemon.start()
} catch {
  log("cannot start: \(error)")
  exit(1)
}

// SIGTERM's default action is fine: the kernel closes the serial port and the
// socket, and the next start unlinks the stale socket file before binding.

// Distributed notifications (screen lock) need the main run loop.
RunLoop.main.run()

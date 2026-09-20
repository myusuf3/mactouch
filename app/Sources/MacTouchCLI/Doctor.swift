import Foundation
import MacTouchKit

// mactouch doctor: prints the kit's check-up. Works with or without the
// daemon; without it the device is asked directly.

func runDoctor(direct: Bool, port: String?) -> Int32 {
  let report = !direct && ControlClient.isAvailable()
    ? HealthReport.viaDaemon()
    : HealthReport.viaDevice(port: port, daemonSkipped: direct)
  print("mactouch check-up")
  for check in report.checks {
    print("  \(check.verdict.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))" +
          "\(check.name.padding(toLength: 11, withPad: " ", startingAt: 0))\(check.detail)")
  }
  return report.healthy ? 0 : 1
}

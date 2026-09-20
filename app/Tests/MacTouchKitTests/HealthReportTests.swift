import Foundation
import Testing
@testable import MacTouchKit

@Suite struct HealthReports {
  /// A daemon that answers `status` with the given fields and `selftest` as told.
  private func fakeDaemon(status: [(String, String)], selftestFails: String? = nil) throws -> ControlServer {
    let server = ControlServer(path: NSTemporaryDirectory() + "mactouch-health-\(UUID().uuidString.prefix(8)).sock")
    server.handler = { request, connection in
      switch request.verb {
      case "status": connection.send(ControlLine.ok("status", status))
      case "selftest":
        if let reason = selftestFails { connection.send(ControlLine.err("selftest", reason)) }
        else { connection.send(ControlLine.ok("selftest")) }
      default: connection.send(ControlLine.err(request.verb, "unknown"))
      }
    }
    try server.start()
    return server
  }

  private func verdicts(_ report: HealthReport) -> [String: HealthCheck.Verdict] {
    Dictionary(uniqueKeysWithValues: report.checks.map { ($0.name, $0.verdict) })
  }

  @Test func healthyDaemon() throws {
    let server = try fakeDaemon(status: [("device", "connected"), ("fw", "0.1.1"), ("sensor", "ready"),
                                         ("prints", "2"), ("monitors", "lock,focus"), ("focus", "assertions")])
    defer { server.stop() }
    let report = HealthReport.viaDaemon(at: server.path)
    let seen = verdicts(report)
    #expect(seen["daemon"] == .ok)
    #expect(seen["device"] == .ok)
    #expect(seen["sensor"] == .ok)
    #expect(seen["signature"] == .ok)
    #expect(seen["fingers"] == .ok)
    #expect(seen["focus"] == .ok)
    #expect(report.healthy)
    #expect(report.checks.first { $0.name == "device" }?.detail == "connected, firmware 0.1.1")
  }

  @Test func deviceAbsentAndNoFingers() throws {
    let server = try fakeDaemon(status: [("device", "absent"), ("monitors", "lock")])
    defer { server.stop() }
    let seen = verdicts(HealthReport.viaDaemon(at: server.path))
    #expect(seen["daemon"] == .ok)
    #expect(seen["device"] == .bad)
    #expect(seen["sensor"] == .off)
    #expect(seen["signature"] == nil)
    #expect(seen["fingers"] == nil)
    #expect(seen["focus"] == .off)
  }

  @Test func badSignatureIsBad() throws {
    let server = try fakeDaemon(status: [("device", "connected"), ("sensor", "ready"), ("prints", "0")], selftestFails: "hmac")
    defer { server.stop() }
    let report = HealthReport.viaDaemon(at: server.path)
    let seen = verdicts(report)
    #expect(seen["signature"] == .bad)
    #expect(seen["fingers"] == .warn)
    #expect(!report.healthy)
  }

  @Test func unreachableDaemonIsBad() {
    let seen = verdicts(HealthReport.viaDaemon(at: NSTemporaryDirectory() + "mactouch-nowhere.sock"))
    #expect(seen["daemon"] == .bad)
    #expect(seen["device"] == .bad)
  }

  @Test func missingPortIsBad() {
    let report = HealthReport.viaDevice(port: NSTemporaryDirectory() + "no-such-port", daemonSkipped: true)
    let seen = verdicts(report)
    #expect(seen["daemon"] == .off)
    #expect(seen["device"] == .bad)
    #expect(seen["sensor"] == .off)
  }
}

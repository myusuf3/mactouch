import Foundation
import Testing
@testable import MacTouchKit

@Suite struct ControlRequests {
  @Test func parsesVerbPositionalAndFields() throws {
    let request = try #require(ControlRequest.parse("LED breathe red timeout=5"))
    #expect(request.verb == "led")
    #expect(request.positional == ["breathe", "red"])
    #expect(request.int("timeout") == 5)
  }

  @Test func reasonRunsToEndOfLine() throws {
    let request = try #require(ControlRequest.parse("identify timeout=20 nonce=00ff reason=deploy to prod, please"))
    #expect(request["nonce"] == "00ff")
    #expect(request["reason"] == "deploy to prod, please")
    #expect(request.line == "identify nonce=00ff timeout=20 reason=deploy to prod, please")
  }

  @Test func emptyIsNil() {
    #expect(ControlRequest.parse("   ") == nil)
  }
}

@Suite struct ControlLines {
  @Test func formatsAndParses() throws {
    let ok = ControlLine.ok("status", [("device", "connected"), ("prints", "3")])
    #expect(ok == "ok status device=connected prints=3")
    guard case .ok(let verb, let fields)? = ControlLine.parse(ok) else { Issue.record("not ok"); return }
    #expect(verb == "status")
    #expect(fields.int("prints") == 3)

    #expect(ControlLine.parse(ControlLine.err("identify", "no match")) == .err(verb: "identify", reason: "no match"))
    #expect(ControlLine.parse("evt match slot=1 score=900")
            == .evt(name: "match", fields: Fields(values: ["slot": "1", "score": "900"])))
    #expect(ControlLine.parse("OK STATUS x=1") == nil)
  }

  @Test func reasonRunsToEndOfLineInEvents() {
    #expect(ControlLine.parse("evt request state=pending kind=plain reason=deploy to prod, please")
            == .evt(name: "request", fields: Fields(values: ["state": "pending", "kind": "plain", "reason": "deploy to prod, please"])))
  }
}

@Suite struct ControlSocketRoundTrip {
  @Test func requestAndEvents() throws {
    let path = NSTemporaryDirectory() + "mactouch-test-\(UUID().uuidString.prefix(8)).sock"
    let server = ControlServer(path: path)
    server.handler = { request, connection in
      switch request.verb {
      case "ping": connection.send(ControlLine.ok("ping", [("proto", "1")]))
      case "slow":
        connection.send(ControlLine.evt("step", [("n", "1")]))
        connection.send(ControlLine.ok("slow"))
      default: connection.send(ControlLine.err(request.verb, "unknown"))
      }
    }
    try server.start()
    defer { server.stop() }

    let client = try ControlClient(path: path)
    defer { client.close() }
    #expect(try client.request(ControlRequest(verb: "ping"))["proto"] == "1")
    var seen: [String] = []
    _ = try client.request(ControlRequest(verb: "slow")) { name, _ in seen.append(name) }
    #expect(seen == ["step"])
    #expect(throws: ControlError.self) { try client.request(ControlRequest(verb: "nope")) }
    #expect(ControlClient.isAvailable(at: path))
  }
}

import Foundation
import Testing
@testable import MacTouchKit

@Suite struct CommandEncoding {
  @Test func lines() {
    #expect(Command.ping.line == "PING")
    #expect(Command.led(.breathe, .magenta).line == "LED breathe magenta")
    #expect(Command.led(.flash, .red, .blue, cycles: 3).line == "LED flash red blue 3")
    #expect(Command.led(.off, .red).line == "LED off")
    #expect(Command.identify(timeoutMs: 15000).line == "IDENTIFY timeout=15000")
    #expect(Command.piv("GENKEY").line == "PIV GENKEY")
    #expect(Command.piv("STATUS").verb == "PIV")
    #expect(Command.identify(timeoutMs: 20000, prompt: .white, nonce: "00ff").line
            == "IDENTIFY timeout=20000 prompt=white nonce=00ff")
    #expect(Command.enroll(slot: 3).line == "ENROLL slot=3")
    #expect(Command.deleteAll.line == "DELETE all")
    #expect(Command.watch(true).line == "WATCH on")
    #expect(Command.touch(.poll).line == "TOUCH poll")
    #expect(Command.pair().line == "PAIR timeout=30000")
    #expect(Command.pair(timeoutMs: 5000).responseVerb == "PAIR")
    #expect(Command.selftest.line == "SELFTEST")
  }

  @Test func responseVerbs() {
    #expect(Command.ping.responseVerb == "PONG")
    #expect(Command.deleteAll.responseVerb == "DELETE")
    #expect(Command.identify(timeoutMs: 1000).responseVerb == "IDENTIFY")
  }
}

@Suite struct LineParsing {
  @Test func okWithFields() throws {
    let line = DeviceLine.parse("OK STATUS fw=0.1.0 proto=1 sensor=ready prints=4 finger=0\r\n")
    guard case .ok(let verb, let fields)? = line else { Issue.record("not OK"); return }
    #expect(verb == "STATUS")
    #expect(fields["sensor"] == "ready")
    #expect(fields.int("prints") == 4)
    #expect(fields.bool("finger") == false)
  }

  @Test func errReasonRunsToEndOfLine() {
    #expect(DeviceLine.parse("ERR IDENTIFY reason=no finger seen")
            == .err(verb: "IDENTIFY", reason: "no finger seen"))
  }

  @Test func event() {
    #expect(DeviceLine.parse("EVT MATCH slot=2 score=140")
            == .event(name: "MATCH", fields: Fields(values: ["slot": "2", "score": "140"])))
  }

  @Test func garbageIsNil() {
    #expect(DeviceLine.parse("") == nil)
    #expect(DeviceLine.parse("hello") == nil)
    #expect(DeviceLine.parse("WAT PING") == nil)
  }
}

@Suite struct LineBuffering {
  @Test func splitsAndStripsCR() {
    var buffer = LineBuffer()
    #expect(buffer.append(Data("OK PO".utf8)) == [])
    #expect(buffer.append(Data("NG\r\nEVT TOUCH state=down\nEVT".utf8)) == ["OK PONG", "EVT TOUCH state=down"])
    #expect(buffer.append(Data(" HOLD\n".utf8)) == ["EVT HOLD"])
  }

  @Test func dropsOverlongLines() {
    var buffer = LineBuffer(limit: 8)
    #expect(buffer.append(Data("0123456789abc\nOK PING\n".utf8)) == ["OK PING"])
    #expect(buffer.droppedOverlong == 1)
  }
}

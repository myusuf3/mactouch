import Foundation
import Testing
@testable import MacTouchKit

@Suite struct Firmware {
  /// A minimal image: header byte, then the app description where ESP-IDF puts it.
  private func image(version: String, project: String = "mactouch", size: Int = 1000) -> FirmwareImage {
    var bytes = [UInt8](repeating: 0, count: size)
    bytes[0] = 0xE9
    bytes.replaceSubrange(0x20..<0x24, with: [0x32, 0x54, 0xCD, 0xAB])
    bytes.replaceSubrange(0x30..<0x30 + version.utf8.count, with: Array(version.utf8))
    bytes.replaceSubrange(0x50..<0x50 + project.utf8.count, with: Array(project.utf8))
    return FirmwareImage(data: Data(bytes))
  }

  @Test func readsVersionAndProject() {
    let firmware = image(version: "0.2.0")
    #expect(firmware.version == "0.2.0")
    #expect(firmware.isMactouch)
    #expect(!image(version: "1.0", project: "tinytouch").isMactouch)
    #expect(firmware.sha256.count == 64)
  }

  @Test func comparesVersionsNumerically() {
    #expect(firmwareVersion("0.1.1", isOlderThan: "0.2.0"))
    #expect(firmwareVersion("0.9.3", isOlderThan: "0.10.0"))
    #expect(!firmwareVersion("0.2.0", isOlderThan: "0.2.0"))
    #expect(!firmwareVersion("0.3", isOlderThan: "0.2.9"))
  }

  @Test func streamsTheImageInOrderAndEndsIt() throws {
    let firmware = image(version: "0.2.0", size: 500)
    var lines: [String] = []
    var written = 0
    let updater = FirmwareUpdater(image: firmware) { step, _ in
      lines.append(step)
      if step.hasPrefix("WRITE") {
        let data = step.split(separator: " ").first { $0.hasPrefix("data=") }!.dropFirst(5)
        written += Data(base64Encoded: String(data))!.count
        return Fields(values: ["next": "\(written)"])
      }
      return Fields()
    }
    var steps: [FirmwareUpdater.Step] = []
    try updater.run { steps.append($0) }
    #expect(lines.first == "BEGIN size=500 sha256=\(firmware.sha256)")
    #expect(lines.last == "END")
    #expect(lines.filter { $0.hasPrefix("WRITE") }.count == 3)
    #expect(lines.allSatisfy { ("FW " + $0).utf8.count < 256 })
    #expect(written == 500)
    #expect(steps.first == .waitingForTouch && steps.last == .installing)
  }

  @Test func aLostEndReplyIsNotAFailure() throws {
    var written = 0
    let updater = FirmwareUpdater(image: image(version: "0.2.0", size: 200)) { step, _ in
      if step == "END" { throw ControlError.rejected(verb: "fw", reason: "device") }
      if step.hasPrefix("WRITE") {
        let data = step.split(separator: " ").first { $0.hasPrefix("data=") }!.dropFirst(5)
        written += Data(base64Encoded: String(data))!.count
        return Fields(values: ["next": "\(written)"])
      }
      return Fields()
    }
    try updater.run()
  }

  @Test func abortsWhenTheDeviceLosesStep() {
    var lines: [String] = []
    let updater = FirmwareUpdater(image: image(version: "0.2.0", size: 500)) { step, _ in
      lines.append(step)
      return step.hasPrefix("WRITE") ? Fields(values: ["next": "7"]) : Fields()
    }
    #expect(throws: FirmwareError.self) { try updater.run() }
    #expect(lines.last == "ABORT")
  }
}

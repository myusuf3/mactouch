import Foundation
import Testing
@testable import MacTouchKit

@Suite struct FocusAssertionParsing {
  private func write(_ json: String) -> String {
    let path = NSTemporaryDirectory() + "assertions-\(UUID().uuidString.prefix(8)).json"
    try! json.write(toFile: path, atomically: true, encoding: .utf8)
    return path
  }

  @Test func namesTheActiveMode() {
    let path = write("""
    {"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}
    """)
    #expect(FocusMonitor.parse(path: path) == "com.apple.donotdisturb.mode.default")
  }

  @Test func noRecordsMeansNoFocus() {
    let path = write(#"{"data":[{"storeAssertionRecords":[]}]}"#)
    #expect(FocusMonitor.parse(path: path) == nil)
  }

  @Test func garbageMeansNoFocus() {
    #expect(FocusMonitor.parse(path: write("not json")) == nil)
    #expect(FocusMonitor.parse(path: "/nonexistent/Assertions.json") == nil)
  }
}

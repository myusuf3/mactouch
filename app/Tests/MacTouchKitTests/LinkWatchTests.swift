import Foundation
import Testing
@testable import MacTouchKit

@Suite struct LinkWatches {
  private let start = Date(timeIntervalSince1970: 1_000_000)
  private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

  @Test func oneTimeoutIsNotEnough() {
    var watch = LinkWatch()
    #expect(watch.timedOut(now: at(0)) == false)
  }

  @Test func twoInARowWithNothingHeardMeansDeaf() {
    var watch = LinkWatch()
    #expect(watch.timedOut(now: at(0)) == false)
    #expect(watch.timedOut(now: at(5)) == true)
  }

  @Test func anythingHeardInBetweenStartsOver() {
    var watch = LinkWatch()
    #expect(watch.timedOut(now: at(0)) == false)
    watch.heard()
    #expect(watch.timedOut(now: at(5)) == false)
    #expect(watch.timedOut(now: at(10)) == true)
  }

  @Test func resetsAtMostOncePerCooldown() {
    var watch = LinkWatch(threshold: 2, cooldown: 60)
    #expect(watch.timedOut(now: at(0)) == false)
    #expect(watch.timedOut(now: at(1)) == true)
    // A board that stays dead after a reset is not reset in a loop.
    #expect(watch.timedOut(now: at(2)) == false)
    #expect(watch.timedOut(now: at(30)) == false)
    #expect(watch.timedOut(now: at(62)) == true)
  }
}

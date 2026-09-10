import Foundation
import Testing
@testable import MacTouchKit

@Suite struct PolicyResolution {
  @Test func idleWhenNothingActive() {
    let policy = LEDPolicy(idle: .cyan)
    #expect(policy.resolve() == .steady(.cyan))
    #expect(policy.active() == [.idle])
  }

  @Test func highestLayerWins() {
    var policy = LEDPolicy(idle: .cyan)
    policy.set(.focus, .steady(.magenta))
    policy.set(.privacy, RingState(.breathe, .red))
    #expect(policy.resolve() == RingState(.breathe, .red))
    policy.clear(.privacy)
    #expect(policy.resolve() == .steady(.magenta))
    #expect(policy.active() == [.idle, .focus])
  }

  @Test func lockedTurnsRingOffBelowPrivacy() {
    var policy = LEDPolicy(idle: .cyan)
    policy.set(.locked, .off)
    #expect(policy.resolve() == .off)
    policy.set(.privacy, RingState(.breathe, .red))
    #expect(policy.resolve().colour == .red)
  }

  @Test func notifyExpires() {
    let start = Date()
    var policy = LEDPolicy(idle: .cyan)
    policy.set(.notify, .steady(.yellow), for: 5, now: start)
    #expect(policy.resolve(now: start.addingTimeInterval(4)) == .steady(.yellow))
    #expect(policy.nextExpiry(now: start) == start.addingTimeInterval(5))
    #expect(policy.resolve(now: start.addingTimeInterval(6)) == .steady(.cyan))
    policy.dropExpired(now: start.addingTimeInterval(6))
    #expect(policy.active(now: start.addingTimeInterval(6)) == [.idle])
    #expect(policy.nextExpiry(now: start.addingTimeInterval(6)) == nil)
  }

  @Test func offColourCollapsesToOffMode() {
    #expect(RingState(.breathe, .off) == .off)
    #expect(RingState(.on, .red).command == .led(.on, .red))
    #expect(RingState(.flash, .red, .blue).description == "flash:red:blue")
  }
}

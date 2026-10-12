import Foundation

/// Decides when a serial link that has stopped answering gets a USB reset.
/// Host sleep can leave the board's serial endpoints wedged while it still
/// enumerates; a bus reset clears that where nothing sent over the link can.
/// A single timeout can be a slow reply, so it takes `threshold` in a row
/// with nothing heard between them, and at most one reset per `cooldown`,
/// so a board that is truly dead is not reset in a loop.
public struct LinkWatch {
  private let threshold: Int
  private let cooldown: TimeInterval
  private var missed = 0
  private var lastReset: Date?

  public init(threshold: Int = 2, cooldown: TimeInterval = 60) {
    self.threshold = threshold
    self.cooldown = cooldown
  }

  /// Any line from the device.
  public mutating func heard() { missed = 0 }

  /// True when the device should be reset now.
  public mutating func timedOut(now: Date = Date()) -> Bool {
    missed += 1
    guard missed >= threshold else { return false }
    if let last = lastReset, now.timeIntervalSince(last) < cooldown { return false }
    lastReset = now
    missed = 0
    return true
  }
}

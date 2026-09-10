import Foundation

/// Reports when the screen locks and unlocks. Needs the main run loop, which
/// is where distributed notifications are delivered.
public final class ScreenLockMonitor {
  public var onChange: ((Bool) -> Void)?
  public private(set) var isLocked = false
  private var observers: [NSObjectProtocol] = []

  public init() {}

  public func start() {
    let center = DistributedNotificationCenter.default()
    observers = [
      center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: nil) { [weak self] _ in
        self?.isLocked = true
        self?.onChange?(true)
      },
      center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: nil) { [weak self] _ in
        self?.isLocked = false
        self?.onChange?(false)
      },
    ]
  }

  public func stop() {
    let center = DistributedNotificationCenter.default()
    observers.forEach(center.removeObserver)
    observers.removeAll()
  }
}

import Foundation

/// Keeps one `Device` open for as long as a mactouch is attached, polling for
/// it while it is absent. Callbacks arrive on the manager's private queue.
public final class DeviceManager {
  public var onConnect: ((Device) -> Void)?
  public var onDisconnect: (() -> Void)?
  public var onEvent: ((String, Fields) -> Void)?
  public var onLog: ((String) -> Void)?

  private let queue = DispatchQueue(label: "mactouch.devices")
  private let pollInterval: TimeInterval
  private var timer: DispatchSourceTimer?
  private var current: Device?
  private var running = false

  public init(pollInterval: TimeInterval = 1) { self.pollInterval = pollInterval }

  public var device: Device? { queue.sync { current } }
  public var isConnected: Bool { device != nil }

  public func start() {
    queue.async { [self] in
      guard !self.running else { return }
      self.running = true
      self.scan()
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now() + self.pollInterval, repeating: self.pollInterval)
      timer.setEventHandler { [weak self] in self?.scan() }
      self.timer = timer
      timer.resume()
    }
  }

  public func stop() {
    queue.sync {
      running = false
      timer?.cancel()
      timer = nil
      current?.close()
      current = nil
    }
  }

  /// Runs `body` with the attached device, or throws `DeviceError.notFound`.
  public func withDevice<T>(_ body: (Device) throws -> T) throws -> T {
    guard let device = self.device else { throw DeviceError.notFound }
    return try body(device)
  }

  private func scan() {
    guard current == nil else { return }
    let paths = DeviceLocator.calloutPaths()
    guard let path = paths.first else { return }
    if paths.count > 1 { onLog?("several devices attached, using \(path)") }
    do {
      let device = try Device(path: path)
      device.onEvent = { [weak self] name, fields in self?.onEvent?(name, fields) }
      device.onDisconnect = { [weak self] in
        guard let self else { return }
        self.queue.async {
          guard self.current === device else { return }
          self.current = nil
          self.onLog?("device disconnected")
          self.onDisconnect?()
        }
      }
      current = device
      onLog?("device connected at \(path)")
      onConnect?(device)
    } catch {
      // The node can exist before the driver is ready; try again next tick.
      onLog?("open failed: \(error)")
    }
  }
}

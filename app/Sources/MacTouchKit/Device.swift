import Foundation

/// Request and response over one serial port, with events delivered as they
/// arrive. `request` blocks the calling thread; call it off the main thread in
/// UI code.
public final class Device {
  public let path: String
  /// Events, including the ones a long command emits before its reply.
  public var onEvent: ((String, Fields) -> Void)?
  public var onDisconnect: (() -> Void)?
  /// Every raw line from the device, for debugging.
  public var onRawLine: ((String) -> Void)?
  /// Every line written to the device, for debugging.
  public var onRawWrite: ((String) -> Void)?

  private let port: SerialPort
  private let state = NSLock()
  private var pending: ((DeviceLine?) -> Void)?
  private let requests = NSLock()

  public init(path: String) throws {
    self.path = path
    port = try SerialPort(path: path)
    port.onLine = { [weak self] line in self?.handle(line) }
    port.onClose = { [weak self] in
      guard let self else { return }
      self.resolve(nil)
      self.onDisconnect?()
    }
    port.start()
  }

  public convenience init() throws {
    guard let path = try DeviceLocator.find() else { throw DeviceError.notFound }
    try self.init(path: path)
  }

  private func handle(_ raw: String) {
    onRawLine?(raw)
    guard let line = DeviceLine.parse(raw) else { return }
    if case .event(let name, let fields) = line {
      onEvent?(name, fields)
      return
    }
    // `cancel()` never waits for this, and the command it interrupts is the
    // one waiting, so the acknowledgement must not be handed to it.
    if case .ok(let verb, _) = line, verb == "CANCEL" { return }
    resolve(line)
  }

  /// Interrupts the command in flight. CANCEL is the one command the device
  /// answers while another is running, so it goes out without the request
  /// lock and without waiting; the interrupted command then fails with
  /// `reason=cancelled` and its caller learns the outcome that way.
  public func cancel() throws {
    onRawWrite?(Command.cancel.line)
    try port.write(Command.cancel.line + "\n")
  }

  private func resolve(_ line: DeviceLine?) {
    state.lock()
    let waiter = pending
    pending = nil
    state.unlock()
    waiter?(line)
  }

  /// Sends a command and returns its OK fields. Throws `rejected` on ERR.
  @discardableResult
  public func request(_ command: Command, timeout: TimeInterval = 5) throws -> Fields {
    requests.lock()
    defer { requests.unlock() }

    final class Box { var line: DeviceLine?; var closed = false }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    state.lock()
    pending = { line in
      if let line { box.line = line } else { box.closed = true }
      done.signal()
    }
    state.unlock()

    onRawWrite?(command.line)
    try port.write(command.line + "\n")
    if done.wait(timeout: .now() + timeout) == .timedOut {
      state.lock(); pending = nil; state.unlock()
      throw DeviceError.timeout(verb: command.verb)
    }
    if box.closed { throw DeviceError.disconnected }
    switch box.line {
    case .ok(let verb, let fields):
      guard verb == command.responseVerb else { throw DeviceError.unexpected("OK \(verb)") }
      return fields
    case .err(let verb, let reason):
      throw DeviceError.rejected(verb: verb, reason: reason)
    default:
      throw DeviceError.unexpected("no reply")
    }
  }

  public func close() { port.close() }
}

import Darwin
import Foundation

/// One accepted client on the control socket.
public final class ControlConnection {
  public let id = UUID()
  /// Set by the handler when the client asked for the event stream.
  public var subscribed = false
  fileprivate let fd: Int32
  fileprivate var lines = LineBuffer()
  fileprivate var source: DispatchSourceRead?
  fileprivate var closed = false

  fileprivate init(fd: Int32) {
    self.fd = fd
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
  }

  public func send(_ line: String) {
    guard !closed else { return }
    var bytes = Array((line + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
      let n = bytes.withUnsafeMutableBufferPointer { Darwin.write(fd, $0.baseAddress! + offset, $0.count - offset) }
      if n <= 0 { return }
      offset += n
    }
  }

  public func close() {
    guard !closed else { return }
    closed = true
    source?.cancel()
  }
}

/// Unix-domain socket server. Lines from each client arrive on `handler`
/// with the connection to answer on. Everything runs on one private queue.
public final class ControlServer {
  public typealias Handler = (ControlRequest, ControlConnection) -> Void
  public let path: String
  public var handler: Handler?
  public var onDisconnect: ((ControlConnection) -> Void)?

  private let queue = DispatchQueue(label: "mactouch.control")
  private var listenFD: Int32 = -1
  private var listenSource: DispatchSourceRead?
  private var connections: [UUID: ControlConnection] = [:]

  public init(path: String) { self.path = path }

  public func start() throws {
    let directory = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    unlink(path)
    listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard listenFD >= 0 else { throw ControlError.socket(errno) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count < capacity else { throw ControlError.pathTooLong }
    withUnsafeMutablePointer(to: &address.sun_path) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, path, capacity - 1) }
    }
    let previous = umask(0o177)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    umask(previous)
    guard bound == 0 else { throw ControlError.socket(errno) }
    guard listen(listenFD, 16) == 0 else { throw ControlError.socket(errno) }

    let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptClient() }
    listenSource = source
    source.resume()
  }

  public func stop() {
    queue.sync {
      listenSource?.cancel()
      if listenFD >= 0 { Darwin.close(listenFD) }
      for connection in connections.values { connection.close() }
      connections.removeAll()
      unlink(path)
    }
  }

  /// Sends a line to every client that asked for events.
  public func broadcast(_ line: String) {
    queue.async { [weak self] in
      guard let self else { return }
      for connection in self.connections.values where connection.subscribed { connection.send(line) }
    }
  }

  private func acceptClient() {
    let fd = accept(listenFD, nil, nil)
    guard fd >= 0 else { return }
    let connection = ControlConnection(fd: fd)
    connections[connection.id] = connection
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self, weak connection] in
      guard let self, let connection else { return }
      self.readFrom(connection)
    }
    source.setCancelHandler { [weak self] in
      Darwin.close(fd)
      self?.connections.removeValue(forKey: connection.id)
      self?.onDisconnect?(connection)
    }
    connection.source = source
    source.resume()
  }

  private func readFrom(_ connection: ControlConnection) {
    var chunk = [UInt8](repeating: 0, count: 2048)
    let n = read(connection.fd, &chunk, chunk.count)
    guard n > 0 else { connection.close(); return }
    for line in connection.lines.append(Data(chunk[0..<n])) {
      guard let request = ControlRequest.parse(line) else {
        connection.send(ControlLine.err("command", "unparseable"))
        continue
      }
      handler?(request, connection)
    }
  }
}

/// Blocking client for the CLI and tests.
public final class ControlClient {
  private let fd: Int32
  private var lines = LineBuffer()
  private var pending: [String] = []

  public static func isAvailable(at path: String = ControlSocketPath.default) -> Bool {
    guard FileManager.default.fileExists(atPath: path) else { return false }
    guard let client = try? ControlClient(path: path) else { return false }
    client.close()
    return true
  }

  public init(path: String = ControlSocketPath.default) throws {
    fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ControlError.socket(errno) }
    var one: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strncpy($0, path, capacity - 1) }
    }
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else {
      let code = errno
      Darwin.close(fd)
      throw ControlError.connect(path: path, errno: code)
    }
  }

  public func send(_ line: String) throws {
    var bytes = Array((line + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
      let n = bytes.withUnsafeMutableBufferPointer { Darwin.write(fd, $0.baseAddress! + offset, $0.count - offset) }
      guard n > 0 else { throw ControlError.socket(errno) }
      offset += n
    }
  }

  /// Next line, or nil when the timeout passes. Throws on disconnect.
  public func readLine(timeout: TimeInterval) throws -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while pending.isEmpty {
      let remaining = deadline.timeIntervalSinceNow
      if remaining <= 0 { return nil }
      var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let ready = poll(&descriptor, 1, Int32(remaining * 1000))
      if ready < 0 && errno == EINTR { continue }
      if ready == 0 { return nil }
      var chunk = [UInt8](repeating: 0, count: 2048)
      let n = read(fd, &chunk, chunk.count)
      guard n > 0 else { throw ControlError.disconnected }
      pending.append(contentsOf: lines.append(Data(chunk[0..<n])))
    }
    return pending.removeFirst()
  }

  /// Sends a request and reads until its `ok` or `err`, handing intermediate
  /// `evt` lines to `onEvent`.
  public func request(_ request: ControlRequest, timeout: TimeInterval = 10,
                      onEvent: ((String, Fields) -> Void)? = nil) throws -> Fields {
    try send(request.line)
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      guard let line = try readLine(timeout: max(0, deadline.timeIntervalSinceNow)) else {
        throw ControlError.timeout(verb: request.verb)
      }
      switch ControlLine.parse(line) {
      case .ok(_, let fields): return fields
      case .err(let verb, let reason): throw ControlError.rejected(verb: verb, reason: reason)
      case .evt(let name, let fields): onEvent?(name, fields)
      case nil: continue
      }
    }
  }

  public func close() { Darwin.close(fd) }
}

public enum ControlError: Error, CustomStringConvertible {
  case socket(Int32)
  case pathTooLong
  case connect(path: String, errno: Int32)
  case disconnected
  case timeout(verb: String)
  case rejected(verb: String, reason: String)

  public var description: String {
    switch self {
    case .socket(let code): return "socket error: \(String(cString: strerror(code)))"
    case .pathTooLong: return "control socket path is too long"
    case .connect(let path, let code): return "cannot reach mactouchd at \(path): \(String(cString: strerror(code)))"
    case .disconnected: return "mactouchd closed the connection"
    case .timeout(let verb): return "\(verb) timed out waiting for mactouchd"
    case .rejected(let verb, let reason): return "\(verb) failed: \(reason)"
    }
  }
}

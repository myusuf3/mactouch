import Darwin
import Foundation

/// A USB CDC serial port read on a private queue. Lines arrive on `onLine`,
/// EOF or a read error on `onClose`. The baud rate is irrelevant over USB but
/// the driver still wants one.
public final class SerialPort {
  public let path: String
  public var onLine: ((String) -> Void)?
  public var onClose: (() -> Void)?

  private let fd: Int32
  private let queue = DispatchQueue(label: "mactouch.serial")
  private var source: DispatchSourceRead?
  private var lines = LineBuffer()
  private var closed = false

  public init(path: String, openTimeout: TimeInterval = 3) throws {
    self.path = path
    // macOS's USB serial driver can block inside open() when the device has
    // stopped answering USB control requests, and O_NONBLOCK does not help.
    // Open on a helper thread and give up after a timeout; the stuck thread
    // is abandoned, which is fine for a process that is about to report an
    // error.
    final class Result { var fd: Int32 = -1; var error: Int32 = 0 }
    let result = Result()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      result.fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
      result.error = errno
      done.signal()
    }
    guard done.wait(timeout: .now() + openTimeout) != .timedOut else {
      throw DeviceError.openStalled(path: path)
    }
    fd = result.fd
    guard fd >= 0 else { throw DeviceError.openFailed(path: path, errno: result.error) }
    // Refuse to share the port: two writers would interleave commands.
    _ = ioctl(fd, TIOCEXCL)

    var tty = termios()
    tcgetattr(fd, &tty)
    cfmakeraw(&tty)
    cfsetspeed(&tty, speed_t(B115200))
    tty.c_cflag |= tcflag_t(CLOCAL | CREAD)
    tty.c_cflag &= ~tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
    tcsetattr(fd, TCSANOW, &tty)
    tcflush(fd, TCIOFLUSH)
  }

  public func start() {
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in self?.readAvailable() }
    source.setCancelHandler { [weak self] in
      guard let self else { return }
      Darwin.close(self.fd)
    }
    self.source = source
    source.resume()
  }

  private func readAvailable() {
    var chunk = [UInt8](repeating: 0, count: 1024)
    while true {
      let n = read(fd, &chunk, chunk.count)
      if n > 0 {
        for line in lines.append(Data(chunk[0..<n])) { onLine?(line) }
        continue
      }
      if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) {
        finish()
      }
      return
    }
  }

  private func finish() {
    guard !closed else { return }
    closed = true
    source?.cancel()
    onClose?()
  }

  /// Writes the whole string. A device whose USB data path has wedged never
  /// drains its buffer, so the retry loop gives up after `timeout` instead of
  /// spinning forever.
  public func write(_ text: String, timeout: TimeInterval = 2) throws {
    var data = Array(text.utf8)
    var offset = 0
    let deadline = Date().addingTimeInterval(timeout)
    while offset < data.count {
      let n = data.withUnsafeMutableBufferPointer { buf in
        Darwin.write(fd, buf.baseAddress! + offset, buf.count - offset)
      }
      if n < 0 {
        guard errno == EAGAIN else { throw DeviceError.writeFailed(errno: errno) }
        guard Date() < deadline else { throw DeviceError.writeStalled }
        usleep(1000)
        continue
      }
      offset += n
    }
  }

  public func close() {
    queue.sync { finish() }
  }

  deinit {
    if !closed { source?.cancel() }
    if source == nil { Darwin.close(fd) }
  }
}

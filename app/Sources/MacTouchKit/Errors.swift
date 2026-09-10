import Foundation

public enum DeviceError: Error, CustomStringConvertible {
  case notFound
  case openFailed(path: String, errno: Int32)
  case openStalled(path: String)
  case writeFailed(errno: Int32)
  case writeStalled
  case timeout(verb: String)
  case disconnected
  case rejected(verb: String, reason: String)
  case unexpected(String)

  public var description: String {
    switch self {
    case .notFound: return "no mactouch device found"
    case .openFailed(let path, let code): return "cannot open \(path): \(String(cString: strerror(code)))"
    case .openStalled(let path): return "\(path) is not responding; replug the device"
    case .writeFailed(let code): return "write failed: \(String(cString: strerror(code)))"
    case .writeStalled: return "device is not accepting data; replug it"
    case .timeout(let verb): return "\(verb) timed out waiting for the device"
    case .disconnected: return "device disconnected"
    case .rejected(let verb, let reason): return "\(verb) failed: \(reason)"
    case .unexpected(let text): return "unexpected reply: \(text)"
    }
  }
}

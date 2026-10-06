import CoreGraphics
import Darwin

/// macOS turns on secure input while a password field has focus, and says
/// which process did. Nothing announces the change, so password mode polls.
public enum SecureInput {
  /// The process holding secure input, nil when nothing is.
  public static func holder() -> pid_t? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
          let pid = session["kCGSSessionSecureInputPID"] as? Int, pid > 0 else { return nil }
    return pid_t(pid)
  }

  /// The executable's name, which is what the request panel shows.
  public static func processName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
    guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "another app" }
    return String(cString: buffer)
  }
}

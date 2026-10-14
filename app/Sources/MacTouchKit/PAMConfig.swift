import Foundation

/// Where pam_mactouch is installed and which PAM services load it, as
/// scripts/pam-install.sh leaves them.
public enum PAMConfig {
  public static let module = "/usr/local/lib/pam/pam_mactouch.so"
  public static let keyDirectory = "/etc/mactouch"

  /// The serial of the board whose key sudo holds for `user`, ADR-0024.
  /// The key itself is root-only; this note beside it is not. Nil when sudo
  /// was paired by an install that did not record the board.
  public static func keyBoard(in directory: String = keyDirectory, user: String = NSUserName()) -> String? {
    (try? String(contentsOfFile: "\(directory)/\(user).sensor", encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The files in `directory` that name the module, sorted. `sudo_local`
  /// stands for sudo on a Mac that has it, since sudo includes it.
  public static func services(in directory: String = "/etc/pam.d") -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    return files.sorted().filter { name in
      (try? String(contentsOfFile: directory + "/" + name, encoding: .utf8))?.contains(module) ?? false
    }
  }
}

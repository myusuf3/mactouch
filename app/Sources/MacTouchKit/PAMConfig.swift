import Foundation

/// Where pam_mactouch is installed and which PAM services load it, as
/// scripts/pam-install.sh leaves them.
public enum PAMConfig {
  public static let module = "/usr/local/lib/pam/pam_mactouch.so"

  /// The files in `directory` that name the module, sorted. `sudo_local`
  /// stands for sudo on a Mac that has it, since sudo includes it.
  public static func services(in directory: String = "/etc/pam.d") -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
    return files.sorted().filter { name in
      (try? String(contentsOfFile: directory + "/" + name, encoding: .utf8))?.contains(module) ?? false
    }
  }
}

import Foundation

/// What `sc_auth identities` says about the smart cards macOS can see,
/// narrowed to this device's certificates.
public struct SmartCardIdentities: Equatable, Sendable {
  public struct Identity: Equatable, Sendable {
    public let hash: String
    public let name: String
  }
  public var paired: [Identity] = []
  public var unpaired: [Identity] = []

  public init(paired: [Identity] = [], unpaired: [Identity] = []) {
    self.paired = paired
    self.unpaired = unpaired
  }

  /// The subject this device's authentication certificate carries.
  public static let certificateName = "mactouch PIV Authentication"

  /// Sections are "Paired identities:" and "Unpaired identities:", each
  /// followed by `<hash><tab><name>` lines.
  public static func parse(_ text: String) -> SmartCardIdentities {
    var result = SmartCardIdentities()
    var section: WritableKeyPath<SmartCardIdentities, [Identity]>?
    for line in text.split(separator: "\n") {
      if line.hasPrefix("Paired identities") { section = \.paired; continue }
      if line.hasPrefix("Unpaired identities") { section = \.unpaired; continue }
      guard let section, let tab = line.firstIndex(of: "\t") else { continue }
      let name = line[line.index(after: tab)...].trimmingCharacters(in: .whitespaces)
      guard name.contains(certificateName) else { continue }
      result[keyPath: section].append(Identity(hash: String(line[..<tab]), name: name))
    }
    return result
  }

  /// Runs `sc_auth identities`; nil when it cannot run.
  public static func current() -> SmartCardIdentities? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/sc_auth")
    process.arguments = ["identities"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return parse(text)
  }
}

import Foundation

/// An app or website the user has given a password, ADR-0023: their Mac
/// password, or one of its own kept in the keychain under `account`.
public struct PasswordTarget: Codable, Equatable, Hashable, Sendable {
  public enum Kind: String, Codable, Sendable { case app, site }
  public enum Source: String, Codable, Sendable { case mac, own }

  public var kind: Kind
  /// A bundle ID, or a site's host name in lower case.
  public var id: String
  public var uses: Source

  public init(kind: Kind, id: String, uses: Source) {
    self.kind = kind
    self.id = kind == .site ? Self.normalise(id) : id
    self.uses = uses
  }

  /// The keychain account an own password is kept under.
  public var account: String { "\(kind.rawValue):\(id)" }

  private static func normalise(_ host: String) -> String {
    host.trimmingCharacters(in: .whitespaces).lowercased()
  }

  /// A bare host name: letters, digits and hyphens in two or more labels,
  /// with no scheme, path or port.
  public static func isValidSite(_ host: String) -> Bool {
    let labels = normalise(host).split(separator: ".", omittingEmptySubsequences: false)
    return labels.count >= 2 && labels.allSatisfy { label in
      !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
  }

  /// The list as it crosses the control socket: base64 of JSON, one field.
  public static func encode(_ targets: [PasswordTarget]) -> String {
    ((try? JSONEncoder().encode(targets)) ?? Data("[]".utf8)).base64EncodedString()
  }

  public static func decode(_ text: String) throws -> [PasswordTarget] {
    guard let data = Data(base64Encoded: text) else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not base64")) }
    return try JSONDecoder().decode([PasswordTarget].self, from: data)
  }
}

/// Which password a field gets: the Mac password, or a target's own.
public enum PasswordKey: Equatable, Sendable {
  case mac
  case own(account: String)
}

/// A password field password mode can fill: who is asking, for the request
/// panel, and with which password.
public struct PasswordField: Equatable, Sendable {
  public var label: String
  public var password: PasswordKey

  public init(label: String, password: PasswordKey) {
    self.label = label
    self.password = password
  }
}

/// What the daemon sees when a password field has focus: the process
/// holding secure input, and for a browser the host in its address bar,
/// when Accessibility lets it read that.
public struct PasswordContext: Equatable, Sendable {
  public var screenLocked: Bool
  public var bundleID: String?
  public var appName: String
  public var host: String?

  public init(screenLocked: Bool, bundleID: String?, appName: String, host: String?) {
    self.screenLocked = screenLocked
    self.bundleID = bundleID
    self.appName = appName
    self.host = host
  }
}

public enum PasswordTargets {
  /// Always the Mac password, whatever the user has saved: the system's own
  /// prompts and the terminals sudo asks in.
  public static let builtIn: [String: String] = [
    "com.apple.loginwindow": "the login window",
    "com.apple.SecurityAgent": "a system dialog",
    "com.apple.coreautha": "a system dialog",
    "com.apple.Terminal": "Terminal",
    "com.googlecode.iterm2": "iTerm2",
    "com.mitchellh.ghostty": "Ghostty",
    "com.github.wez.wezterm": "WezTerm",
    "net.kovidgoyal.kitty": "kitty",
    "org.alacritty": "Alacritty",
    "dev.warp.Warp-Stable": "Warp",
  ]

  /// Apps whose password fields belong to the page, so they match by site.
  public static let browsers: Set<String> = [
    "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
    "org.chromium.Chromium", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
    "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "org.mozilla.firefox",
  ]

  public static func isBuiltIn(_ bundleID: String) -> Bool { builtIn[bundleID] != nil }

  /// The lock screen and built-ins take the Mac password; a browser takes
  /// what was saved for the exact host; any other app what was saved for
  /// it. Nil when nothing applies, and then nothing is typed.
  public static func field(for context: PasswordContext, targets: [PasswordTarget]) -> PasswordField? {
    if context.screenLocked { return PasswordField(label: "the lock screen", password: .mac) }
    guard let bundle = context.bundleID else { return nil }
    if let label = builtIn[bundle] { return PasswordField(label: label, password: .mac) }
    if browsers.contains(bundle) {
      guard let host = context.host?.lowercased(),
            let site = targets.first(where: { $0.kind == .site && $0.id == host }) else { return nil }
      return PasswordField(label: host, password: key(for: site))
    }
    guard let app = targets.first(where: { $0.kind == .app && $0.id == bundle }) else { return nil }
    return PasswordField(label: context.appName, password: key(for: app))
  }

  private static func key(for target: PasswordTarget) -> PasswordKey {
    target.uses == .mac ? .mac : .own(account: target.account)
  }
}

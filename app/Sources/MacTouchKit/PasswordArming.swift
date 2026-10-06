import Foundation

/// When password mode arms the sensor, and whether a match earns the
/// password (ADR-0022). The daemon reports what it sees; this decides, so
/// tests can drive it without a Mac or a device.
public struct PasswordArming {
  public struct Inputs: Equatable {
    public var mode: UnlockMode
    public var passwordStored: Bool
    /// Who has a password field focused, nil when nothing does.
    public var field: String?

    public init(mode: UnlockMode, passwordStored: Bool, field: String?) {
      self.mode = mode
      self.passwordStored = passwordStored
      self.field = field
    }
  }

  public enum Change: Equatable {
    case arm(nonce: String, field: String)
    case disarm
  }

  public enum Outcome: Equatable {
    case type(field: String)
    /// The match was signed, but not by this device for this nonce.
    case reject
    /// Not armed, or not signed: a match for something else.
    case ignore
  }

  private let nonce: () -> String
  private var armed: (nonce: String, field: String)?
  /// A field the user cancelled; it stays unarmed until focus moves on.
  private var dismissed: String?

  public init(nonce: @escaping () -> String = PasswordArming.randomNonce) {
    self.nonce = nonce
  }

  public mutating func update(_ inputs: Inputs) -> Change? {
    if inputs.field != dismissed { dismissed = nil }
    let wanted = inputs.mode == .password && inputs.passwordStored ? inputs.field : nil
    if let field = wanted, field != dismissed {
      if armed?.field == field { return nil }
      let fresh = nonce()
      armed = (fresh, field)
      return .arm(nonce: fresh, field: field)
    }
    guard armed != nil else { return nil }
    armed = nil
    return .disarm
  }

  /// The device disarms itself on any armed match, so this does too.
  public mutating func matched(slot: Int, mac: String?, key: Data) -> Outcome {
    guard let current = armed, let mac else { return .ignore }
    armed = nil
    return ApprovalMAC.verify(key: key, nonce: current.nonce, slot: slot, mac: mac) ? .type(field: current.field) : .reject
  }

  public mutating func dismiss() -> Change? {
    guard let current = armed else { return nil }
    dismissed = current.field
    armed = nil
    return .disarm
  }

  /// A device that dropped off the link has forgotten its nonce.
  public mutating func deviceReset() { armed = nil }

  /// What the device can type: printable ASCII, as many characters as its
  /// TYPE line carries.
  public static func typeable(_ password: String) -> Bool {
    let bytes = Array(password.utf8)
    return !bytes.isEmpty && bytes.count <= 64 && bytes.allSatisfy { (0x20...0x7E).contains($0) }
  }

  public static func randomNonce() -> String {
    (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
  }
}

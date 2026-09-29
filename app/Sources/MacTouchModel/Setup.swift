import Foundation
import MacTouchKit

/// The pieces the app bundle carries to turn on sudo by fingerprint:
/// scripts/pam-install.sh, the module it installs, and the CLI it pairs with.
public struct SudoInstaller: Equatable, Sendable {
  public let script: String
  public let module: String
  public let cli: String
  public init(script: String, module: String, cli: String) {
    self.script = script; self.module = module; self.cli = cli
  }
}

/// The steps of the setup window, docs/ONBOARDING.md, in order.
public enum SetupStep: Int, CaseIterable, Sendable {
  case connect, firmware, finger, sudo, smartCard

  /// Optional steps are offered but never nag.
  public var isOptional: Bool { self == .smartCard }
}

extension DaemonModel {
  /// Whether a step is done, read from the sensor and the Mac rather than
  /// remembered, so the window picks up wherever things stand.
  public func isDone(_ step: SetupStep) -> Bool {
    switch step {
    case .connect: return deviceConnected
    case .firmware: return deviceConnected && firmware != nil && !firmwareUpdateAvailable
    case .finger: return (prints ?? 0) > 0
    case .sudo: return health?.checks.first { $0.name == "sudo" }?.verdict == .ok
    case .smartCard: return smartCard?.paired == true
    }
  }

  /// Whether this Mac still needs setting up, nil until the health report
  /// says. Sudo by fingerprint is the thing MacTouch is for, and unlike the
  /// sensor's state it does not depend on the sensor being plugged in.
  public var needsSetup: Bool? {
    guard health != nil else { return nil }
    return !isDone(.sudo)
  }

  public var canEnableSudo: Bool { sudoInstaller != nil }
}

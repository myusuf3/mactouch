import Foundation
import MacTouchKit

/// What the app bundle carries to change the Mac as root, ADR-0021: the PAM
/// module with the scripts that install and remove it, and the CLI, which
/// the install script pairs with and /usr/local/bin can point at.
public struct BundledTools: Equatable, Sendable {
  public let pamInstall: String
  public let pamUninstall: String
  public let pamModule: String
  public let cli: String
  public init(pamInstall: String, pamUninstall: String, pamModule: String, cli: String) {
    self.pamInstall = pamInstall; self.pamUninstall = pamUninstall; self.pamModule = pamModule; self.cli = cli
  }
}

/// What sits where the app puts the `mactouch` command.
public enum CommandLineTool: Equatable, Sendable {
  case absent
  /// A link to this copy of the app's CLI.
  case installed
  /// A link into another copy of MacTouch.app, such as one since moved.
  case stale
  /// Something that is not MacTouch's; the app leaves it alone.
  case occupied

  public static func status(at link: String, for cli: String) -> CommandLineTool {
    guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else {
      return FileManager.default.fileExists(atPath: link) ? .occupied : .absent
    }
    if destination == cli { return .installed }
    return destination.hasSuffix("MacTouch.app/Contents/Helpers/mactouch") ? .stale : .occupied
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
    case .sudo: return sudoByFingerprint
    case .smartCard: return smartCard?.paired == true
    }
  }

  /// Whether sudo itself loads the module, directly or through the
  /// sudo_local file it includes. Other services, such as su, do not count.
  public var sudoByFingerprint: Bool {
    pamServices?.contains { $0 == "sudo" || $0 == "sudo_local" } ?? false
  }

  /// Whether this Mac still needs setting up, nil until its PAM files have
  /// been read. Sudo by fingerprint is the thing MacTouch is for, and unlike
  /// the sensor's state it does not depend on the sensor being plugged in.
  public var needsSetup: Bool? {
    pamServices.map { _ in !sudoByFingerprint }
  }

  public var canChangeSudo: Bool { tools != nil }
}

import Foundation
import MacTouchKit
import OpenDirectory

/// Password mode (ADR-0022): while a password field has focus the sensor is
/// armed and the ring breathes white; a match signed against the arming
/// nonce gets the password from the keychain, which the sensor types.
extension Daemon {
  /// Secure input is polled, so a field is noticed within this long.
  private static let fieldPoll: DispatchTimeInterval = .milliseconds(500)

  func startWatchingForPasswordFields() {
    // Read before the observers exist, so no change can be overwritten.
    screenLocked = ScreenLockMonitor.sessionIsLocked()
    screen.onChange = { [weak self] locked in
      self?.queue.async {
        self?.screenLocked = locked
        self?.updateArming()
      }
    }
    screen.start()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + Self.fieldPoll, repeating: Self.fieldPoll)
    timer.setEventHandler { [weak self] in self?.updateArming() }
    fieldTimer = timer
    timer.resume()
  }

  /// Who is asking for a password: the lock screen, or whichever process
  /// holds secure input. The app's own password sheet is not a request.
  private var passwordField: String? {
    if screenLocked { return "the lock screen" }
    guard let pid = SecureInput.holder(), pid != getpid() else { return nil }
    let name = SecureInput.processName(pid)
    return name == "MacTouch" ? nil : name
  }

  /// Nothing changes while a long command owns the link: the device would
  /// not match for the arming then anyway.
  func updateArming() {
    guard busy == nil, let device = manager.device else { return }
    let inputs = PasswordArming.Inputs(mode: unlockMode, passwordStored: passwordStored && deviceKey != nil,
                                       field: passwordField)
    switch arming.update(inputs) {
    case .arm(let nonce, let field)?:
      do {
        try device.request(.arm(nonce: nonce))
      } catch {
        log("arming failed: \(describe(error))")
        arming.deviceReset()
        return
      }
      log("armed for \(field)")
      setLayer(.prompt, RingState(.breathe, .white))
      server.broadcast(ControlLine.evt("request", [("state", "pending"), ("kind", "password"),
                                                   ("reason", "Touch to type your password into \(field)")]))
    case .disarm?:
      _ = try? device.request(.arm(nonce: nil))
      endPrompt()
    case nil:
      break
    }
  }

  func deviceForgotArming() {
    arming.deviceReset()
    endPrompt()
  }

  /// The request panel's Cancel; true when there was an arming to cancel.
  func dismissArming() -> Bool {
    guard arming.dismiss() != nil else { return false }
    if let device = manager.device { _ = try? device.request(.arm(nonce: nil)) }
    endPrompt()
    return true
  }

  private func endPrompt() {
    guard policy.active().contains(.prompt) else { return }
    setLayer(.prompt, nil)
    server.broadcast(ControlLine.evt("request", [("state", "done"), ("kind", "password")]))
  }

  func passwordMatch(_ fields: Fields) {
    guard let key = deviceKey, let slot = fields.int("slot") else { return }
    switch arming.matched(slot: slot, mac: fields["mac"], key: key) {
    case .type(let field):
      endPrompt()
      guard let device = manager.device, let data = Vault.read(.password),
            let password = String(data: data, encoding: .utf8) else { return }
      do {
        try device.request(.type(password: password), timeout: 10)
        log("typed the password into \(field)")
      } catch {
        log("typing failed: \(describe(error))")
      }
    case .reject:
      endPrompt()
      log("a match came back signed with another key; not typing")
    case .ignore:
      break
    }
  }

  /// `password status|clear`, and `password set hex=<utf-8 as hex>`, which
  /// checks the password against the account and, the first time, takes the
  /// device key with a touch so matches can be verified.
  func passwordRequest(_ request: ControlRequest, _ connection: ControlConnection) {
    let verb = request.verb
    switch request.positional.first {
    case "status":
      connection.send(ControlLine.ok(verb, [("stored", passwordStored && deviceKey != nil ? "yes" : "no")]))
    case "clear":
      Vault.remove(.password)
      passwordStored = false
      updateArming()
      connection.send(ControlLine.ok(verb))
    case "set":
      guard let data = request["hex"].flatMap(Data.init(hex:)), let password = String(data: data, encoding: .utf8) else {
        return connection.send(ControlLine.err(verb, "value"))
      }
      guard PasswordArming.typeable(password) else { return connection.send(ControlLine.err(verb, "characters")) }
      guard Self.isAccountPassword(password) else { return connection.send(ControlLine.err(verb, "wrong")) }
      if deviceKey != nil {
        store(password, verb, connection)
      } else {
        runLong(verb, connection, timeout: 33) { [weak self] device in
          let fields: Fields
          do {
            fields = try device.request(.pair(timeoutMs: 30000), timeout: 33)
          } catch DeviceError.rejected(_, "already") {
            throw DeviceError.rejected(verb: "PAIR", reason: "key_released")
          }
          guard let key = fields["key"].flatMap(Data.init(hex:)), key.count == 32 else {
            throw DeviceError.rejected(verb: "PAIR", reason: "key")
          }
          try Vault.write(.deviceKey, key)
          try Vault.write(.password, Data(password.utf8))
          self?.queue.async {
            self?.deviceKey = key
            self?.passwordStored = true
          }
          return Fields()
        }
      }
    default:
      connection.send(ControlLine.err(verb, "value"))
    }
  }

  private func store(_ password: String, _ verb: String, _ connection: ControlConnection) {
    do {
      try Vault.write(.password, Data(password.utf8))
      passwordStored = true
      updateArming()
      connection.send(ControlLine.ok(verb))
    } catch {
      connection.send(ControlLine.err(verb, "keychain"))
    }
  }

  /// Checked against the account, so a typo is caught here rather than at
  /// the lock screen.
  private static func isAccountPassword(_ password: String) -> Bool {
    guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
          let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil) else {
      return false
    }
    return (try? record.verifyPassword(password)) != nil
  }
}

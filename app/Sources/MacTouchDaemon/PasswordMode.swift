import Foundation
import MacTouchKit
import OpenDirectory

/// Password mode (ADR-0022): while a password field has focus the sensor is
/// armed and the ring breathes white; a match signed against the arming
/// nonce gets the password from the keychain, which the sensor types. Which
/// password follows the app or site asking, ADR-0023.
extension Daemon {
  /// Secure input is polled, so a field is noticed within this long.
  private static let fieldPoll: DispatchTimeInterval = .milliseconds(500)
  private static let targetsKey = "password.targets"

  func startWatchingForPasswordFields() {
    passwordTargets = (defaults.string(forKey: Self.targetsKey)).flatMap { try? PasswordTarget.decode($0) } ?? []
    ownStored = Set(passwordTargets.filter { $0.uses == .own && Vault.read(.password, account: $0.account) != nil }.map(\.account))
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

  /// Who is asking for a password, and which one they get: the lock screen,
  /// or whichever process holds secure input. MacTouch's own password sheet
  /// is not a request.
  private var passwordField: PasswordField? {
    var context = PasswordContext(screenLocked: screenLocked, bundleID: nil, appName: "", host: nil)
    if !screenLocked {
      guard let pid = SecureInput.holder(), pid != getpid() else { return nil }
      context.bundleID = SecureInput.bundleID(pid)
      guard context.bundleID != "dev.mactouch.app" else { return nil }
      context.appName = SecureInput.processName(pid)
      if let bundle = context.bundleID, PasswordTargets.browsers.contains(bundle) {
        context.host = BrowserAddress.host(pid: pid)
      }
    }
    return PasswordTargets.field(for: context, targets: passwordTargets)
  }

  private func hasPassword(_ key: PasswordKey) -> Bool {
    switch key {
    case .mac: return passwordStored
    case .own(let account): return ownStored.contains(account)
    }
  }

  /// Nothing changes while a long command owns the link: the device would
  /// not match for the arming then anyway.
  func updateArming() {
    guard busy == nil, let device = manager.device else { return }
    let field = passwordField
    let inputs = PasswordArming.Inputs(mode: unlockMode, passwordStored: deviceKey != nil && field.map { hasPassword($0.password) } == true,
                                       field: field)
    switch arming.update(inputs) {
    case .arm(let nonce, let field)?:
      do {
        try device.request(.arm(nonce: nonce))
      } catch {
        log("arming failed: \(describe(error))")
        arming.deviceReset()
        return
      }
      log("armed for \(field.label)")
      setLayer(.prompt, RingState(.breathe, .white))
      let whose = field.password == .mac ? "your Mac password" : "its password"
      server.broadcast(ControlLine.evt("request", [("state", "pending"), ("kind", "password"),
                                                   ("reason", "Touch to type \(whose) into \(field.label)")]))
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
      let stored: Data?
      switch field.password {
      case .mac: stored = Vault.read(.password)
      case .own(let account): stored = Vault.read(.password, account: account)
      }
      guard let device = manager.device else { return }
      guard let data = stored, let password = String(data: data, encoding: .utf8) else {
        // The login keychain locks on a timeout or on sleep if the user set it to.
        return log("cannot read the password for \(field.label); is the login keychain locked? Nothing typed")
      }
      do {
        try device.request(.type(password: password), timeout: 10)
        log("typed the password into \(field.label)")
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

  /// `targets` lists what the user has added; `target set kind=app|site
  /// id=… uses=mac|own [hex=…]` adds or changes one, with its own password
  /// when it has one; `target remove kind=… id=…` drops it and its password.
  func targetRequest(_ request: ControlRequest, _ connection: ControlConnection) {
    let verb = request.verb
    func fail(_ reason: String) { connection.send(ControlLine.err(verb, reason)) }
    if verb == "targets" {
      return connection.send(ControlLine.ok(verb, [("list", PasswordTarget.encode(passwordTargets)),
                                                    ("accessibility", BrowserAddress.allowed ? "yes" : "no")]))
    }
    guard let kind = request["kind"].flatMap(PasswordTarget.Kind.init), let id = request["id"], !id.isEmpty else {
      return fail("value")
    }
    switch request.positional.first {
    case "set":
      guard let uses = request["uses"].flatMap(PasswordTarget.Source.init) else { return fail("value") }
      let target = PasswordTarget(kind: kind, id: id, uses: uses)
      if kind == .app && PasswordTargets.isBuiltIn(target.id) { return fail("builtin") }
      if kind == .site && !PasswordTarget.isValidSite(target.id) { return fail("site") }
      if uses == .own {
        if let hex = request["hex"] {
          guard let data = Data(hex: hex), let password = String(data: data, encoding: .utf8) else { return fail("value") }
          guard PasswordArming.typeable(password) else { return fail("characters") }
          do { try Vault.write(.password, data, account: target.account) } catch { return fail("keychain") }
          ownStored.insert(target.account)
        } else if !ownStored.contains(target.account) {
          return fail("password")
        }
      } else {
        Vault.remove(.password, account: target.account)
        ownStored.remove(target.account)
      }
      passwordTargets.removeAll { $0.kind == kind && $0.id == target.id }
      passwordTargets.append(target)
      if kind == .site && !BrowserAddress.allowed { BrowserAddress.requestAccess() }
    case "remove":
      let account = PasswordTarget(kind: kind, id: id, uses: .own).account
      passwordTargets.removeAll { $0.account == account }
      Vault.remove(.password, account: account)
      ownStored.remove(account)
    default:
      return fail("value")
    }
    defaults.set(PasswordTarget.encode(passwordTargets), forKey: Self.targetsKey)
    updateArming()
    connection.send(ControlLine.ok(verb))
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

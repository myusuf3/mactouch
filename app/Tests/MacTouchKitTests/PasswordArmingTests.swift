import Foundation
import Testing
@testable import MacTouchKit

@Suite struct PasswordArmings {
  private let key = Data(repeating: 7, count: 32)
  private var nonces: () -> String {
    var count = 0
    return {
      count += 1
      return String(format: "%032x", count)
    }
  }

  private func field(_ label: String) -> PasswordField { PasswordField(label: label, password: .mac) }

  private func ready(_ label: String?) -> PasswordArming.Inputs {
    PasswordArming.Inputs(mode: .password, passwordStored: true, field: label.map(field))
  }

  @Test func armsWhileAPasswordFieldHasFocus() {
    var arming = PasswordArming(nonce: nonces)
    #expect(arming.update(ready(nil)) == nil)
    #expect(arming.update(ready("Terminal")) == .arm(nonce: String(format: "%032x", 1), field: field("Terminal")))
    #expect(arming.update(ready("Terminal")) == nil)
    #expect(arming.update(ready(nil)) == .disarm)
    #expect(arming.update(ready(nil)) == nil)
  }

  @Test func onlyInPasswordModeWithAPasswordSaved() {
    var arming = PasswordArming(nonce: nonces)
    #expect(arming.update(.init(mode: .pin, passwordStored: true, field: field("loginwindow"))) == nil)
    #expect(arming.update(.init(mode: .password, passwordStored: false, field: field("loginwindow"))) == nil)
    #expect(arming.update(ready("loginwindow")) != nil)
    #expect(arming.update(.init(mode: .pin, passwordStored: true, field: field("loginwindow"))) == .disarm)
  }

  @Test func aSignedMatchForTheCurrentNonceEarnsThePassword() {
    var arming = PasswordArming(nonce: nonces)
    guard case .arm(let nonce, _)? = arming.update(ready("SecurityAgent")) else { Issue.record("not armed"); return }
    let mac = ApprovalMAC.compute(key: key, nonce: nonce, slot: 2)
    #expect(arming.matched(slot: 2, mac: mac, key: key) == .type(field: field("SecurityAgent")))
    // One match, one password: the device disarmed itself, and so does this.
    #expect(arming.matched(slot: 2, mac: mac, key: key) == .ignore)
    // Still focused, say after a wrong password: armed again on a fresh nonce.
    #expect(arming.update(ready("SecurityAgent")) == .arm(nonce: String(format: "%032x", 2), field: field("SecurityAgent")))
  }

  @Test func refusesAMatchItCannotVerify() {
    var arming = PasswordArming(nonce: nonces)
    guard case .arm(let nonce, _)? = arming.update(ready("loginwindow")) else { Issue.record("not armed"); return }
    #expect(arming.matched(slot: 2, mac: nil, key: key) == .ignore)
    let otherSlot = ApprovalMAC.compute(key: key, nonce: nonce, slot: 3)
    #expect(arming.matched(slot: 2, mac: otherSlot, key: key) == .reject)
    // The device disarms after any armed match, so a second try needs arming again.
    guard case .arm(let again, _)? = arming.update(ready("loginwindow")) else { Issue.record("not rearmed"); return }
    let otherKey = ApprovalMAC.compute(key: Data(repeating: 9, count: 32), nonce: again, slot: 2)
    #expect(arming.matched(slot: 2, mac: otherKey, key: key) == .reject)
  }

  @Test func aMatchWhileNotArmedIsSomeoneElses() {
    var arming = PasswordArming(nonce: nonces)
    let mac = ApprovalMAC.compute(key: key, nonce: String(format: "%032x", 1), slot: 1)
    #expect(arming.matched(slot: 1, mac: mac, key: key) == .ignore)
  }

  @Test func aDifferentPasswordForTheSameAppRearms() {
    var arming = PasswordArming(nonce: nonces)
    #expect(arming.update(ready("Safari")) != nil)
    let other = PasswordField(label: "Safari", password: .own(account: "site:github.com"))
    #expect(arming.update(.init(mode: .password, passwordStored: true, field: other))
            == .arm(nonce: String(format: "%032x", 2), field: other))
  }

  @Test func dismissingWaitsForTheFieldToChange() {
    var arming = PasswordArming(nonce: nonces)
    #expect(arming.update(ready("Terminal")) != nil)
    #expect(arming.dismiss() == .disarm)
    #expect(arming.update(ready("Terminal")) == nil)
    #expect(arming.update(ready(nil)) == nil)
    #expect(arming.update(ready("Terminal")) != nil)
  }

  @Test func aReconnectedDeviceHasForgottenItsNonce() {
    var arming = PasswordArming(nonce: nonces)
    #expect(arming.update(ready("Terminal")) != nil)
    arming.deviceReset()
    #expect(arming.update(ready("Terminal")) == .arm(nonce: String(format: "%032x", 2), field: field("Terminal")))
  }

  @Test func passwordsGoOverTheLinkAsHex() {
    #expect(PasswordArming.typeable("hunter2 !") == true)
    #expect(PasswordArming.typeable("café") == false)
    #expect(PasswordArming.typeable("") == false)
    #expect(PasswordArming.typeable(String(repeating: "x", count: 65)) == false)
    #expect(Command.type(password: "aB").line == "TYPE 6142")
  }
}

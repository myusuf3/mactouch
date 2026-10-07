import Foundation
import Security

/// What password mode keeps on the Mac (ADR-0022, ADR-0023): the passwords it
/// types and the device key that proves a match came from the sensor. They
/// live in the login keychain of the process that stores them, which is
/// mactouchd, so it reads them back without a prompt. The Mac password is
/// under the user's name; an app's or site's own under its target account.
public enum Vault {
  public enum Item: String {
    case password = "dev.mactouch.password"
    case deviceKey = "dev.mactouch.device-key"
  }

  public struct Failure: Error, CustomStringConvertible {
    public let status: OSStatus
    public var description: String {
      SecCopyErrorMessageString(status, nil) as String? ?? "keychain error \(status)"
    }
  }

  private static func query(_ item: Item, _ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: item.rawValue,
     kSecAttrAccount as String: account]
  }

  public static func read(_ item: Item, account: String = NSUserName()) -> Data? {
    var query = query(item, account)
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }

  public static func write(_ item: Item, _ data: Data, account: String = NSUserName()) throws {
    let status = SecItemUpdate(query(item, account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw Failure(status: status) }
    var add = query(item, account)
    add[kSecValueData as String] = data
    let added = SecItemAdd(add as CFDictionary, nil)
    guard added == errSecSuccess else { throw Failure(status: added) }
  }

  public static func remove(_ item: Item, account: String = NSUserName()) {
    SecItemDelete(query(item, account) as CFDictionary)
  }
}

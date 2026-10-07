import ApplicationServices

/// The host of the page whose field has focus in a browser, read through
/// Accessibility (ADR-0023). Needs the user to allow the reading process in
/// System Settings, Privacy & Security, Accessibility.
public enum BrowserAddress {
  public static var allowed: Bool { AXIsProcessTrusted() }

  /// Shows the system's request to allow Accessibility, once per process.
  public static func requestAccess() {
    let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
  }

  /// Walks up from the focused element to the web area holding it and reads
  /// that page's URL. Chromium and Electron build their tree for assistive
  /// apps only once asked to, hence AXManualAccessibility.
  public static func host(pid: pid_t) -> String? {
    guard allowed else { return nil }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    var element = child(app, kAXFocusedUIElementAttribute)
    for _ in 0..<64 {
      guard let current = element else { return nil }
      if attribute(current, kAXRoleAttribute) as? String == "AXWebArea" {
        return (attribute(current, kAXURLAttribute) as? URL)?.host?.lowercased()
      }
      element = child(current, kAXParentAttribute)
    }
    return nil
  }

  private static func child(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
  }

  private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
  }
}

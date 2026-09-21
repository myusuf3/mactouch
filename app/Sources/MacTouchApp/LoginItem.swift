import ServiceManagement

/// Launch at login through the system's login item for this bundle, which
/// lists MacTouch under Login Items in System Settings. `requiresApproval`
/// means registered but waiting for the user to allow it there.
final class LoginItem: ObservableObject {
  @Published private(set) var status = SMAppService.mainApp.status
  @Published private(set) var lastError: String?

  var isEnabled: Bool { status == .enabled || status == .requiresApproval }

  func set(enabled: Bool) {
    do {
      if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
    refresh()
  }

  func refresh() {
    status = SMAppService.mainApp.status
  }

  func openLoginItems() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

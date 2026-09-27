import MacTouchKit
import MacTouchModel
import SwiftUI

/// The menu bar app: a view over mactouchd, one more client of its socket.
/// A plain menu, as the HIG asks of menu bar extras; the `touchid` symbol is
/// a template image so the system colours it for light and dark menu bars.
@main
struct MacTouchApp: App {
  @StateObject private var model: DaemonModel
  @StateObject private var agent: DaemonAgent
  @StateObject private var loginItem: LoginItem
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  /// The HIG leaves it to people whether an extra sits in their menu bar.
  /// The app keeps running hidden; opening it again brings the icon back.
  @AppStorage(showInMenuBarKey) private var showInMenuBar = true
  private let requestPanel: RequestPanel

  init() {
    let image = Bundle.main.url(forResource: "mactouch", withExtension: "bin", subdirectory: "firmware")
      .flatMap { try? FirmwareImage(contentsOf: $0) }
    let model = DaemonModel(bundledFirmware: image?.isMactouch == true ? image : nil)
    _model = StateObject(wrappedValue: model)
    let agent = DaemonAgent()
    _agent = StateObject(wrappedValue: agent)
    let loginItem = LoginItem()
    _loginItem = StateObject(wrappedValue: loginItem)
    requestPanel = RequestPanel(model: model)
    agent.install()
    loginItem.registerOnFirstLaunch()
  }

  var body: some Scene {
    MenuBarExtra("MacTouch", systemImage: "touchid", isInserted: $showInMenuBar) {
      StatusMenu(model: model, agent: agent)
    }
    Settings {
      SettingsView(model: model, loginItem: loginItem)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Opening the app while it already runs, from Finder or Spotlight, is the
  /// way back once the menu bar icon has been hidden, and how daemon.sh
  /// starts the bundled agent.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    UserDefaults.standard.set(true, forKey: showInMenuBarKey)
    DaemonAgent().register()
    return true
  }
}

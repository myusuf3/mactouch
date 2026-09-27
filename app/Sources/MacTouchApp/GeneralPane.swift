import MacTouchModel
import SwiftUI

struct GeneralPane: View {
  @ObservedObject var model: DaemonModel
  @ObservedObject var loginItem: LoginItem
  @AppStorage(showInMenuBarKey) private var showInMenuBar = true

  var body: some View {
    Form {
      Section {
        Toggle(isOn: launchAtLogin) {
          RowLabel(title: "Open at Login", detail: "So it is there the next time sudo asks.", symbol: "power", tint: .gray)
        }
        if loginItem.status == .requiresApproval {
          LabeledContent("Waiting for approval under Login Items") {
            Button("Open Login Items…") { loginItem.openLoginItems() }
          }
        }
        if let error = loginItem.lastError {
          Text(error).foregroundStyle(.red)
        }
      }
      Section {
        Toggle(isOn: $showInMenuBar) {
          RowLabel(title: "Show in Menu Bar", detail: nil, symbol: "menubar.rectangle", tint: .blue)
        }
      } footer: {
        Footnote("Without the icon, MacTouch keeps running and still shows fingerprint requests. Open MacTouch again to bring the icon back.")
      }
    }
    .formStyle(.grouped)
    .onAppear { loginItem.refresh() }
  }

  private var launchAtLogin: Binding<Bool> {
    Binding(get: { loginItem.isEnabled }, set: { loginItem.set(enabled: $0) })
  }
}

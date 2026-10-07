import AppKit
import MacTouchKit
import MacTouchModel
import SwiftUI
import UniformTypeIdentifiers

/// Which password password mode types where, ADR-0023: the Mac password for
/// the lock screen, system prompts and terminals, and for each app or site
/// the user adds either that or a password of its own. Everything else is
/// left alone.
struct PasswordsPane: View {
  @ObservedObject var model: DaemonModel
  @State private var draft: TargetDraft?
  @State private var pickError: String?

  var body: some View {
    Form {
      if model.smartCard?.unlockMode != .password {
        Section {
          Label("These are typed only in password mode. Turn it on in Smart Card, under Unlock With.", systemImage: "info.circle")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        RowLabel(title: "Lock Screen and System Prompts", detail: "The login window and dialogs that ask to make changes.",
                 symbol: "lock.fill", tint: .gray)
        RowLabel(title: "Terminals", detail: terminals, symbol: "terminal.fill", tint: .black)
      } header: {
        Text("Always Your Mac Password")
      } footer: {
        Footnote("sudo and other system prompts ask for your Mac password, so these get it whatever else is saved.")
      }
      Section {
        if let targets = model.passwordTargets {
          if targets.isEmpty {
            Text("No apps or websites yet.").foregroundStyle(.secondary)
          }
          ForEach(targets, id: \.self) { target in
            row(target)
          }
        } else {
          Text(model.daemonRunning ? "Reading…" : "MacTouch's background service is not running.").foregroundStyle(.secondary)
        }
        HStack {
          Button("Add App…", action: pickApp)
          Button("Add Website…") { draft = TargetDraft(kind: .site) }
        }
        .disabled(model.passwordTargets == nil)
        if let error = pickError ?? model.targetError {
          Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
      } header: {
        Text("Apps and Websites")
      } footer: {
        Footnote("A password field in anything not listed is left alone. Websites match the exact address in the browser's address bar, so a look-alike site gets nothing.")
      }
      if model.passwordTargets?.contains(where: { $0.kind == .site }) == true && model.browserAccessAllowed == false {
        Section {
          HStack {
            Label("To tell sites apart, allow mactouchd in Accessibility.", systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
            Spacer()
            Button("Open Settings") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      model.refreshPasswordTargets()
      model.refreshSmartCard()
    }
    .sheet(item: $draft) { draft in
      TargetSheet(model: model, draft: draft)
    }
  }

  private var terminals: String {
    let names = Set(PasswordTargets.builtIn.values).subtracting(["the login window", "a system dialog"])
    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: ", ")
  }

  private func row(_ target: PasswordTarget) -> some View {
    HStack(spacing: 10) {
      TargetIcon(target: target)
      VStack(alignment: .leading, spacing: 2) {
        Text(TargetDraft.name(of: target))
        Text(target.uses == .mac ? "Your Mac password" : "Its own password")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Change…") { draft = TargetDraft(target) }
      Button {
        model.removePasswordTarget(target)
      } label: {
        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
      }
      .buttonStyle(.borderless)
      .help("Remove, along with its saved password")
    }
  }

  private func pickApp() {
    pickError = nil
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = "Choose"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let bundle = Bundle(url: url)?.bundleIdentifier else {
      pickError = "That app has no bundle identifier to match."
      return
    }
    if PasswordTargets.isBuiltIn(bundle) {
      pickError = "That app always gets your Mac password."
    } else if PasswordTargets.browsers.contains(bundle) {
      pickError = "Browsers match by website; use Add Website… instead."
    } else {
      draft = TargetDraft(kind: .app, id: bundle)
    }
  }
}

/// An app's icon, or a globe for a site.
private struct TargetIcon: View {
  var target: PasswordTarget

  var body: some View {
    if target.kind == .app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: 26, height: 26)
    } else {
      SettingsIcon(symbol: target.kind == .app ? "app.fill" : "globe", tint: .blue, size: 26)
    }
  }
}

/// A target being added or changed in the sheet.
struct TargetDraft: Identifiable {
  let id = UUID()
  var kind: PasswordTarget.Kind
  var targetID = ""
  var uses: PasswordTarget.Source = .own
  /// Changing one that already has its own password saved.
  var hasOwnPassword = false
  var isNew = true

  init(kind: PasswordTarget.Kind, id: String = "") {
    self.kind = kind
    self.targetID = id
  }

  init(_ target: PasswordTarget) {
    kind = target.kind
    targetID = target.id
    uses = target.uses
    hasOwnPassword = target.uses == .own
    isNew = false
  }

  static func name(of target: PasswordTarget) -> String {
    guard target.kind == .app else { return target.id }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) else { return target.id }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
  }
}

private struct TargetSheet: View {
  @ObservedObject var model: DaemonModel
  @State var draft: TargetDraft
  @Environment(\.dismiss) private var dismiss
  @State private var password = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(.headline)
      Form {
        if draft.kind == .site && draft.isNew {
          TextField("Website", text: $draft.targetID, prompt: Text("github.com"))
        }
        Picker("Type", selection: $draft.uses) {
          Text("Its Own Password").tag(PasswordTarget.Source.own)
          Text("Your Mac Password").tag(PasswordTarget.Source.mac)
        }
        if draft.uses == .own {
          SecureField("Password", text: $password,
                      prompt: Text(draft.hasOwnPassword ? "Leave empty to keep the saved one" : "Required"))
        }
      }
      .formStyle(.columns)
      if draft.kind == .site && !draft.targetID.isEmpty && !PasswordTarget.isValidSite(draft.targetID) {
        Text("Just the host name as the address bar shows it, like accounts.google.com.")
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save", action: save)
          .keyboardShortcut(.defaultAction)
          .disabled(!canSave)
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  private var title: String {
    let name = draft.isNew && draft.kind == .site ? "a Website" : TargetDraft.name(of: target)
    return draft.isNew ? "Add \(name)" : "Change \(name)"
  }

  private var target: PasswordTarget { PasswordTarget(kind: draft.kind, id: draft.targetID, uses: draft.uses) }

  private var canSave: Bool {
    if draft.kind == .site && !PasswordTarget.isValidSite(draft.targetID) { return false }
    if draft.uses == .own && password.isEmpty && !draft.hasOwnPassword { return false }
    return true
  }

  private func save() {
    guard canSave else { return }
    model.savePasswordTarget(target, password: draft.uses == .own && !password.isEmpty ? password : nil)
    password = ""
    dismiss()
  }
}

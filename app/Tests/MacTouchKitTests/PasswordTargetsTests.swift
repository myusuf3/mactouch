import Foundation
import Testing
@testable import MacTouchKit

@Suite struct PasswordTargetChoices {
  private func context(_ bundle: String?, name: String = "App", host: String? = nil, locked: Bool = false) -> PasswordContext {
    PasswordContext(screenLocked: locked, bundleID: bundle, appName: name, host: host)
  }

  private let slack = PasswordTarget(kind: .app, id: "com.tinyspeck.slackmacgap", uses: .own)
  private let zoom = PasswordTarget(kind: .app, id: "us.zoom.xos", uses: .mac)
  private let github = PasswordTarget(kind: .site, id: "github.com", uses: .own)

  @Test func theLockScreenAndSystemPromptsTakeTheMacPassword() {
    #expect(PasswordTargets.field(for: context("com.tinyspeck.slackmacgap", locked: true), targets: [slack])
            == PasswordField(label: "the lock screen", password: .mac))
    #expect(PasswordTargets.field(for: context("com.apple.SecurityAgent"), targets: [])
            == PasswordField(label: "a system dialog", password: .mac))
    #expect(PasswordTargets.field(for: context("com.apple.loginwindow"), targets: [])?.password == .mac)
  }

  @Test func terminalsTakeTheMacPasswordWhateverIsSaved() {
    #expect(PasswordTargets.field(for: context("com.apple.Terminal"), targets: [])
            == PasswordField(label: "Terminal", password: .mac))
    let overridden = PasswordTarget(kind: .app, id: "com.googlecode.iterm2", uses: .own)
    #expect(PasswordTargets.field(for: context("com.googlecode.iterm2"), targets: [overridden])
            == PasswordField(label: "iTerm2", password: .mac))
  }

  @Test func otherAppsOnlyWhenAdded() {
    #expect(PasswordTargets.field(for: context("com.example.unknown"), targets: [slack, zoom]) == nil)
    #expect(PasswordTargets.field(for: context(nil), targets: [slack]) == nil)
    #expect(PasswordTargets.field(for: context("com.tinyspeck.slackmacgap", name: "Slack"), targets: [slack, zoom])
            == PasswordField(label: "Slack", password: .own(account: "app:com.tinyspeck.slackmacgap")))
    #expect(PasswordTargets.field(for: context("us.zoom.xos", name: "zoom.us"), targets: [slack, zoom])
            == PasswordField(label: "zoom.us", password: .mac))
  }

  @Test func browsersMatchTheExactSiteOnly() {
    #expect(PasswordTargets.field(for: context("com.apple.Safari", host: "github.com"), targets: [github])
            == PasswordField(label: "github.com", password: .own(account: "site:github.com")))
    #expect(PasswordTargets.field(for: context("com.google.Chrome", host: "GitHub.com"), targets: [github])?.label == "github.com")
    #expect(PasswordTargets.field(for: context("com.apple.Safari", host: "github.com.evil.io"), targets: [github]) == nil)
    #expect(PasswordTargets.field(for: context("com.apple.Safari", host: "www.github.com"), targets: [github]) == nil)
    // Without the address bar there is nothing to match, and a browser
    // added as an app does not stand in for its sites.
    #expect(PasswordTargets.field(for: context("com.apple.Safari", host: nil), targets: [github]) == nil)
    let safari = PasswordTarget(kind: .app, id: "com.apple.Safari", uses: .mac)
    #expect(PasswordTargets.field(for: context("com.apple.Safari", host: "example.com"), targets: [safari, github]) == nil)
  }

  @Test func targetsNormaliseAndRoundTrip() throws {
    let site = PasswordTarget(kind: .site, id: " GitHub.COM ", uses: .own)
    #expect(site.id == "github.com")
    #expect(site.account == "site:github.com")
    #expect(PasswordTarget.isValidSite("accounts.google.com"))
    #expect(!PasswordTarget.isValidSite("https://github.com/login"))
    #expect(!PasswordTarget.isValidSite("github"))
    #expect(!PasswordTarget.isValidSite("git hub.com"))
    let list = [slack, zoom, github]
    #expect(try PasswordTarget.decode(PasswordTarget.encode(list)) == list)
    #expect(PasswordTargets.isBuiltIn("com.apple.Terminal"))
    #expect(!PasswordTargets.isBuiltIn("com.tinyspeck.slackmacgap"))
  }
}

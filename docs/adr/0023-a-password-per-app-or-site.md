# ADR-0023: A Password per App or Site, Chosen by What Is Asking

## Status

Accepted. Amends [ADR-0022](0022-password-mode.md), whose password mode typed the Mac password into any field that turned on secure input.

## Context

Password mode types the Mac password wherever a password field has focus. The owner wants it to type the right password for what is asking: the Mac password at the lock screen, in system prompts and in terminals, where sudo asks, and an app's or website's own password in that app or on that site.

Third-party apps cannot read Apple Passwords or Safari's saved passwords, which live in the data-protection keychain under Apple's access groups. MacTouch therefore keeps its own copies, in mactouchd's login keychain like the Mac password.

A typed password goes wherever focus is, so the choice of password must rest on something a page cannot fake. A window title can say anything. The process holding secure input, and for a browser the URL of the web area that holds the focused field, come from the system.

## Decision

mactouchd keeps a list of targets, each an app by bundle ID or a site by host name, each using either the Mac password or one of its own. The list is not secret and lives in mactouchd's defaults; an own password lives in the keychain under the account `app:<bundle-id>` or `site:<host>`.

When a password field has focus, the field gets:

1. the Mac password at the lock screen, or when the holder of secure input is built in: the login window, SecurityAgent and the other system prompts, and the common terminals (Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty, Warp). Built-ins cannot be overridden;
2. in a browser, the target whose host equals the host of the page, read through Accessibility from the web area around the focused element. The match is exact, so `www.github.com` and `github.com.evil.io` do not get `github.com`'s password. Without Accessibility the browser gets nothing;
3. in any other app, the target for its bundle ID;
4. otherwise nothing, and the sensor is not armed.

The decision is `PasswordTargets.field(for:targets:)` in MacTouchKit, pure and tested; the rest of password mode is unchanged.

The Settings window gets a Passwords pane listing the built-ins and the user's targets, with Add App… (an app picked from Applications), Add Website…, Change… and remove. The CLI has `mactouch password list|add|remove`.

## Consequences

An app's password field is left alone until the app is added, where ADR-0022 typed the Mac password into it. The lock screen, system prompts and terminals behave as before.

Copies go stale: a password changed on a site must be changed here too. Own passwords cannot be checked the way the Mac password is, so a typo is found at the field.

Reading a page's address needs mactouchd to be allowed in Accessibility, which macOS asks for once, the first time a site is added. Chromium and Electron build the tree it reads only when asked, which mactouchd does.

Matching on bundle ID trusts that the app holding secure input is the app the user meant. An app the user adds can still show a field for something else; adding an app means trusting it with that password.

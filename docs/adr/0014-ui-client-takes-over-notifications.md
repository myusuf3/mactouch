# ADR-0014: A Socket Client Says Hello to Take Over Request Notifications

## Status

Accepted

## Context

ADR-0003 left fingerprint notifications with the daemon: an `osascript` popup carrying the requester's reason, with no button, because only a bundled app can use `UserNotifications`. The menu bar app (APP.md) is that bundle. It will show a real notification with a Cancel action for every request, and dismiss it when the request ends.

Two things stand in the way. The daemon tells nobody that a request started; a client watching `events` sees the ring change colour and nothing else. And if the app posts its own notification while the daemon keeps posting the popup, every sudo shows two.

Until now no client has told the daemon anything about itself. The CLI, the PAM module and `events` streams are indistinguishable on the socket, and ADR-0003 wants to keep it that way: the app has no special access.

## Decision

**The daemon announces requests on the event stream.** Around every `identify` it emits `evt request state=pending kind=plain|nonce reason=<text>` and then `evt request state=done kind=...`. `kind` mirrors the ring colour, blue for a plain request and white for one carrying a nonce, so a client can word its notification the same way. `reason` is the last field and runs to the end of the line, as the protocol already promised for every line type; the parser now honours that for `ok` and `evt` lines too, not only `err`.

**A client that shows requests says so.** `hello ui=1` on a connection registers it as a UI client, answered with `ok hello proto=1`. While at least one UI client is connected the daemon skips the `osascript` popup for `identify`. The registration lives exactly as long as the connection: when the socket closes, the daemon forgets it, so an app that crashes hands the popup back without doing anything. The app sends `hello ui=1` on the same connection it subscribes to `events` on.

**Hello grants nothing else.** It changes who displays the request, not who may cancel it or what any command does. The daemon holds a set of connection ids and nothing about the peer; there is no authentication, because the socket is already 0600 to the user and any process that can connect could run `identify` itself.

## Consequences

The app's notification step (APP.md step 5) is now a client feature with no further daemon change: subscribe, hello, post on `pending`, dismiss on `done`, send `cancel` from the button.

`mactouch events` shows requests as they happen, which is useful on its own for seeing what asked for a finger and when.

`pair` keeps its popup regardless of hello. It is an install-time command run from a terminal that already prints the same instruction, and the app has no pairing screen planned.

The daemon decides whether to post when the request starts. A UI client that connects during a request does not suppress a popup already shown, and one that disconnects mid-request leaves no popup at all for that request. Both windows are seconds long and the ring still shows the request.

This is the first verb where a client describes itself. The precedent is deliberately narrow: one flag, one effect, forgotten on disconnect. Anything that needs the daemon to trust a client is a different decision.

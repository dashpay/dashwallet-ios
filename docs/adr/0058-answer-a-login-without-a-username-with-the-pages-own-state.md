# 0058 — Answer a login without a username with the page's own state, and open nothing

- **Status:** Proposed
- **Date:** 2026-11-02 (shipped in #1278, merged 2026-11-16; recorded 2026-11-17)
- **Deciders:** romchornyi (ADR author)

## Context

An app connection needs the identity's username (the app shows it, and the sheet names it). A
request can arrive by link or scan on a wallet without one. Before, it was parsed, its app's
contract read, and then refused with an error, or reached a sheet that could not be approved.

## Decision drivers

- Read nothing from the network for a request the wallet will not answer.
- Tell the user the one thing to do: create a username.
- Never open a return the user did not see a sheet for (ADR-0056).

## Considered options

1. **Refuse with an error** after parsing the request.
2. **The page's own state**: `ConnectionsViewModel.receive` reads the username before the request;
   without one, anything but a `dash-st:` request goes to `answerWithoutUsername`, which says
   nothing on a page that already shows the no-username state ("Sign in to apps without passwords",
   Create username), and shows "Create a username to connect apps, then ask the app for a new
   code." only where the page may show connections. A wallet whose username is not read yet
   (`usernameUnknown`) takes the same branch and always shows a different note: "The wallet is
   still reading your username. Try again in a moment." No approve sheet, no return, and nothing
   is read for the request itself.

## Decision outcome

**Chosen:** the page's own state. The request is dropped before it is parsed, and the user sees
the action that unblocks it. Reading the username first can start a background DPNS name sync
(`refreshUsername`), which is about the identity, not the request.

## Consequences

**Positive**
- No read of the request's app or contract for a request that cannot succeed. The create-username
  page says it by itself; a page that may show connections shows the note as an alert titled
  "Error".
- The app has to ask again after the username exists, so no stale request is kept.

**Negative**
- The app gets no callback saying why; it must time out or ask again.

**Neutral**
- A token purchase (`dash-st:`) keeps its own refusal ("Create a username to buy tokens in apps").

## Links

- Code: `ConnectionsViewModel.receive`, `answerWithoutUsername`,
  `ConnectionsScreen.showsNoUsernameState`
- Related ADR: [ADR-0056](0056-know-no-app-and-ask-before-returning-to-one.md)
- Promoted from the DashConnect feature ADR 0020 on 2026-11-17, after the decision shipped.

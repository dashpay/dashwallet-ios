# 0056 — Know no app: show every app as unknown and ask before returning to it

- **Status:** Proposed
- **Date:** 2026-11-02 (shipped in #1278, merged 2026-11-16; recorded 2026-11-17)
- **Deciders:** romchornyi (ADR author)

## Context

An App Connect request names its app by a contract id and a label the app chose, and a link
request may carry a callback (`cb`) the wallet opens when the request ends. The earlier approve
sheet had a brand map: a short list of known apps (Yappr) with a name and a website, shown as
trusted, and every callback was opened straight after Approve or Deny. Nothing in a request proves
which website it came from, the brand map named one testnet app, and an opened callback takes the
user to whatever host the request named.

## Decision drivers

- The sheet must not claim more about an app than the wallet can check.
- A return must never take the user somewhere they did not choose.
- No list for someone to keep up to date as apps appear.

## Considered options

1. **Brand map with verified apps**: keep a curated list of app names and websites, open their
   callbacks without asking, caution the rest.
2. **Know no app, ask before returning**: every app is unknown, the sheet says "This wallet does not
   know this app." (naming the return host when there is one), and after Approve or Deny on a link
   request with a callback the sheet asks "Return to <host>?" before opening it.
3. **Never return**: drop callbacks; the user switches back by hand.

## Decision outcome

**Chosen:** know no app, ask before returning. The wallet shows the App ID, and as the app's name
the contract owner's username when it can be read, else the label the request carries (which the
wallet cannot check). A return happens only when the user taps it, so a request cannot send the
user to a host they did not see.

## Consequences

**Positive**
- No curated list to maintain; no app is shown as more trusted than another.
- A malicious callback host is shown before it is opened.

**Negative**
- Every connection, also to well-known apps, shows the caution.
- One more tap to get back to the app after a link request.

**Neutral**
- Only a request that arrived as a link can return (`pendingRequestArrivedByLink`): a scanned code asks nothing, even when it carries a `cb`.
- A request answered without its sheet being seen (no username, ADR-0058) asks nothing either.

## Links

- Code: `ConnectionsViewModel.openCallback`, `pendingReturn`, `unknownAppText`
- Related ADR: [ADR-0058](0058-answer-a-login-without-a-username-with-the-pages-own-state.md)
- Promoted from the DashConnect feature ADR 0018 on 2026-11-17, after the decision shipped.

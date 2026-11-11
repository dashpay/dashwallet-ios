# 0031 — Turn off unattributed DashPay profile keys with any disconnect

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author), the product owner (no profile key left on that no connection accounts for)

## Context

[ADR-0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md) lets an
App Connect v2 request ask for a key bound to the DashPay `profile` document type, a contract the
app does not own. That bound names no app: every app can be given such a key. The wallet links the
key to its app only through its own grant record. When the record is gone (a reinstall, a restore,
a key another device of the wallet granted), the key is still live on the identity and can update
the user's DashPay profile, but no disconnect of a particular app can claim it.

The first version of #1263 left such keys on and showed them as a separate "Shared profile access"
row with Revoke and Keep. Keep wrote exemptions that later disconnects honoured.

## Decision drivers

- A disconnect should not leave behind a key that can write the user's profile.
- The wallet cannot tell which app holds an unattributed profile key, so asking per app is not
  possible.
- The product owner's decision: no DashPay profile key stays on that no connection accounts for.
- A disconnect never reports keys as off when it cannot tell which keys there are (repository
  guardrail 3).

## Considered options

1. **Turn them off with any disconnect that ends on the identity.** The disconnect's own
   confirmation and PIN cover them, and the alert says how many went.
2. **A separate row with Revoke and Keep**, as the first version of #1263 had. The user decides,
   and Keep's exemptions survive later disconnects.
3. **Leave them on** and only report them, as the Android wallet does.

## Decision outcome

**Chosen:** option 1, because a key that can write the user's profile and that no connection
accounts for is access nobody can see or end otherwise.

- A disconnect of an app that this identity holds keys or a grant of, and that ends on this
  identity (the app is not held, or left unchecked, on another identity), also disables the live,
  unexpired DashPay profile keys of the active identity that no confirmed grant record names.
- When that set cannot be told from the store (a record it cannot read, a stored key no record
  names whose bound it cannot read, a stored profile key the fetched view lacks), none of them is
  touched, the app's own keys still go, and the alert says the profile keys could not be checked.
- A live key in the fetched view whose bound the store cannot read stops the whole disconnect,
  as before this decision: it may be the app's own.
- The profile keys are disabled before the app's own keys, so a disconnect that fails part way
  leaves an app key live and its retry reaches the profile keys left.
- Keep, its stored exemptions and the separate row are removed; the data source deletes the
  exemptions an earlier build wrote, once.

## Consequences

**Positive**
- No profile key is left on that no connection accounts for once any app on the identity is
  disconnected.
- No second question: the disconnect the user confirmed is the whole decision.

**Negative**
- A profile key another app, or another device of the same wallet, still uses is turned off too;
  that app has to ask again.
- It differs from the Android wallet, which only reports such keys.
- A v2 approval whose outcome was unknown when it failed has no record, so its profile key is
  turned off like any other (`TODO(app-connect-v2-pending-record)`).
- Only the active identity is covered; a disconnect that does not end on the identity leaves the
  profile keys on.

**Neutral**
- A key of another app or wallet with a bound this build cannot read keeps the profile keys on
  until it expires or the build can read it.
- Letting the user keep such keys can come back in a later release as a new decision.

## Links

- Related ADR: [0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)
- PR: #1263; the #1210 review thread it answers: r4369061768

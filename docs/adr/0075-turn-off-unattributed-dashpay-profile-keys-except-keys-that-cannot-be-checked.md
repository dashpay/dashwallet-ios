# 0075 — Turn off unattributed DashPay profile keys with any disconnect, except keys that cannot be checked

- **Status:** Proposed
- **Date:** 2026-11-23
- **Deciders:** romchornyi (ADR author); the product owner's decision from ADR-0031 (no profile key left on that no connection accounts for) is carried over. The exceptions below record what the code does; they are not part of that decision

## Context

[ADR-0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md) lets an
App Connect v2 request ask for a key bound to the DashPay `profile` document type, a contract the
app does not own. That bound names no app: every app can be given such a key. The wallet links the
key to its app only through its own record (now the approval's intent). When the record is gone (a
reinstall, a restore, a key another device of the wallet granted), the key is still live on the
identity and can update the user's DashPay profile, but no disconnect of a particular app can claim
it.

[ADR-0031](0031-turn-off-unattributed-dashpay-profile-keys-with-any-disconnect.md) made this decision.
Its Positive consequence promised that no such key is left on once any app is disconnected, while
its own decision leaves a key whose bound the store cannot read on, and that key may be a profile
key. This ADR restates the decision with that exception and with the key shape the decision is
applied to; nothing in the code changes. The review of #1447 found it, and the review of #1494
found the shape and the cases where the disconnect ends in an error.

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

1. **Turn them off with any disconnect on the active identity.** The disconnect's own
   confirmation and PIN cover them, and the alert says how many went.
2. **A separate row with Revoke and Keep**, as the first version of #1263 had. The user decides,
   and Keep's exemptions survive later disconnects.
3. **Leave them on** and only report them, as the Android wallet does.

## Decision outcome

**Chosen:** option 1, because a key that can write the user's profile and that no connection
accounts for is access nobody can see or end otherwise.

- A disconnect of an app on the active identity also disables the live DashPay profile keys of
  that identity that no recorded intent names, in the shape App Connect registers
  (`AppConnect.isAppConnectAuthKey`: HASH160 authentication at HIGH or CRITICAL, with an expiry).
  A profile-bound key of another shape is not one this wallet's App Connect gives
  ([ADR-0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)):
  it is left on and not reported.
- The disconnect plans its writes from the read after the PIN. A profile key that lands after
  that read (another device approving during the disconnect) is not in the plan and stays on.
  When the read after the writes sees it, the result counts it as still live and the alert says
  not every key was turned off. The next disconnect on the identity plans it.
- An open intent of the app on another identity of the wallet does not hold the profile keys
  back. After the writes, the result counts the keys still live and the fences missing, from the
  read after the writes or, when that read fails, from what the submission reported. With neither
  left, the disconnect ends with `grantOnAnotherIdentity` instead of its result; with either left,
  it returns its result, which asks for a retry.
- When the store holds an intent this build cannot read and that names the active identity, or
  whose identity cannot be read, or when the stored value is not a list of intents, the whole
  disconnect stops before any write, the app's own keys included, and the user is asked to update
  the wallet (`intentsUnreadable`).
- A live key in App Connect's shape that no recorded intent names and whose bound the store cannot
  read does not stop the disconnect: it is left on, and the result counts it as a key that could
  not be checked ([ADR-0032](0032-pass-owners-read-from-platform-into-the-pure-projection.md)).
  The wallet cannot tell whether it is a profile key, so it is not turned off as one. A key that a
  recorded intent of the app names is disabled with the app's keys, whatever its bound.
- The profile keys are disabled before the app's own keys, so when the app has keys of its own, a
  disconnect that fails part way leaves an app key live and its retry reaches the profile keys
  left.
- Keep, its stored exemptions and the separate row are removed; the data source deletes the
  exemptions an earlier build wrote, once.

## Consequences

**Positive**
- Once any app on the active identity is disconnected, no profile key in App Connect's shape is
  left on that no connection accounts for, with two exceptions. A key whose bound the wallet
  cannot read yet is left on and counted as not checked. A key that landed after the disconnect's
  read is left on until the next disconnect on the identity, and is counted as still live when the
  read after the writes sees it. When the disconnect returns its result, the
  alert says some keys were left on; when it ends with `grantOnAnotherIdentity`, the user sees
  that error instead and not the count.
- No second question: the disconnect the user confirmed is the whole decision.

**Negative**
- A profile key another app, or another device of the same wallet, still uses is turned off too;
  that app has to ask again.
- It differs from the Android wallet, which only reports such keys.
- A profile key another wallet gave in another shape (for example without an expiry) is not
  covered: it is left on and not reported.
- Only the active identity is covered; profile keys on another identity of the wallet stay on
  until a disconnect runs while that identity is active.

**Neutral**
- An approval records its intent before it sends the update, so a profile key whose approval
  ended with an unknown outcome is named by that intent and is not one of these keys.
- A key in App Connect's shape that no intent names, of another app or wallet, with a bound this
  build cannot read is left on and counted as not checked; the profile keys still go.
- Letting the user keep such keys can come back in a later release as a new decision.

## Links

- Supersedes [ADR-0031](0031-turn-off-unattributed-dashpay-profile-keys-with-any-disconnect.md).
- Related ADR: [0009](0009-answer-app-connect-request-v2-with-wallet-derived-keys-under-wallet-limits.md)
- PR: #1263; the #1210 review thread it answers: r4369061768

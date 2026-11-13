# 0009 — Answer App Connect request v2 with wallet-derived keys under wallet limits

- **Status:** Proposed
- **Date:** 2026-11-06
- **Deciders:** romchornyi (ADR author), PastaPastaPasta (author of the change)

## Context

[ADR-0006](0006-choose-the-app-connect-login-by-the-protocol-version-read-at-runtime.md) gives a protocol-14 network the one-QR login of App Connect request v1: one session key, bound to one contract, with a budget and an expiry the wallet chooses. That is enough for an app that only writes its own documents. An app such as Yappr also needs a key for a group of its contracts (token claims need a CRITICAL group key), a key for a document type on another contract (the DashPay `profile`), and an encryption key for its messages. A v1 request cannot ask for any of these.

App Connect request v2 (`dash-key:` with `v=2`, decoded since #1204) lets the app name up to four auth bindings and two encryption bindings, each with the limits it proposes, plus a connection id and an identity hint. Its wallet rules are written in Yappr's `docs/APP_CONNECT_PROFILE.md` and are being folded into the App Connect DIP (dashpay/dips#181, open). The DIP defines v2 for testnet and devnets only.

The question is how far the wallet trusts the request: which keys it registers, with which limits, and who builds the identity update.

## Decision drivers

- The app never gets a key it could use beyond what the user approved on one sheet, and never an identity key or the recovery phrase.
- The wallet, not the app, derives every key and builds and signs the identity update.
- A request the wallet cannot check against Platform (owners, the identity hint) is refused, not guessed (repository guardrail 3).
- One approval is one identity update, and a repeat of the same request registers nothing new.
- The rules follow the profile so that the same request gets the same answer from every wallet.

## Considered options

1. **Answer v2 with keys the wallet derives, under limits the wallet enforces.** The wallet checks the request against the profile's rules, clamps what the app proposes to its own caps, derives one key per binding, and registers them in one update it signs itself.
2. **Answer only v1 and leave group, foreign-type and encryption keys out.** Simple and already shipped, but an app that needs a token claim, a profile write or messages cannot sign in at all.
3. **Let the app send the identity update for the wallet to sign (the two-scan `dash-st:` shape).** The app could ask for anything; the wallet would have to read back and judge an update it did not build, for every key shape the app can name.

## Decision outcome

**Chosen:** option 1, because it gives the app the keys it names while the wallet alone decides their shape and their limits.

- **Freshness.** A request more than 10 minutes old, or dated in the future, is refused.
- **Owners.** Every binding must be on a contract (or contract group) owned by the owner of the app's contract; the one exception is the DashPay `profile` document type. A Platform system contract is never the app nor a binding target. An encryption binding must name the app's contract, and that contract must accept bounded keys of the purpose. The owners and the identity hint are read from Platform with proofs before the sheet is shown.
- **Levels and limits.** CRITICAL only on a group key, HIGH on every other auth key, MEDIUM on encryption keys. A proposed budget is capped at 5 DASH and a lifetime at 365 days; a binding without an expiry gets 90 days. No limit the app asked for is dropped, and none it did not ask for is added.
- **Keys.** Each auth key is derived from the app's ephemeral key and the binding's index, so keys are distinct per binding and stable across retries of one request. The encryption key is the DIP-13 application encryption key for the app's contract, chosen by the DIP "Encryption Keys" rules. The wallet derives rotation `0'` at the path with the `rotation'` level, then each next rotation while the previous one is on the identity, and stops at the first that is not; on testnet and devnet only, it also derives the key at the earlier path without that level. A live current key is sent when it is one of these keys and left out otherwise (rule 1); a disabled current key leaves the slot out and registers nothing (rule 2); with no key for the binding, rotation `0'` at the new path is registered (rule 3). A login never rotates a key.
- **One update.** The new keys are added, and the keys of this wallet's earlier grant with the same connection id are disabled, in one identity update the wallet signs.
- **The answer.** The keys are sealed to the app's ephemeral key and published on the App Connect contract; the callback named in the request opens only after the user has answered the sheet.
- **Networks.** A v2 request for mainnet is refused by the parser.

## Consequences

**Positive**
- Apps that need a group key, a profile key or an encryption key sign in with one scan, on the same sheet and the same contract as v1.
- The wallet never signs an update it did not build, and every auth key has an expiry.
- A repeat of a request, or a renewal on the same connection, does not pile up live keys.

**Negative**
- The rules come from a profile whose DIP is still open (dashpay/dips#181). When it settles, the parts it changes (requests the DIP allows but this wallet does not grant, the binding counts) change with it.
- A binding that proposes no budget gets a key with no budget, and the sheet says so.
- The wallet keeps no map of which hosts belong to which app; the sheet shows the callback's host and the user judges it.
- Two devices signing in to the same app within seconds can delete each other's response before the app reads it, because each publish deletes the identity's earlier responses for the app.
- A renewal is a new login on the same connection id; raising the limits of an existing key is not done.

**Neutral**
- The caps (5 DASH, 365 days, 90 days) are the profile's and can be lowered by a later decision without changing the shape of this one.

## Links

- Feature summary: [docs/features/app-connect/README.md](../features/app-connect/README.md)
- Related ADR: [0006 — Choose the App Connect login by the protocol version read at runtime](0006-choose-the-app-connect-login-by-the-protocol-version-read-at-runtime.md)
- Request v2 decoder: #1204. Profile: Yappr `docs/APP_CONNECT_PROFILE.md`. DIP: dashpay/dips#181.

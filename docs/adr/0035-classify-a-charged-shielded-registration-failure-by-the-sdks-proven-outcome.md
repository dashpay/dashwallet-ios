# 0035 — Classify a charged Shielded registration failure by the SDK's proven outcome

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** romchornyi (ADR author and author of the change)

## Context

A private registration pays for the identity from Shielded with one Type-20 state transition. When the network rejects it, the wallet must tell a charged failure apart from every other failure before it may say that money came back. In a charged failure the exit left the shared pool and its remainder went to the wallet's Platform Payment balance. An unknown outcome must never read as money returned.

In a block, Type 20 is rejected in two ways:
- **Free.** Minimum pool notes, anchor, nullifiers, pool balance, or the identity already existing: nothing is spent.
- **Paid.** A key-state check fails (a public-key hash already registered, a contract bound, an expired key): the spend is final and the rest is credited to the fallback address.

Both reach the client as the same consensus error on the result-wait stream. That stream comes from one DAPI node, with no proof behind it. Platform v5.1-dev (#5810) therefore stopped trusting it: every wait failure without a created identity is `ShieldedBroadcastUnconfirmed`, which leaves the wallet no charged signal at all.

dashpay/platform#5853 adds one. The wallet SDK reads two things with proofs, at the node the create went to:
- whether the transition's nullifiers are spent;
- whether its identity exists.

All spent, with the identity absent at or above the spending height, returns `PlatformWalletError.shieldedIdentityCreateInputsConsumed`. The outcome means the create can never execute and created no identity. It makes no claim about the fallback address, because the same notes spent by another transition (another device holding the keys) read the same.

Those reads can also fail while the create call runs (a lost connection after the create was sent). The call then returns unconfirmed, and the SDK reads the outcome later, during a sync, at the same node. It records a proven outcome on the create's activity row as the `InputsConsumed` status (`PersistentShieldedActivity.status` 4). It never writes `Failed` for that outcome, because `Failed` also marks a create that never left the wallet or whose notes were released.

## Decision drivers

- No raw technical error on screen, and never a "money came back" for an unknown outcome.
- The classification rests on proven state, never on a node's word or on a balance change alone.
- One owner for the rule: the SDK proves, the app maps a type.

## Considered options

1. **Classify in the app from the verdict text.** The first version of this decision: `shieldedBroadcastFailed` whose text starts with the result-wait prefix → charged. Rejected in review: a free in-block rejection carries the same text, and from #5810 that text no longer arrives.
2. **Type the consensus verdict in the SDK.** A charged variant chosen by the type of the consensus error. Rejected: it still trusts an unauthenticated verdict, the opposite of #5810.
3. **Classify by the SDK's proven outcome.** `shieldedIdentityCreateInputsConsumed` → charged; `ShieldedIdentityCreateUnconfirmedError` or `shieldedBroadcastUnconfirmed` → unknown outcome; anything else → not classified.

## Decision outcome

**Chosen:** the app treats a Shielded registration failure as charged only when the SDK proves its inputs spent and its identity not created (option 3). A create the call left unconfirmed is kept as an unresolved attempt (wallet and network scope, its identity id and the record it would have). The explanation turns it into the charged record once the create's activity row has the `InputsConsumed` status, after a relaunch too. The record that follows says "did not go through" and "checking where the money went". It states an amount only once the fallback address is seen to rise ([ADR-0036](0036-measure-returned-funds-as-the-fallback-address-increase.md)), so the one case the proof cannot rule out (another device spent the notes) leaves the checking message, never a wrong amount.

## Consequences

**Positive**
- No text matching; a free rejection or an unproven verdict never writes a record.
- The SDK settles the spent notes and the activity row the same way, so the wallet does not re-drive a create that can never execute.

**Negative**
- The app needs a platform pin with #5853. Until it merges, the pin is that PR's head.
- A charged failure is recognised only after the proven reads succeed at the create's node. If that node is gone, the registration stays on "still confirming".
- A create proven during a sync is explained on the next Platform address sync or the next check of the row, not at the moment the SDK writes the row.

**Neutral**
- If the notes were spent elsewhere, the row stays on the checking message until the next registration starts or one succeeds.
- A create's `Confirmed` row is not read as success: a scan confirms the row from its outputs before the outcome is read. An unresolved attempt whose identity was created stays, explaining nothing, until the next registration starts or one succeeds.

## Links

- Feature summary: [docs/features/shielded-registration-failure/README.md](../features/shielded-registration-failure/README.md)
- Related ADR: [0036 — Measure returned funds as the fallback address increase](0036-measure-returned-funds-as-the-fallback-address-increase.md)
- Issue: #1265. Platform: dashpay/platform#5810, dashpay/platform#5853.

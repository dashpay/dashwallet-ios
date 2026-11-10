# 0035 — Classify a charged Shielded registration failure by the verdict text

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** romchornyi (ADR author and author of the change)

## Context

A private registration pays for the identity from Shielded with one Type-20 state transition. When the network rejects it, the wallet must tell a charged failure (the exit left the shared pool and its remainder went to the wallet's Platform Payment balance) apart from every other failure before it may say that money came back. An unknown outcome must never read as money returned.

At the pinned platform (`1721ca7a8b`) the only Type-20 rejections that spend the exit are those that run in a block; they reach the wallet on the result-wait stream with a consensus cause. `rs-platform-wallet` then drops the typed cause and returns `ShieldedBroadcastFailed(e.to_string())`, the same variant it uses for a rejection before a block, where nothing is spent. In Swift both are `PlatformWalletError.shieldedBroadcastFailed(String)`, with no consensus code. The result-wait form keeps the SDK's `StateTransitionBroadcastError` display text, `"state transition broadcast error: <consensus message>"`. An unknown outcome is a separate type, `ShieldedIdentityCreateUnconfirmedError`.

## Decision drivers

- No raw technical error on screen, and never a "money came back" for an unknown outcome.
- The classification comes from the network's decision, never from a balance change alone.
- #1267 needs this fix to ship; it should stay an app-only change on the current SDK pin.
- No typed signal exists at the pinned SDK.

## Considered options

1. **Classify in the app from the verdict text** — one pure classifier, applied to the failure of the Type-20 call itself (after the readiness pre-flight, before the name step): `ShieldedIdentityCreateUnconfirmedError` → unknown outcome; `shieldedBroadcastFailed` whose text starts with the result-wait verdict prefix → charged; anything else → not classified.
2. **Add a typed error in the platform SDK** — a separate `rs-platform-wallet` variant for an in-block Type-20 rejection that keeps the `ConsensusError`, its own FFI result code with `consensus_code`, and a Swift case; the app classifies by type. Needs a platform PR, a new `.platform-ref` and an xcframework rebuild.

## Decision outcome

**Chosen:** the app classifies a charged Shielded registration failure from the SDK's result-wait verdict text (option 1). It needs no platform change and its failure mode is safe: a text that no longer matches falls to the plain "did not go through", never to a wrong amount, because an amount is stated only once the returned funds are seen ([ADR-0036](0036-measure-returned-funds-as-the-fallback-address-increase.md)).

## Consequences

**Positive**
- The fix ships in the app alone, on the current SDK pin.
- One function owns the rule; every place that shows the failure reads its result.

**Negative**
- It depends on the SDK's display text; an SDK change can silently turn charged failures into plain ones until the test or the classifier is updated.
- The verdict is accepted from one DAPI node without a proof (the SDK does the same today).

**Neutral**
- A unit test holds the real text at the pinned SDK; it is re-checked on every `.platform-ref` bump.
- Moving to option 2 later changes only the classifier's input.

## Links

- Feature summary: [docs/features/shielded-registration-failure/README.md](../features/shielded-registration-failure/README.md)
- Related ADR: [0036 — Measure returned funds as the fallback address increase](0036-measure-returned-funds-as-the-fallback-address-increase.md)
- Issue: #1265. Builds on #1267.

# 0044 — Top up an identity from Shielded in one step

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** Roman Chornyi (owner), with Claude, on the review of PR #1358. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Shielded → Identity ran in two steps through `IdentityCreditsTopUp.fromShielded`: an unshield to the
wallet's own Platform address, then `topUpFromAddresses`. ADR-0042 added the `movedToPlatform`
outcome for a failure between them. The review of PR #1358 showed the second step cannot pay someone
else's identity at all: rs-platform-wallet `top_up_from_addresses` reads the identity from the
wallet's identity manager and returns `IdentityNotFound` otherwise (the same on `v5.1-dev`), so every
Shielded payment to a foreign Identity ID moved the money to the holder's Platform balance and then
failed. The SDK at the pin already has the one-step Type 22 `IdentityTopUpFromShieldedPool`
(`PlatformWalletManager.shieldedIdentityTopUpFromPool`, platform#4711): notes are spent so that any
existing identity receives the amount, the flat pool fee comes from the notes, and the identity does
not have to be managed by the wallet.

## Decision drivers

- AC-12 / AC-12b: Shielded pays someone else's identity and tops up the holder's own.
- Funds safety and ADR-0040: one transition has one outcome; no half-done state to explain.
- Use the operation the SDK owns instead of composing two (dashpay/platform `packages/swift-sdk/CLAUDE.md`).

## Considered options

1. **One step with `shieldedIdentityTopUpFromPool`** — one transition, any existing identity, the
   pool fee from the notes; ADR-0040's outcomes apply unchanged.
2. **Keep the two steps and ADR-0042** — works only for the holder's own identity; Shielded → a
   foreign Identity ID would have to become unavailable.
3. **Two steps with a foreign-capable second step** — wait for the external top-up of ADR-0045 and
   keep `movedToPlatform` for a failure in between.

## Decision outcome

**Chosen:** option 1. It pays every identity the feature pays with one transition the SDK already
ships, and removes the only route whose failure leaves the money somewhere the holder did not send it.

## Consequences

**Positive**
- Shielded → someone else's Identity ID works; Shielded → own identity is one transition instead of two.
- The `movedToPlatform` outcome and its Toast ("Top-up not completed") go away; ADR-0040's three
  outcomes cover the route.
- No dependence on a Platform receive address for this route.

**Negative**
- The fee changes to the Type 22 flat pool fee (`estimateShieldedFee(kind: .identityTopUpFromPool)`);
  Max and the Confirm figure for this route are recomputed, and the note selection follows ADR-0043.
- The existing Top Up sheet's own Shielded route (`IdentityCreditsTopUp.fromShielded`) is left as it
  is; two ways to top up from Shielded stay in the app until it follows.

**Neutral**
- `shieldedSpendUnconfirmed` from the SDK maps to `inFlight` (ADR-0040).

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Review: [dashpay/dashwallet-ios#1358](https://github.com/dashpay/dashwallet-ios/pull/1358)
- Related ADR: supersedes [ADR-0042](0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md); [ADR-0040](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md); [ADR-0045](0045-add-an-external-identity-top-up-and-a-non-blocking-identity-read-to-the-sdk.md)

# 0045 — Add an external-identity top-up and a non-blocking identity read to the SDK

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** Roman Chornyi (owner), with Claude, on the review of PR #1358. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Two identity paths of the feature fail on SDK behaviour that the design checked only by signature.
(1) Platform → someone else's Identity ID calls `topUpFromAddresses`; rs-platform-wallet
`top_up_from_addresses` takes the identity from the wallet's identity manager and returns
`IdentityNotFound` for any other (pin `1721ca7a8b` and `v5.1-dev`), so the pair the policy offers
cannot pay. (2) The Address screen checks an Identity ID with `SDK.identityGet`, which is
`@MainActor` and calls the synchronous `dash_sdk_identity_fetch`, so the UI freezes for the whole
network round trip, timeouts included. Both belong to the SDK; the owner agreed to platform PRs for them.

## Decision drivers

- AC-12: Platform pays someone else's identity; AC-13 / AC-13b: the identity check keeps Address
  responsive and tells "not found" from "could not check".
- dashpay/platform `packages/swift-sdk/CLAUDE.md`: orchestration lives in rs-platform-wallet, the FFI and Swift only
  marshal; an app-side workaround would duplicate it.
- No foreign identity may be recorded as the wallet's own (the review's explicit constraint).

## Considered options

1. **New SDK operations** — rs-platform-wallet gains a top-up of an identity that is not managed by
   the wallet (it fetches the identity from Platform, tops it up from the given addresses, and
   touches no identity-manager state), exposed over the FFI and Swift; `SDK.identityGet` and the
   other blocking reads it uses become `nonisolated`, following `documentList`.
2. **Register the foreign identity in the wallet's manager before the top-up** — no SDK change,
   but the wallet would list someone else's identity as its own.
3. **Platform → foreign identity unavailable; the identity read wrapped in a detached task** — no
   platform PR, but the pair stays missing against Android parity, and a detached task still hops
   to the main actor inside `identityGet`.

## Decision outcome

**Chosen:** option 1. It makes the pair work without the wallet claiming someone else's identity,
and fixes the freeze where it comes from, with the existing `nonisolated documentList` as the pattern.

## Consequences

**Positive**
- Platform → someone else's Identity ID pays; the app's route calls one SDK operation.
- Address stays responsive while an Identity ID is checked.
- Android can bind the same operation later.

**Negative**
- Two more platform PRs and a `.platform-ref` bump; until they merge the app PR cannot use them.
- The external top-up fetches the identity on every send (one more Platform request).

**Neutral**
- The holder's own identity keeps the existing managed path.
- Together with ADR-0043 and the Identity → Shielded binding of ADR-0036, the feature's platform
  surface grows from one binding to several PRs; ADR-0036's two-surface decision holds.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Review: [dashpay/dashwallet-ios#1358](https://github.com/dashpay/dashwallet-ios/pull/1358)
- Related ADR: [ADR-0036](0036-ship-the-ios-screens-and-the-sdk-binding-as-two-surfaces.md); [ADR-0044](0044-top-up-an-identity-from-shielded-in-one-step.md); [ADR-0043](0043-bind-the-fee-where-the-sdk-can-and-mark-the-rest-as-an-estimate.md)

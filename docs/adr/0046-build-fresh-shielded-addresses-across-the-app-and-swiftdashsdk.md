# 0046 — Build fresh shielded addresses across the app and SwiftDashSDK

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** romchornyi (author)

## Context

Receive showed the default shielded address because SwiftDashSDK exported only `shieldedDefaultAddress` (diversifier index 0). The Rust wallet could derive an address at any diversifier index and test whether a recipient was one of its own (`is_own_orchard_recipient`), but neither existed in the FFI or the Swift API. dashpay/platform#5869 asked for the export; nobody was scheduled to build it. Without the SDK change the app part of the feature cannot work.

## Decision drivers

- The app release waits until the SDK change is in the pinned platform release.
- The history needs a second SDK answer: whether a shielded recipient is one of the wallet's own addresses.
- Cross-repository fixes in platform are in scope for app features.

## Considered options

1. **Two surfaces: the app and the SDK.** The feature owns the SDK exports (Rust, FFI, Swift) and the app changes; tasks, the API contract and tests cover both.
2. **One surface: the app.** The SDK export is an external dependency delivered by someone else under #5869; the design only names the expected signature.

## Decision outcome

**Chosen:** the feature builds both the SDK exports and the app changes. The exports are on the critical path and nobody else was scheduled to build them. Owning them lets one contract describe the two new signatures and lets the SDK work be planned, reviewed and tested with the feature.

## Consequences

**Positive**
- The platform work is planned, reviewed and tested as part of the feature, not waited for.
- The same exports can serve Android later; the Kotlin SDK wraps the same Rust wallet.

**Negative**
- Two repositories and two PRs. The app PR depends on dashpay/platform#5888 and on its arrival in a pinned platform commit.
- SwiftDashSDK maintainers' review is on the critical path.

**Neutral**
- If platform maintainers prefer a different signature, the app adapts before its PR merges, not after.

## Links

- Issue: [dashpay/dashwallet-ios#1372](https://github.com/dashpay/dashwallet-ios/issues/1372)
- SDK pull request: [dashpay/platform#5888](https://github.com/dashpay/platform/pull/5888) (closes [#5869](https://github.com/dashpay/platform/issues/5869))
- Feature summary: [shielded-receive-addresses](../features/shielded-receive-addresses/README.md)
- Related ADR: [0047 — Draw the random diversifier index inside the SDK](0047-draw-the-random-diversifier-index-inside-the-sdk.md)
- Related ADR: [0048 — Recognise own shielded recipients through an SDK predicate](0048-recognise-own-shielded-recipients-through-an-sdk-predicate.md)

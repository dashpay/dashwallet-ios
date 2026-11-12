# 0048 — Recognise own shielded recipients through an SDK predicate

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** romchornyi (author)

## Context

`HomeViewModel.fetchShieldedActivity` marked a shielded sent row as the owner's own funds only when it was matched to its received side by entry id, or when its recipient equalled the default shielded address. A transfer to one of the wallet's fresh addresses, sent from another device or found by a restore scan, therefore showed as external. The wallet keeps no list of issued addresses, so only the incoming viewing key can tell whether an address is its own. The Rust wallet already runs this test internally (`is_own_orchard_recipient`).

## Decision drivers

- A transfer to an own address reads as own funds whether it was sent from this device or another one, and whether it was recorded live or found by a restore scan.
- No list of issued addresses is stored.
- `PersistentShieldedActivity` (SwiftData) already holds the recipient as 43 raw bytes, so rows can be classified at read time with no schema change.

## Considered options

1. **An SDK predicate.** `isOwnShieldedAddress(walletId:account:raw43:) -> Bool?` exposes the viewing-key test; `fetchShieldedActivity` takes an own-recipient predicate instead of the default address.
2. **A flag set when the row is recorded.** Rust classifies the recipient when it records activity and stores `isSelfTransfer` on `PersistentShieldedActivity`.

## Decision outcome

**Chosen:** the history asks an SDK own-address predicate at read time. It classifies every row (old, live, other-device, restore-scan) the same way, with no schema change in SwiftData or in the Rust store and no backfill of rows written before the update.

## Consequences

**Positive**
- No migration and no backfill; existing rows are corrected on the next read.
- `fetchShieldedActivity` keeps its injectable test seam: tests pass a stub predicate.

**Negative**
- Every history fetch makes one main-actor hop that asks the predicate for each sent row not already matched by entry id. Answers are cached per recipient for that fetch, and the test is a cheap key operation, but a very long history still pays it per distinct recipient.
- A second new function in the public SwiftDashSDK API.
- An unknown answer (shielded not bound, or the SDK threw) shows the row as external until a later reload.

**Neutral**
- If the per-fetch cost ever shows up, the answers can be cached across fetches without changing the API.

## Links

- Issue: [dashpay/dashwallet-ios#1372](https://github.com/dashpay/dashwallet-ios/issues/1372)
- SDK pull request: [dashpay/platform#5888](https://github.com/dashpay/platform/pull/5888)
- Feature summary: [shielded-receive-addresses](../features/shielded-receive-addresses/README.md)
- Related ADR: [0046 — Build fresh shielded addresses across the app and SwiftDashSDK](0046-build-fresh-shielded-addresses-across-the-app-and-swiftdashsdk.md)

# 0047 — Draw the random diversifier index inside the SDK

- **Status:** Proposed
- **Date:** 2026-11-11
- **Deciders:** romchornyi (author)

## Context

A fresh shielded address uses a random 88-bit diversifier index, and no issued address or index is stored. The incoming viewing key finds notes to every diversified address, and the index can be recovered from the address itself. What remained was where the random index is drawn, which fixes the shape of the new public SwiftDashSDK API.

## Decision drivers

- A repeat must be practically impossible (at most 1 in 10¹² over 10⁶ shown addresses), which needs a full-width, cryptographically random index every time.
- No fresh address may be the default shielded address (index 0), except in the warned fallback.
- Every shown address stays payable and is found after a restore, with no state to persist or restore.
- The same API will serve Android (dashpay/dash-wallet#1677), so a rule enforced in one place covers both clients.

## Considered options

1. **The SDK draws the index.** `shieldedFreshAddress(walletId:account:) -> Data?`: Rust draws 11 bytes from the OS CSPRNG, redraws index 0, and returns the 43 raw bytes; `nil` when shielded is not bound, like `shieldedDefaultAddress`.
2. **The client passes the index.** `shieldedAddress(walletId:account:diversifierIndex:) -> Data?`: each app draws 11 bytes itself (`SecRandomCopyBytes` on iOS).

## Decision outcome

**Chosen:** the SDK draws the random index and never returns index 0. The randomness and the "never index 0" rule live in one place that every client inherits, so a client bug cannot hand out a repeated or default (linkable) address. It also matches the proposal in dashpay/platform#5869.

## Consequences

**Positive**
- Clients cannot weaken unlinkability by passing a bad index.
- Stateless: nothing to persist, migrate or restore.

**Negative**
- The returned address is not deterministic, so app unit tests stub the address source (`ShieldedReceiveAddressSource`) instead of calling the SDK, except one timing test that runs the real SDK offline.
- A caller cannot ask for a specific index; a future feature that needs one (for example labelled addresses) adds another export.

**Neutral**
- Every 11-byte Orchard diversifier yields a valid address, so the call needs no retry loop beyond the index-0 redraw.
- The derivation is a cheap key operation: 100 timed derivations in a unit test measure a p95 of about 0.5 ms, against a 500 ms budget.

## Links

- Issue: [dashpay/dashwallet-ios#1372](https://github.com/dashpay/dashwallet-ios/issues/1372)
- SDK pull request: [dashpay/platform#5888](https://github.com/dashpay/platform/pull/5888)
- Feature summary: [shielded-receive-addresses](../features/shielded-receive-addresses/README.md)
- Related ADR: [0046 — Build fresh shielded addresses across the app and SwiftDashSDK](0046-build-fresh-shielded-addresses-across-the-app-and-swiftdashsdk.md)

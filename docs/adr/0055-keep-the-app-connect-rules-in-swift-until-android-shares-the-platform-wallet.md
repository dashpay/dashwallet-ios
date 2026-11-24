# 0055 — Keep the App Connect rules in Swift until Android shares the platform wallet

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** romchornyi (ADR author)

## Context

The functional core — `project()`, the approve, disconnect, supersession and fence plans, the funding-limit split and the state-to-actions table (ADR-0019) — is pure Swift in the iOS app. ADR-0027 notes it could move to a shared implementation for both wallets later; rust-platform-wallet is the candidate home. The Android wallet (dashpay/dash-wallet#1604) talks to Platform through dashj (`org.dashj.platform`), not through rust-platform-wallet, and differs from iOS on purpose (ADR-0029, ADR-0016; no at-most-once, Not delivered or Refused model).

## Decision drivers

- No new FFI for this feature; one iOS engineer; Platform PRs run their own multi-week review cycles.
- On 2026-11-04, when this was decided, mainnet blockers were still open (the pin of dashpay/platform#5715, the fence key on a network, the product owner's sign-off on ADR-0017). Develop's pin has since moved past #5715.
- A shared core is worth it only if both wallets consume it and agree on one status semantics.

## Considered options

1. **Swift now, review after mainnet** — keep the core in Swift and pure (no clock, storage or logging inside), write its table tests as data (snapshot + intents → expected rows) that Android can use as parity vectors; revisit once mainnet runs DashConnect.
2. **Move to rust-platform-wallet now** — expose `project()`, the plans and the table through the FFI for iOS (and later Android); the option ADR-0027 keeps open, and choosing it would have waived the «no new FFI for this feature» constraint.

## Decision outcome

**Chosen:** Swift now, review after mainnet. Moving the rules today buys Android nothing — it does not use rust-platform-wallet — while every status rule change would become a Platform PR, a re-pin and a new SDK build before mainnet.

## Consequences

**Positive**
- A status rule changes in one iOS PR and one review.
- The data-shaped table tests are a portable artefact: the same fixtures can serve Android, or a Rust port, later.

**Negative**
- The protocol rules stay written twice, in Swift and in Kotlin; parity rests on the DIP and on shared fixtures, not on shared code.

**Neutral**
- Revisit when any of these holds: Android moves its identity operations to the platform wallet (`rs-unified-sdk-jni`); both wallets agree on one status semantics (closing the ADR-0029 and ADR-0016 differences); a third consumer appears; the projection has gone several weeks after mainnet without a rule change. If Android stays on dashj, the answer can stay Swift.

## Links

- Related ADR: [ADR-0027](0027-derive-app-connect-connections-from-the-identity-and-recorded-intents.md), [ADR-0019](0019-let-one-state-table-decide-what-a-connection-shows-and-offers.md)
- Promoted from the DashConnect feature ADR 0015 on 2026-11-17, after the decision shipped.

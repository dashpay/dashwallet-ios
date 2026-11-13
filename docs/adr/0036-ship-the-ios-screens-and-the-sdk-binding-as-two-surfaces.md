# 0036 — Ship the iOS screens and the SDK binding as two surfaces

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

The address send redesign is an iOS feature, but one of its pairs, Identity → someone else's
Shielded address, needs a capability SwiftDashSDK does not expose at `.platform-ref` 1721ca7a: the
Rust wallet has `shielded_shield_from_identity_to_recipient`, while the FFI and Swift layers only
shield from an identity into the wallet's own account. The feature commits to adding that
capability itself.

## Decision drivers

- Every source × destination pair is handled at release: it either sends or shows why it cannot.
- Every pair is explained correctly to the holder.
- The platform pin may move, and the feature may add code to the platform repository.

## Considered options

1. **iOS app + SDK library** — the SDK binding is a surface of this feature, with its own tasks and tests in the platform repository.
2. **iOS app only** — the binding is an external dependency tracked as a risk, built outside the feature.

## Decision outcome

**Chosen:** option 1, the feature owns two surfaces: the iOS app and the SwiftDashSDK binding for Identity → a foreign Shielded address. It keeps the feature's commitment to add the capability, and puts the binding and its tests into the feature's plan instead of leaving them to memory.

## Consequences

**Positive**
- The binding is planned, reviewed and tested as part of the feature.
- The feature's task and test plans cover both containers.

**Negative**
- Up to three repositories in one feature: the app, platform (worktree, PR, review cycle) and DashUIKit when the screens need a new component.

**Neutral**
- The pair can switch on later than the screens ship; [ADR-0041](0041-keep-identity-to-shielded-off-in-this-release.md) keeps it off in this release.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Jira: MO-1121
- Related ADR: [0041 — Keep Identity to Shielded off in this release](0041-keep-identity-to-shielded-off-in-this-release.md)

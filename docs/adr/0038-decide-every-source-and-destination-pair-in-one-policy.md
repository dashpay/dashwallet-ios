# 0038 — Decide every source and destination pair in one policy

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Whether a source can pay a destination, and why not, is asked in five places: the starting source
(AC-10), Select source (AC-05, AC-06), the pinned-source replacement (AC-14), the executor's route,
and the Confirm warnings (AC-16, AC-17); the criteria are listed in the
[feature summary](../features/external-send/README.md). Today the source list and the route are
worked out in separate places of `SendViewModel`.

## Decision drivers

- Every pair is explained correctly, and every source × destination combination is covered.
- Funds safety: a screen must never offer a pair the executor cannot pay.
- Enabling a pair later (such as Identity → Shielded, kept off by [ADR-0041](0041-keep-identity-to-shielded-off-in-this-release.md)) must be a one-row change.

## Considered options

1. **One pure pair policy** — (source, destination type, facts) → route or unavailable reason, plus the Confirm warnings; every caller reads it.
2. **Logic where it is used** — each screen and the executor decide availability themselves.

## Decision outcome

**Chosen:** option 1, one pure pair policy, with no network or state, answers every source × destination question and lists the Confirm warnings for the pair. All 16 pairs and their warnings are covered by one table-driven unit test, and no caller can drift from the others.

## Consequences

**Positive**
- One table-driven test covers the full matrix and every warning rule.
- Adding or enabling a pair is a one-row change.

**Negative**
- Discipline: no caller may keep a private switch over sources or destinations; review must catch it.

**Neutral**
- The facts the policy needs (own Current identity, script-form Platform address, SDK capability) are gathered by the ViewModels before they call it.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADRs: [0037 — Build external send as a new module over the existing spend seams](0037-build-external-send-as-a-new-module-over-the-existing-spend-seams.md), [0041 — Keep Identity to Shielded off in this release](0041-keep-identity-to-shielded-off-in-this-release.md)

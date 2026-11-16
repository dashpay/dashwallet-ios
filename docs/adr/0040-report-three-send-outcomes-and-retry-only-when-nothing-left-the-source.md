# 0040 — Report three send outcomes and retry only when nothing left the source

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

AC-19 in the [feature summary](../features/external-send/README.md) allows Retry only when the money
is still in the source. The SDK and `WalletSendService` have an unknown state: a broadcast accepted
whose result was not confirmed, after which the caller must not retry (`WalletSendService.swift`;
`shieldedSpendUnconfirmed` in the Swift SDK). Core → Platform, Shielded or an Identity ID also has
a second step after the Core payment leaves; by default the existing asset-lock recovery finishes
it, and the app shows it as in progress. [ADR-0042](0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md)
later adds a fourth outcome for Shielded → Identity.

## Decision drivers

- Funds safety: no double payment.
- AC-19, and the default for a failure after the money left: recovery finishes it, shown as in progress.
- The SDK's no-retry contract for unconfirmed spends.

## Considered options

1. **Three outcomes** — `sent`, `inFlight` (unknown or partly done) and `notSent(reason)`; Retry only on `notSent`, doubt resolves to `inFlight`.
2. **Retry on any failure after a balance check** — Retry blocked only if the source balance already dropped.

## Decision outcome

**Chosen:** option 1, the executor reports one of three outcomes and only `notSent` offers Retry; any doubt is reported as `inFlight`. Balances update with a delay after SPV or Platform sync, so a balance check could miss a payment that already left; the three outcomes follow the SDK's own no-retry contract.

## Consequences

**Positive**
- A send can never be paid twice through Retry.
- One contract between the executor, the result screens and the SDK.

**Negative**
- Some real failures show as "in progress" without a button until recovery or sync settles them.

**Neutral**
- The in-progress view is the existing one until a dedicated lock-progress design arrives.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADRs: [0037 — Build external send as a new module over the existing spend seams](0037-build-external-send-as-a-new-module-over-the-existing-spend-seams.md), [0042 — Report movedToPlatform when a Shielded to Identity top-up fails after the unshield](0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md) (refines this ADR)

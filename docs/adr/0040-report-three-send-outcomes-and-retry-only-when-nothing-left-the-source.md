# 0040 — Report send outcomes and retry only when nothing left the source

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

AC-19 in the [feature summary](../features/external-send/README.md) allows Retry only when the money
is still in the source. The SDK and `WalletSendService` have an unknown state: a broadcast accepted
whose result was not confirmed, after which the caller must not retry (`WalletSendService.swift`;
`shieldedSpendUnconfirmed` in the Swift SDK). Core → Shielded or an Identity ID also has
a second step after the Core payment leaves; by default the existing asset-lock recovery finishes
it, and the app shows it as in progress. [ADR-0042](0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md)
proposed a fourth outcome for Shielded → Identity;
[ADR-0044](0044-top-up-an-identity-from-shielded-in-one-step.md) superseded it with a one-step
top-up that these outcomes cover.

A Core → Shielded or Identity send whose asset lock is recorded and broadcast,
while the Platform step failed or never ran, was also reported as in progress, but nothing resumes
such a lock without the holder: only Rebroadcast in the transaction details does
([dashwallet-ios#1422](https://github.com/dashpay/dashwallet-ios/issues/1422)).

## Decision drivers

- Funds safety: no double payment.
- AC-19, and the default for a failure after the money left: recovery finishes it, shown as in progress.
- The SDK's no-retry contract for unconfirmed spends.

## Considered options

1. **Three outcomes** — `sent`, `inFlight` (unknown or partly done) and `notSent(reason)`; Retry only on `notSent`, doubt resolves to `inFlight`.
2. **Retry on any failure after a balance check** — Retry blocked only if the source balance already dropped.

## Decision outcome

**Chosen:** option 1, extended by the revision below to four outcomes: the executor reports `sent`, `notSent`, `inFlight` or `lockHeld`, and only `notSent` offers Retry. A doubt about a submitted payment is reported as `inFlight`; a recorded asset lock whose Platform step did not finish is `lockHeld`, which offers Finish instead. Balances update with a delay after SPV or Platform sync, so a balance check could miss a payment that already left; the four outcomes follow the SDK's own no-retry contract.

**Revised 2026-11-15** ([dashwallet-ios#1422](https://github.com/dashpay/dashwallet-ios/issues/1422)):
a fourth outcome, `lockHeld(lock)`, for a send whose asset lock is recorded while its Platform step
did not finish. Its sheet says the Dash is held for this transfer and offers Finish, which resumes
that same lock (the Rebroadcast resume, behind authentication) and never builds a second payment;
Close leaves it for the transaction details. `inFlight` keeps only "submitted, outcome unknown".

## Consequences

**Positive**
- A send can never be paid twice through Retry.
- One contract between the executor, the result screens and the SDK.

**Negative**
- Some real failures show as "in progress" without a button until recovery or sync settles them.
- Core → an Identity ID still reports a held lock as in progress: the SDK call does not return the lock's outpoint yet (dashwallet-ios#1422).

**Neutral**
- The in-progress view is the existing one until a dedicated lock-progress design arrives.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADRs: [0066 — Build external send as a new module over the existing spend seams](0066-build-external-send-as-a-new-module-over-the-existing-spend-seams.md), [0042 — Report movedToPlatform when a Shielded to Identity top-up fails after the unshield](0042-report-moved-to-platform-when-a-shielded-to-identity-top-up-fails-after-the-unshield.md) (superseded by ADR-0044)

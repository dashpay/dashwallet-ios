# 0039 — Estimate the fee on Send and recompute it on Confirm

- **Status:** Superseded by [ADR-0043](0043-bind-the-fee-where-the-sdk-can-and-mark-the-rest-as-an-estimate.md)
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Max and the "balance minus the fee" check on the Send screen need a fee before Confirm, while the
agreed flow works the fee out when Confirm opens and blocks Confirm if it fails (AC-01b in the
[feature summary](../features/external-send/README.md)). Fees differ per pair: Core depends on
inputs and size, Platform and Identity on a credit reserve, Shielded on the notes spent. An estimate
can go stale before the send.

## Decision drivers

- Funds safety: a send never takes more than the balance minus the fee (AC-08).
- Fee and total are shown on Confirm within 3 s for every source.
- AC-01b: a failed estimate blocks Confirm with a retry, for every source.

## Considered options

1. **Estimate on Send, recompute on Confirm** — the Send estimate drives Max and the balance check; Confirm recomputes for the exact amount and that fee is binding.
2. **One estimate on Send, shown on Confirm** — computed once on Send, displayed unchanged on Confirm.

## Decision outcome

**Chosen:** option 1, the fee is estimated on Send and recomputed for Confirm, and the Confirm figure is the one sent. Because the existing seams authenticate before they build and sign (`WalletSendService.swift`), Continue runs the spend authentication and prepares the send; Confirm shows the prepared fee and its tap only broadcasts. If it no longer fits the balance, Confirm says the balance is not enough and returns to Send, where Max is recomputed; this keeps the funds-safety goal even when the estimate went stale.

## Consequences

**Positive**
- No send can exceed the balance because of a stale estimate.
- Matches the agreed flow and the time limit for showing the fee on Confirm.

**Negative**
- Two computations per send; a rare "fine on Send, not enough on Confirm" path to design and test.

**Neutral**
- For Core the Confirm computation is the existing prepare step, which authenticates, builds and signs but never broadcasts; Cancel on Confirm discards the prepared transaction.
- Authentication moves from after the Confirm tap to Continue.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADR: [0038 — Decide every source and destination pair in one policy](0038-decide-every-source-and-destination-pair-in-one-policy.md)

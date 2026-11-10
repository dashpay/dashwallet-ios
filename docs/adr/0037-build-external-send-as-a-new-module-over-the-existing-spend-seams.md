# 0037 — Build external send as a new module over the existing spend seams

- **Status:** Proposed
- **Date:** 2026-11-09
- **Deciders:** Roman Chornyi (owner), with Claude during the design pass. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).

## Context

Today's Send is `SendViewModel` (1,917 lines, 8 routes) with `SendScreen` (1,727 lines), a UIKit
`EnterAddressViewController`, and cross-rail legs in `ShieldedTransferCoordinator` (1,979 lines).
The redesign adds Identity as a source and Identity ID as a destination, up to 15 executable
routes, and splits the flow into Address, Send, Select source, Confirm and Sending.

## Decision drivers

- `CLAUDE.md` guardrail 4: one file, one responsibility; no coordinator that accumulates unrelated duties.
- `CLAUDE.md` guardrail 1: reuse shared primitives by promoting them, never copy-then-adapt.
- Every spend goes through the existing spend seams.
- New UI is SwiftUI with a ViewModel; a UIKit screen is migrated when it is reworked.

## Considered options

1. **New ExternalSend module** — one ViewModel per screen plus one executor over the existing seams; the old Send files are retired.
2. **Extend `SendViewModel`** — add the new source, destination and routes to the existing types and restyle `SendScreen`.
3. **One transfer engine shared with InternalTransfer** — extract routes, fee, Max and the runner from both flows into one engine.

## Decision outcome

**Chosen:** option 1, a new ExternalSend module with a ViewModel per screen and one executor that calls the existing seams. Over option 2 it keeps each piece small and testable instead of growing a 1,917-line ViewModel past 3,000 lines; over option 3 it leaves the working InternalTransfer flow untouched, keeping the feature at size M.

## Consequences

**Positive**
- Each screen's ViewModel and the executor are unit-testable on their own.
- The old UIKit Address screen and the oversized ViewModel leave the codebase.

**Negative**
- Larger diff; behaviour the old `SendViewModel` carries (Core drain Max, existing Confirm banners, payment-request handling) has to be moved deliberately, not lost.
- Some logic stays similar between ExternalSend and InternalTransfer until a later consolidation.

**Neutral**
- Private helpers in the old Send and InternalTransfer files are promoted to `internal` where ExternalSend needs them.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Android counterpart: [dashpay/dash-wallet#1680](https://github.com/dashpay/dash-wallet/pull/1680)
- Related ADRs: [0038 — Decide every source and destination pair in one policy](0038-decide-every-source-and-destination-pair-in-one-policy.md), [0040 — Report three send outcomes and retry only when nothing left the source](0040-report-three-send-outcomes-and-retry-only-when-nothing-left-the-source.md)

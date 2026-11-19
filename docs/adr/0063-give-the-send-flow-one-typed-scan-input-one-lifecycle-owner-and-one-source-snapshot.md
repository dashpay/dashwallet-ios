# 0063 — Give the send flow one typed scan input, one lifecycle owner and one source snapshot

- **Status:** Proposed
- **Date:** 2026-11-18
- **Deciders:** Roman Chornyi (owner), with Claude, after the round-7 architecture assessment of the external-send PR stack. Becomes Accepted only on a non-author Reviewer's approval of the PR that carries it (ADR-0001 rule 3).
- **Refines:** [ADR-0054](0054-build-external-send-as-a-new-module-over-the-existing-spend-seams.md) (module shape), [ADR-0062](0062-decide-every-source-and-destination-pair-in-one-policy.md) (the policy's inputs)

## Context

Seven review rounds on the screens layer ([#1409](https://github.com/dashpay/dashwallet-ios/pull/1409))
stayed flat at about ten findings each, and about a dozen of them were caused by the previous round's
own fixes. The reviewer named three seams, and the code confirms them:

- **A scan is parsed three times.** `DWQRScanModel` builds a typed `DWPaymentInput`. `ExternalSendLauncher`
  reduces it to `rawString` plus flags and rebuilds `requestCleared` by parsing again. Then
  `ExternalSendHostController.present` and `ExternalSendFlow.handleScanned` each call `scannedDestination`
  on the same text.
- **Two objects own the flow's lifetime.** The host has a static weak `opening` guard that is cleared only
  when a Task returns, and it decides on its own whether to leave, dismiss, or keep Address on screen. The flow
  has `openTask`, `refetchTask`, `preparing` and `isHandlingScan`, and `finish` closes Address for every
  result. `LivePaymentRequestFetcher.fetch` does not observe cancellation.
- **SendAmount has no single set of facts about the source.** About fifteen independent `@Published` flags
  plus three generation counters repair timing races, and `state` is derived from them. Because of this, a
  balance that could not be read is "not known" in one path (`startingSource`) and "not enough" in
  another (`isAffordable`).

Every boundary bug fixed so far moved to a sibling path. The money paths are not at risk:
`ExternalSendExecutor.prepareRouted` checks again before any money moves. The bugs are liveness and UX
traps: a screen stuck in Checking, a guard that is never released, a wrong "not enough".

## Decision drivers

- The flow never leaves the holder on a screen they cannot act on or leave.
- ViewModels own screen state, and the domain layer is pure and unit-tested (ADR-0054).
- One owner for each decision (ADR-0062). The same rule now applies to scan reading, lifecycle and source facts.
- Review convergence: a seam with one owner can be tested once. A seam with several owners needs one test per path.

## Considered options

1. **Keep patching each finding where it is reported.** No restructuring, but each fix has so far created
   the next round's finding (about 12 regressions in 7 rounds).
2. **Redesign the three boundaries inside #1409, before merge.** This means:
   - a typed `ScanInput` built once from `DWPaymentInput` or a link;
   - `ExternalSendFlow` as the only lifecycle owner, with a session token and explicit terminal versus
     recoverable finishes, and fetches that can be cancelled;
   - an operation-scoped `SourceFacts` snapshot (balance known, unknown or loading; funding check pending,
     ok, refused or unknown; fee; Max plan) from which `SendAmountViewModel.state` is derived.
3. **Merge the stack as it is and redesign in a follow-up PR
   ([#1450](https://github.com/dashpay/dashwallet-ios/issues/1450)).** This keeps the PRs as they are, but
   the same code is reviewed twice and #1409 does not get past review without it.

## Decision outcome

**Chosen:** option 2, the screens layer gets one typed scan input, one lifecycle owner and one source snapshot before #1409 merges.
- Each of the three seams gets one owner, so the bug classes behind the last rounds can no longer be expressed
  in the code.
- Option 3 does not avoid the work, because #1409 is not merge-ready while the seams are open.
- Option 1 has already shown it does not converge.

The redesign is limited to the screens layer. The executor's missing plan (it needs
[dashpay/platform#5607](https://github.com/dashpay/platform/issues/5607)), the SDK delivery result
([dashpay/platform#5928](https://github.com/dashpay/platform/issues/5928)) and the move of Core work off the
main actor ([#1449](https://github.com/dashpay/dashwallet-ios/issues/1449)) stay out of scope.

## Consequences

**Positive**
- Scan input:
  - the scanner hands over one typed value;
  - `scannedDestination` is called in one place;
  - `requestCleared` is no longer rebuilt from text.
- Lifecycle:
  - one owner, so the opening guard is always released;
  - a recoverable finish (`requestFailed`) cannot close Address;
  - closing the flow cancels every task it started, the fetch included.
- Source facts:
  - an unreadable balance is "unknown" everywhere, never "not enough" and never 0;
  - Continue waits for a pending funding check because the snapshot says it is pending, not because a flag
    happens to be set.
- The generation counters go away; one cancellable task per operation replaces them.

**Negative**
- About six files and 800–1,200 changed lines, including test rewrites (`ExternalSendFlowTests`,
  `SendAmountViewModelTests`).
- #1409 gets a full re-review, and its diff is already too large for inline review threads.
- Architectural rework normally goes into a follow-up PR; that practice is meant for PRs that are already
  merge-ready, and #1409 is not.

**Neutral**
- The screens, the domain layer and the executor keep their public contracts. #1406 and #1407 do not change.
- Issue #1450 is closed by this work instead of being picked up after merge.

## Links

- Feature summary: [external-send](../features/external-send/README.md)
- Review: [dashpay/dashwallet-ios#1409](https://github.com/dashpay/dashwallet-ios/pull/1409), [dashpay/dashwallet-ios#1450](https://github.com/dashpay/dashwallet-ios/issues/1450)
- Related ADRs: refines [ADR-0054](0054-build-external-send-as-a-new-module-over-the-existing-spend-seams.md) and [ADR-0062](0062-decide-every-source-and-destination-pair-in-one-policy.md)

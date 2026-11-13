# 0035 — Run every vote through a pure vote-attempt state machine

- **Status:** Proposed
- **Date:** 2026-11-04
- **Deciders:** romchornyi, with Claude during the design pass

## Context

A vote passes gates in a fixed order: contest still open → voting set up (else "Add your voting keys") → a ticked masternode has a vote left (else "No votes left") → "One vote left" when it is the last vote → the lock-is-final confirmation for a block → send. Only the first thing that stops a vote is shown, and after the key flow the vote continues without a second tap (AC-12, AC-16b). The same chain starts from a list pill, from Request details, for abstain (which skips the lock-is-final confirmation) and for Quick voting (many names). Today `VoteFlow.swift` routes only between the key flow and the cast sheet, through `@State` and `onDismiss` in a view modifier.

## Decision drivers

- Vote safety: the gate order and the per-masternode vote limit decided in one place (SAD §1 QG-1; AC-15, AC-16b, AC-17).
- CLAUDE.md guardrail 1: no copy-then-adapt — Quick voting must not get its own copy of the chain.
- SwiftUI shows one sheet or dialog at a time, so the next step has to wait until the previous one is dismissed.

## Considered options

1. **A pure state machine plus one coordinator** — `VoteAttempt` maps (contest, choice, ticked masternodes with their history, now) to the next step; one `@MainActor` `VoteAttemptCoordinator` per attempt presents that step's dialog through one presentation value and restarts the gates after the key flow.
2. **Extend the `VoteFlow` view modifier** — add `@State` for each new dialog to the modifier, and limit checks to the screens' view models.

## Decision outcome

**Chosen:** Option 1. The gate order becomes data a table-driven unit test can cover, every entry point shares it, and the coordinator owns the one-dialog-at-a-time sequencing that `onDismiss` chains do today.

## Consequences

**Positive**
- The gate order, abstain's missing confirmation and the per-masternode counting are tested without UI.
- List and Request details cannot drift apart; adding a gate is one change (and one in Quick voting's plan, see Deviation).

**Negative**
- New types and a rewrite of `VoteFlow.swift`; stage 4 carries most of it.
- The coordinator has to wait for each dialog to be dismissed before presenting the next, which is easy to get wrong without UI tests.

**Neutral**
- `CastVoteSheet`'s confirmation is replaced by the coordinator's steps; its per-masternode result view lives on as the result sheet (AC-06b).

**Deviation (2026-11-10, review-2026-11-10i finding 1)**
- Quick voting does not run one `VoteAttempt` per name. `QuickVotePlan` plans every name on screen at once with its own gate chain — voting ended (closed or past its end), voting end known, history known, blocked by any wallet masternode, the first request, votes left — because the run asks "Add your voting keys" and "One vote left" once for all names, not per name. The plan checks what the gates check, in their order, and `QuickVotePlanTests` covers each skip; a new gate must be added to both.

## Links

- Feature summary: [docs/features/username-voting/README.md](../features/username-voting/README.md)
- Related ADR: [0014 — Split voting state into a shared store and per-screen view models](0014-split-voting-state-into-a-shared-store-and-per-screen-view-models.md)

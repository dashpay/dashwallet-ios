# 0014 — Split voting state into a shared store and per-screen view models

- **Status:** Proposed
- **Date:** 2026-11-04
- **Deciders:** romchornyi, with Claude during the design pass

## Context

Today one `@MainActor` `VotingViewModel` (826 lines) serves the list, the contest screen and the key flow: contests, votable and ticked masternodes, vote history, filters, casting, toast. The redesign adds Request details, Quick voting, the vote-limit and lock-is-final dialogs and the result sheet, and every one of them must see the same data — a vote from Request details has to fill the pill on the list. We had to decide where that state lives.

## Decision drivers

- Vote safety: one source for my vote and the vote limit, so no screen decides on stale counts (SAD §1 QG-1; CONTEXT invariant "No masternode of this wallet ever exceeds the vote limit").
- Testability: today `VoteHistoryDAOImpl.shared` is hard-wired into the view model, and there are no tests for `VotingViewModel` or `MasternodeVoteCaster`.
- SwiftUI-first with `@MainActor` `ObservableObject` view models (CLAUDE.md, SAD §2).

## Considered options

1. **Keep one `VotingViewModel`, extract pure planners** — the view model stays the single source of truth for every screen; new rules go into pure value types in their own files.
2. **A shared store plus one view model per screen** — a `@MainActor` store owns contests, masternodes, history, in-flight votes and the outcome; list, Request details, voting keys and Quick voting each get a small view model over it; rules live in pure value types.

## Decision outcome

**Chosen:** Option 2. Each screen's view model stays small and testable on its own, and the store is the one place that owns my vote and the vote limit; the owner preferred the cleaner split now over growing the existing view model further.

## Consequences

**Positive**
- One owner for the data every screen shares; screen view models hold only presentation state.
- The caster keeps writing each landed vote to the vote history as it lands (so an interrupted run loses nothing) and re-checks the votes left before each cast; the store owns the in-memory view of my vote and every decision on the vote limit.
- The store takes its dependencies (contest service, registry, caster, vote history, prefs) by injection, so it and the planners can be unit-tested.

**Negative**
- Brings forward part of the clean-code rework spec §3 lists as a non-goal; stage PRs grow, and the list and filter code already written for stages 1–2 moves onto the store.
- More types to wire and review; screens must not cache store data in their own state.

**Neutral**
- The later clean-code rework (spec §3) starts from this split instead of from one view model.

## Links

- Feature summary: [docs/features/username-voting/README.md](../features/username-voting/README.md)
- Related ADR: [0013 — Treat DashUIKit and SwiftDashSDK as library surfaces of this feature](0013-treat-dashuikit-and-swiftdashsdk-as-library-surfaces.md)

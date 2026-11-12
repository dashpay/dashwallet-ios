# 0013 — Treat DashUIKit and SwiftDashSDK as library surfaces of this feature

- **Status:** Proposed
- **Date:** 2026-11-04
- **Deciders:** romchornyi, with Claude during the design pass

## Context

The redesign needs work in three repositories: the voting screens in dashwallet-ios, new shared components in DashUIKit (stage 0: VotePill, FilterBar; follow-ups #52, #55) and the request date in the platform SDK (stage 5a: `DPNSContender.createdAt`, platform#5718). The SDD pipeline reads `target_surfaces` to decide which contract `api` writes, which task layers `tasks` plans and which test tiers `plan-tests` adds. We had to decide whether the libraries are dependencies the feature only consumes, or surfaces it owns.

## Decision drivers

- The owner changes all three repositories through PRs, so a later stage may add to a library instead of working around it in the app (decision during design, 2026-11-04).
- Every stage leaves the app shippable, and DashUIKit's public API changes by additions only, because the app tracks DashUIKit `master` (spec §6, SAD §1 QG-3).
- US-13 / AC-22 is a library story (the SDK read), and stage 5b depends on its public API.

## Considered options

1. **Only `mobile-app`** — the libraries are external dependencies; their changes live in their own PRs outside this pipeline, and AC-22 is traced to platform#5718.
2. **`mobile-app` + `library-sdk`** — the libraries' feature-specific public API is part of this feature; already-merged or approved library work is recorded as done.

## Decision outcome

**Chosen:** Option 2, `target_surfaces: [mobile-app, library-sdk]`. The owner can and may need to change DashUIKit or the SDK in later stages, and the pipeline should plan and trace that work instead of treating it as out of band.

## Consequences

**Positive**
- `api` documents the public API the feature adds to the libraries (`contracts/public-api.md`), so stage 5b builds against a written contract.
- `tasks` can plan a DashUIKit or platform PR when a stage needs one, and `review` traces AC-22 through it.

**Negative**
- Downstream stages must skip stage 0 and stage 5a work that is already merged or approved, or they duplicate it.
- Work spans three repositories with separate reviews and release cycles; a library change that is not additive breaks develop at once (DashUIKit `master`).

**Neutral**
- The C4 Context (SAD §3) still shows DashUIKit and SwiftDashSDK as separate systems: they are separate repositories; the C4 Container view (SAD §5) draws the parts this feature owns.

## Links

- Feature summary: [docs/features/username-voting/README.md](../features/username-voting/README.md)
- Related ADR: [0014 — Split voting state into a shared store and per-screen view models](0014-split-voting-state-into-a-shared-store-and-per-screen-view-models.md)

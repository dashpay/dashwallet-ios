# 0066 — Declare the app and the zero-loss check as the feature's surfaces

- **Status:** Accepted
- **Date:** 2026-11-18
- **Deciders:** Roman Chornyi (owner), with Claude during the design walk

## Context

The move changes no screen: every flow in ux-flows.md is a verification path through existing screens. What it changes is the main app's code, build and bundle resources, and it adds a local zero-loss check that a Developer runs before merge and that the owner re-runs at the next three releases (spec §7). The pipeline needs to know which runnable things the feature owns, because later stages pick their artifacts by it (an e2e-through-UI test tier for an app, a command contract for a CLI).

## Decision drivers

- Wording preservation must be proved before merge and re-proved at three releases (spec §6, §7) — the check outlives the pull request and needs a stable, documented output.
- AC-09 and AC-10 fix what the check reports (file and line, the current and Baseline key, per-locale counts) — a contract a reader and a test can hold the check to.
- The workspace QA rule requires Maestro flows for the visible part (AC-01, AC-02, AC-12, AC-13) — an e2e-through-UI tier on the app.

## Considered options

1. **`mobile-app` + `cli`** — the app is one surface; the zero-loss check is a second, a command-line tool with its own commands, flags, exit codes and report format.
2. **`mobile-app` only** — the check is an untyped script or test inside the app's surface, with no contract of its own.

## Decision outcome

**Chosen:** option 1, `mobile-app` + `cli`. The check is used after merge by someone other than its author (the release preparer), so its report format and exit codes are recorded as a contract (`scripts/localization/ZERO_LOSS_CHECK.md`) that AC-09/AC-10 tests can assert against; option 2 leaves that format unwritten.

The UI architecture of the `mobile-app` surface does not change: native UIKit + SwiftUI as today, no new screen; the `screens` stage has nothing to draw.

## Consequences

**Positive**
- The check's output is specified once and tested against, so its re-runs at the next three releases read the same way.
- `plan-tests` adds the e2e-through-UI tier that the Maestro flows fill.

**Negative**
- One more artifact (`scripts/localization/ZERO_LOSS_CHECK.md`) for a small tool.

**Neutral**
- `target_surfaces: [mobile-app, cli]` in the SAD frontmatter; downstream stages read it and do not re-derive it.

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)

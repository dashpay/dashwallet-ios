# 0004 — Read the Xcode version from a file through a composite action

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** romchornyi (author). Approved in #1311 by llbartekll.

## Context

Xcode 26.6 was hard-coded in four places: the `maxim-lobanov/setup-xcode` steps of the test and release workflows and both SDK cache keys. With the Rust version owned by platform ([ADR-0003](0003-take-rust-toolchain-from-platform-pin.md)), the single source in this repository holds the Xcode version only. The release builds the app from `wallet_ref` but takes its tooling from the dispatch ref, and branches cut before the source existed must still release. So the version has to live in a file versioned with the app branch, with a fallback to the tooling copy. What remains open is who reads the file and selects Xcode on the runner.

## Decision drivers

- Test and release of the same commit use that commit's version and reuse one cache entry.
- A branch without the file falls back to the release tooling's copy and needs no edit.
- A version the runner does not have fails before any step that reads release credentials and lists the installed versions.
- One toolchain bump is one change.
- Precedent: DashUIKit keeps Xcode selection in one composite action (`.github/actions/select-xcode`).

## Considered options

1. **File plus a script in `.github/scripts/`** — both workflows call a script that reads `.xcode-version` (app checkout first, tooling copy second), validates, runs `xcode-select` and outputs the version.
2. **File plus a composite action** — the same logic packaged as `.github/actions/select-xcode`. A composite action is a set of steps used as a single `uses:`.
3. **File plus the pinned `setup-xcode` action** — keep the third-party step, pinned, and feed it the version read by a small step.

## Decision outcome

**Chosen:** option 2, `.xcode-version` read and applied by the composite action `.github/actions/select-xcode`. Each workflow gets one `uses:` line, matching the sibling repository's layout, while the version still lives in a file versioned with the app branch. Like option 1, it drops the third-party `setup-xcode` step. Unlike option 3, it controls the error text for a missing version and runs early enough in the release to fail before secrets.

## Consequences

**Positive**
- One readable `uses: ./…/select-xcode` step per workflow, the same shape as DashUIKit.
- `maxim-lobanov/setup-xcode` leaves both workflows: one third-party step fewer next to the signing credentials.
- The action owns the fallback rule, the "not installed — available: …" message and the version output for the shared cache key.

**Negative**
- The release must add `.github/actions` and `.xcode-version` to the tooling sparse checkout and call `./release-tooling/.github/actions/select-xcode`; the test workflow calls `./dashwallet-ios/.github/actions/select-xcode`.
- actionlint does not read composite `action.yml`, so the workflow policy script must feed the action's `run:` blocks to shellcheck and apply the pinned-step rule to `.github/actions/**` ([ADR-0005](0005-enforce-workflow-policy-with-in-repo-script.md)).
- The action depends on the runner image's `/Applications/Xcode_<version>.app` naming.

**Neutral**
- In the release the action's logic comes from the dispatch ref while the version comes from `wallet_ref`, by design. Tooling changes are deployed by the dispatch ref, and app data comes from the app branch.
- Moving to option 1 later means unwrapping the action's steps into a script; the file format stays.

## Links

- Feature summary: [docs/features/ci-workflow-hardening/README.md](../features/ci-workflow-hardening/README.md)
- The action: [.github/actions/select-xcode/action.yml](../../.github/actions/select-xcode/action.yml)
- Related ADRs: [0003 — Take the Rust toolchain version from platform's pin](0003-take-rust-toolchain-from-platform-pin.md), [0005 — Enforce workflow policy with an in-repo script beside actionlint](0005-enforce-workflow-policy-with-in-repo-script.md)

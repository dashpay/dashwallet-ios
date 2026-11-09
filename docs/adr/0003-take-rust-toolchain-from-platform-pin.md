# 0003 — Take the Rust toolchain version from platform's pin

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** romchornyi (author). Approved in #1311 by llbartekll.

## Context

The test and the release workflow should take both build-toolchain versions (Xcode and Rust) from one source, so that a test run and a release of the same commit build with the same tools and share the SDK build cache. Both workflows ran `dtolnay/rust-toolchain@1.92.0` and put `rust-1.92` into the shared SDK cache key. The CI log of run 41710811220 (2026-11-03) shows that the SDK is not built with 1.92. The build runs inside the platform checkout, where `rust-toolchain.toml` names 1.98.1 (at the `.platform-ref` commit `e72022ab45`). rustup auto-installs that version, and its log warns that this kind of auto-install is deprecated. The workflows' Rust version was dead configuration.

## Decision drivers

- Test and release use one set of toolchain versions from a single source and keep sharing the build cache.
- A release uses the versions of the branch it builds. Both workflows already read `.platform-ref` from that branch, unless the release is dispatched with an explicit `platform_ref`.
- A nonexistent SDK-toolchain version fails before any step that reads release credentials.
- CI run 41710811220 (2026-11-03): the SDK is already built with platform's 1.98.1 from `rust-toolchain.toml`, while the workflows' 1.92 install goes unused. Building with the compiler platform itself is tested with is the status quo.

## Considered options

1. **Platform's pin** — the Rust version is whatever `rust-toolchain.toml` names in dashpay/platform at `.platform-ref`. The unused setup step is removed and an explicit install replaces the auto-install.
2. **This repository's source, forced** — the Rust version lives next to the Xcode version here and overrides platform's file through `RUSTUP_TOOLCHAIN`.
3. **This repository's source plus a match check** — the Rust version lives here as well, and CI fails when it differs from platform's file at `.platform-ref`.

## Decision outcome

**Chosen:** option 1, the Rust version is the one platform's `rust-toolchain.toml` names at `.platform-ref`. Both workflows already read platform's file through `.platform-ref`, so it is a single source today. Choosing it removes a version that nothing uses rather than adding a second copy. Option 2 would build the SDK with a compiler platform does not test with (today a downgrade from 1.98.1 to 1.92). Option 3 adds a second manual edit to every platform bump that raises Rust, and the copy that rotted here is exactly that kind of duplicate.

## Consequences

**Positive**
- The SDK is built with the same compiler platform tests with, and a `.platform-ref` bump carries its Rust version along.
- One third-party step (`dtolnay/rust-toolchain`) leaves both workflows, so there is one step fewer to pin and one fewer next to the signing credentials.
- An explicit `rustup toolchain install` in the platform checkout replaces rustup's deprecated auto-install before it stops working.
- The cache key carries the real Rust version, read from the toml, in one formula shared by both workflows.

**Negative**
- The Rust version cannot be changed in this repository on its own; it moves only with `.platform-ref`.
- A `.platform-ref` bump that changes Rust is a toolchain change that needs a manual release run before merging, but the workflow-lint check does not flag it.
- The single source in this repository holds the Xcode version only, not both toolchains.
- A release with an explicit `platform_ref` builds with that commit's Rust, and a branch without `.platform-ref` takes Rust from platform's default branch rather than from the release tooling.

**Neutral**
- Reading the version needs the platform checkout, which both workflows already do before the toolchain steps; in the release this all moves before the first secret is read.
- Switching to option 3 later is a small change: add a version line and a comparison step.

## Links

- Feature summary: [docs/features/ci-workflow-hardening/README.md](../features/ci-workflow-hardening/README.md)
- Related ADR: [0004 — Read the Xcode version from a file through a composite action](0004-read-xcode-version-file-via-composite-action.md)

# 0070 — Keep the Catalog in step with Xcode's own string sync in every build

- **Status:** Proposed
- **Date:** 2026-11-18
- **Deciders:** Roman Chornyi (owner), with Claude during the design walk

## Context

Today a third-party tool (BartyCrouch) rewrites all 43 text lists on every build of the `dashpay` and `dashwallet` targets and deletes keys it does not recognize. After the move, the Catalog must follow the code through the regular build alone (Goal 1, AC-03–AC-05), and spec §8 Q3 asks whether that holds for both a build in the Xcode app and a command-line `xcodebuild` — the way CI and coding agents build. The Xcode app syncs a String Catalog after a build; whether `xcodebuild` does is not verified. `xcrun xcstringstool sync <catalog> --stringsdata …` performs the same update from the build's `.stringsdata` (present on Xcode 27.2, 2026-11-18). CI fails any build that changes the checkout (`unit-tests.yml:344`).

## Decision drivers

- Goal 1 / AC-03: a text added in code reaches the Catalog through the regular build, with no other step writing text files.
- AC-04 and the invariant "a build can never delete a translation".
- AC-05 and spec §6 Catalog stability: 0 changed lines after a second build with no text change.
- Spec §6 Build time: ≤ the old build + 5 s.
- Developers and coding agents both build from the command line (AGENTS.md "Canonical build").

## Considered options

1. **Xcode's own sync, plus a `xcstringstool sync` build phase if the pilot shows `xcodebuild` does not sync** — the regular build is both the Xcode-app build and the command-line build.
2. **Xcode-app build only, plus a CI drift step** — command-line builds never touch the Catalog; a CI step syncs a copy and fails on a difference.

## Decision outcome

**Chosen:** option 1. It is the only option where the Xcode app, `xcodebuild` and coding agents behave the same, so the spec §8 Q3 default (both builds keep the Catalog in step) holds; and with it, CI's existing "Build must not modify the checkout" step becomes the drift guard: a pull request whose code and Catalog disagree is changed by CI's build and fails there, with no new CI code.

What the build does:
- `dashpay` (and `dashwallet`, which carries the same phase today) gets `SWIFT_EMIT_LOC_STRINGS = YES` and `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`; both "Run Script - bartycrouch" phases are removed.
- The pilot (spec §8 Q1/Q3) runs a command-line build after adding a text and checks whether the Catalog changed. If not, a "Sync String Catalog" run-script phase after compilation calls `xcrun xcstringstool sync DashWallet/Localizable.xcstrings --stringsdata <the target's .stringsdata>` — Apple's tool, the same update the Xcode app makes, written into the Catalog only.
- The pilot also checks that the sync takes Objective-C lookups into account (else they would be marked stale) and that a Catalog synced by Xcode 27.2 builds on CI's Xcode 26.6 and stays byte-identical after that build, with the same derived keys (§2); otherwise CI's drift guard would fail every pull request.

## Consequences

**Positive**
- One behaviour for every way of building; the drift KPI (spec §7) is held at 0 by CI without a dedicated check.
- No third-party tool writes text files during the build (spec §7 KPI target 0).

**Negative**
- Whether the phase exists is decided by the pilot, so `tasks` carries a conditional task.
- In the Xcode app the sync may run twice per build (the IDE's and the phase's); the result is the same, but the time counts against the +5 s budget.
- `xcstringstool sync` marks entries no code uses as stale and may remove stale entries that have no translation; an entry with translations is kept (AC-04). An untranslated English-only entry whose code was removed can disappear — the zero-loss check's Unused-entry rule covers only entries with Baseline translations.

**Neutral**
- A Developer who edits code without building and commits gets the failure in CI rather than locally.

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)
- Related ADR: [0067](0067-generate-the-catalog-from-the-baseline-lists-with-a-repository-script.md)

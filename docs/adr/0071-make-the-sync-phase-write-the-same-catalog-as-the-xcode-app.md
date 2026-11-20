# 0071 — Make the sync phase write the same Catalog as the Xcode app, and compile only the shipped locales

- **Status:** Proposed
- **Date:** 2026-11-19
- **Deciders:** Roman Chornyi (owner), with Claude during the toolchain pilot
- **Refines:** [ADR-0068](0068-keep-the-catalog-in-step-with-xcodes-own-string-sync-in-every-build.md) (what the "Sync String Catalog" phase does); ADR-0068's choice of option 1 stands.

## Context

ADR-0068 adds a phase that calls `xcstringstool sync <Catalog> --stringsdata <the target's .stringsdata>` if a command-line build does not sync. The pilot (pilot.md, Q-sync, Q-objc, Q-regions) found:

- `xcodebuild` does not sync, so the phase is needed.
- The Xcode app syncs too, after its build, and writes **different bytes** for the same code: it sorts every object's keys with `localizedStandardCompare` (the CLI sorts by code point), it also extracts `NSLocalizedString` from Swift and Objective-C and merges the comments of several places into one, and it drops new untranslated keys that occur only in `#if DEBUG` / `#Preview` code. A phase as ADR-0068 describes it and the Xcode app would rewrite each other's output, and CI's "Build must not modify the checkout" would fail after any build in the Xcode app (2681 entries, 138 599 lines differed in the pilot).
- The Catalog compiles every locale it holds into the bundle, regardless of `knownRegions`. Today's app ships `Localizable` in 22 locales; the other 21 lists are on disk but not in the project.

## Decision drivers

- AC-05 and spec §6 Catalog stability: 0 changed lines after a second build with no text change — for a build in the Xcode app and on the command line alike.
- ADR-0068's drift guard: CI's existing "Build must not modify the checkout" step.
- Spec §1 (amended 2026-11-19): the Catalog keeps 43 locales; the app keeps the 22 it ships (owner decision, «more than 50% translated»).
- Spec §6 Build time: ≤ the old build + 5 s.

## Considered options

1. **The phase reproduces the Xcode app's sync** — compiler `.stringsdata` plus a legacy extraction of the target's Swift and Objective-C sources, `xcstringstool sync`, then a re-serialization in the app's order and format.
2. **No phase; only the Xcode app syncs; a CI step compares Catalog and code ignoring order** (ADR-0068 option 2) — command-line builds and coding agents never update the Catalog.
3. **The phase as ADR-0068 states it, and the Xcode app's result is not committed** — relies on every Developer re-building on the command line before a commit.

## Decision outcome

**Chosen:** option 1 (owner decision 2026-11-19). In the pilot the emulated phase produced a file byte-identical to the Xcode app's, apart from the 19 `#if DEBUG` / `#Preview` keys, so both ways of building converge and CI's existing step stays the drift guard.

What the build does, in addition to ADR-0068's settings:
- The "Sync String Catalog" run-script phase on `dashpay` runs after compilation: it passes the target's compiler `.stringsdata` and the `.stringsdata` of `xcstringstool extract --legacy-localizable-strings` over the target's Swift sources (`<target>.SwiftFileList`, whose paths escape spaces as `\ `) and Objective-C sources to `xcstringstool sync`, then re-writes the Catalog with every object's keys in `localizedStandardCompare` order under one pinned locale, two-space indent, `" : "`, empty object as `{\n\n<indent>}`, no trailing newline.
- `XCSTRINGS_LANGUAGES_TO_COMPILE` lists the 22 shipped locales (`bg cs de el en es fr id it ja ko nl pl pt ru sk th tr uk vi zh-Hans zh-Hant-TW`), so the bundle holds the same `Localizable` locales as today; the Catalog keeps all 43.
- No new translatable literal stays only in `#if DEBUG` / `#Preview` code; such texts are written verbatim. A Baseline lookup there keeps its lookup, so the zero-loss pairing still finds its place, and its Catalog entry is marked `manual`: the Xcode app does not extract `#Preview` code and would otherwise mark the entry stale, while neither writer changes a `manual` entry (one today: `"Amount too low"` in the `TransferAmountView` preview).
- Only a Debug build syncs; the phase skips itself in every other configuration (Release, TestFlight, TestNet), which compiles the Catalog as committed. Added after the NFR measurement's Release build: a Release build does not compile `#if DEBUG` code, so its sync marked `"Amount too low"` (looked up only in a `#Preview`) stale and the Catalog depended on the configuration (owner decision 2026-11-19).

## Consequences

**Positive**
- A build in the Xcode app, `xcodebuild`, CI and coding agents all leave the same Catalog bytes; CI's existing step catches any drift.
- Objective-C entries are not marked stale by command-line builds.
- No Wallet holder sees a language appear or change.

**Negative**
- Own code in the build: the legacy extraction call and a re-serializer that must keep matching the Xcode app's format; a future Xcode that writes differently shows up as a CI diff.
- A text looked up only in `#if !DEBUG` code would be marked stale by every Debug build; none exists today.
- Only the dashpay target syncs, but the dashwallet and Today extension targets compile the Catalog too. A text looked up only by another target, or only under `#if !DASHPAY`, would be marked stale and read as Unused; such an entry is kept `manual` (the Today extension's "Setup Wallet"). A script test fails on a Today-extension or `#if !DASHPAY` lookup whose entry is not `manual`; a lookup in a dashwallet-only file is not checked. The Xcode app's own sync after a Release build is not covered by the phase's skip; one Release build in the Xcode app left the Catalog unchanged (2026-11-19).
- The Xcode app's order follows the Mac's locale; a Developer on a Mac in another language could get another order than the pinned one. Not checked; the owner accepted the risk on 2026-11-19.
- The phase costs about 5.7 s per build in the pilot (0.6 s extraction, 1.8–4.3 s sync, 0.8 s re-serialization), against a removed BartyCrouch phase; a full sync measured 5.2 s against the Baseline's 21.2 s BartyCrouch build, and the phase skips itself when no `.stringsdata` changed.

**Neutral**
- The 21 unshipped locales keep their translations in the Catalog and in the zero-loss check, as they kept them on disk.

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)
- Related ADR: [0068](0068-keep-the-catalog-in-step-with-xcodes-own-string-sync-in-every-build.md)

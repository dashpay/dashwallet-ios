# 0065 — Generate the Catalog from the Baseline lists with a repository script

- **Status:** Proposed
- **Date:** 2026-11-18
- **Deciders:** Roman Chornyi (owner), with Claude during the design walk

## Context

The main app's texts live in 43 `DashWallet/<lang>.lproj/Localizable.strings` + `Localizable.stringsdict` pairs. They must become one `DashWallet/Localizable.xcstrings` with every translation and plural variant. The move ships as one pull request whose Baseline is its merge-base with develop and is re-taken after every rebase (spec §1), so the conversion runs once per rebase, not once. The 43 locale names must stay exactly as they are, including `zh_TW` and `sl_SI`, while the project's `knownRegions` lists only 23 of them.

## Decision drivers

- Wording preservation: 100% of Baseline translations reach the Catalog (spec §6, AC-06, AC-10).
- AC-18: after a rebase, develop's new or changed texts and translations must be in the Catalog with the same wording.
- Spec §1: the Catalog keeps exactly the 43 locales under their current names; none is renamed or merged.
- Plural fidelity: every plural variant the Baseline has, and no new ones (AC-07).

## Considered options

1. **A repository script** reads the Baseline lists of all 43 locales and writes the Catalog; after every rebase it is re-run on the new merge-base and its output replaces the previous one.
2. **Xcode's "Migrate to String Catalog"** — Apple's converter, run by hand in the Xcode app; after a rebase, develop's changes are carried over by hand or the whole migration is redone.
3. **Xcode's converter once, then a script that applies develop's delta** between the old and the new merge-base after each rebase.

## Decision outcome

**Chosen:** option 1, a repository script. It is the only option where a rebase costs one re-run, with no hand-carried changes (AC-18), and where the locale names and plural variants are under the script's control instead of depending on how Xcode's converter treats `zh_TW`, `sl_SI` and the 20 locales missing from `knownRegions` (untested, brief §6 ledger).

## Consequences

**Positive**
- Rebases are mechanical: re-run the script on the new merge-base, then the zero-loss check (ADR-0067) proves the result.
- The script is testable on small fixtures (one locale, one plural entry, one format-code key).

**Negative**
- About 200 lines of own code that must write the Catalog's JSON the way Xcode expects; anything Xcode re-serializes differently shows up as a diff after the first build.
- The script carries the knowledge of the `.strings` / `.stringsdict` formats that Xcode's converter would have carried.

**Neutral**
- The committed Catalog is the script's output after one Xcode build has normalized it, so the second build leaves it unchanged (spec §6 Catalog stability; CI's `git diff --exit-code` step).
- The script and the other one-off migration tools leave the repository in the pull request's last commit (owner decision 2026-11-19); nothing after merge depends on them.

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)
- Related ADR: [0067](0067-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md)

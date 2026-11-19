# 0066 — Rewrite formatted lookups as interpolations and move their Catalog entries

- **Status:** Proposed
- **Date:** 2026-11-18
- **Deciders:** Roman Chornyi (owner), with Claude during the design walk

## Context

3681 Swift places look texts up through `NSLocalizedString` and must move to `String(localized:)` (US-05, AC-08). In English, 371 of the 2689 keys carry format codes (280 only `%@`, 91 numeric such as `%d`, `%u`, `%ld`; 26 positional such as `%1$d`; 5 fixed-precision floats), and 62 entries are counted phrases with plural variants. The Swift compiler derives the lookup key of an interpolated `String(localized:)` from the argument types. Probed on Xcode 27.2 (2026-11-18, `-emit-localized-strings`): `"\(n) words"` with an `Int` yields `%lld words`, `"\(s) and \(s)"` with `String`s yields `%@ and %@`, and a literal without interpolation (`"%d words"`, `"~%.0f%%"`) keeps its key byte for byte. The same probe showed that a literal key under `String.localizedStringWithFormat` still picks the Baseline plural forms. A changed key whose entry stays behind shows English in 42 locales with no error (brief R1).

## Decision drivers

- US-05: one current Swift call, used the way current Swift code uses it.
- Brief problem 2: a counted phrase formatted with `String(format:)` silently loses its plural rules; an interpolated `String(localized:)` applies them by itself.
- Wording preservation (spec §6): every place still resolves to its Baseline wording after formatting with the same sample arguments — a changed key is allowed only as a Moved key (spec §8 Q1 default, glossary "Moved key").

## Considered options

1. **Keep every key verbatim** — literal `String(localized: "k")`, formatting stays in `String(format:)` / `localizedStringWithFormat` around the literal; no Moved key by default.
2. **Interpolate only the 62 counted phrases** — plain and other formatted texts keep their literal keys; the counted phrases' entries become Moved keys.
3. **Interpolate wherever the text takes arguments** — every formatted lookup becomes `String(localized: "… \(x) …")`; every entry whose derived key differs becomes a Moved key.

## Decision outcome

**Chosen:** option 3, interpolation wherever the text takes arguments (owner decision 2026-11-18, against the recommended option 1). It gives one idiomatic form for all Swift lookups and removes the `String(format:)` step through which counted phrases lost their plural rules, at the price of moving entries and rewriting their format codes in every locale.

Rules that follow from it:
- A plain text (no arguments) keeps its key: `String(localized: "k", comment: "c")`.
- A formatted text becomes an interpolation. When the derived key differs from the Baseline key, the entry moves to the derived key in all 43 locales with all its translations and plural variants, and each translation's format codes are rewritten to the derived ones, keeping their positions (`%1$d` → `%1$lld`). No Unused copy of the old key remains (AC-06).
- Where an interpolation cannot reproduce the Baseline wording for the same sample arguments (for example a fixed-precision float `%.0f`, whose interpolation formats through a format style), the place keeps its literal key and its formatting call; the zero-loss check (ADR-0067) is the judge, not the rewrite.

## Consequences

**Positive**
- Every Swift lookup reads the same way; counted phrases get the plural rules from `String(localized:)` itself, so the `String(format:)` plural bug cannot recur in Swift.
- The key that the compiler derives is the key in the Catalog, so the regular build's extraction matches the code without a hand-kept list.

**Negative**
- Roughly the 91 numeric, 26 positional and 62 plural English entries (overlapping) move, and their translations in 43 locales get rewritten format codes — a large translation diff that a reviewer cannot read line by line; only the zero-loss check proves it.
- The translation service will receive these entries under new keys after the Translation sync pause; whether their translations travel with them is part of the deferred transfer decision (spec §8 Q2) and gets harder with every Moved key.
- The rewrite needs each argument's type to know the derived key, so a plain text search cannot do it; the codemod works on parsed Swift (§5).

**Neutral**
- Texts whose arguments are all `String`s keep `%@` keys, so most of the 280 `%@`-only entries do not move; positional `%1$@` keys do move.
- Objective-C lookups keep their Baseline keys; a key looked up from both Objective-C and a rewritten Swift place cannot simply move, because the Objective-C lookup would lose it. On 2026-11-18, 44 keys are looked up from both languages and none of them carries a numeric or positional code (count by `xcstringstool extract --legacy-localizable-strings`); a shared key whose derived Swift key would still differ keeps its literal key at the Swift place (SAD §11).

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)
- Related ADR: [0065](0065-generate-the-catalog-from-the-baseline-lists-with-a-repository-script.md), [0067](0067-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md)

# 0070 — Check releases through the key map instead of pairing code places

- **Status:** Proposed
- **Date:** 2026-11-19
- **Deciders:** Roman Chornyi (owner; chose the key map during `api`, 2026-11-19), recorded with Claude during `implement` (T8)
- **Amends:** [ADR-0067](0067-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md) — for release runs only; the pre-merge check keeps pairing code places.

## Context

ADR-0067 proves zero loss by pairing each code place with the key that place used at the Baseline, by file and ordinal. That works before the merge, when the only change to the code is the move. Spec §7 asks for the same check at each of the next 3 releases. By then other pull requests have added, removed and moved lookups, so a file's ordinals shift and pairing fails on files the move never touched (sad §11, OQ-API-1). The owner chose during `api` that a passing pre-merge run writes a key map (Baseline key → current keys) and that release runs check the Catalog through it.

## Decision drivers

- Spec §7: the check runs at each of the next 3 releases and must not fail on ordinary later code changes.
- AC-10, AC-15: Unused entries and Watch files are still checked at release time.
- Zero loss stays measured against the Baseline wording, not against the Catalog of the release before.

## Considered options

1. **Key map** — a passing pre-merge run writes `scripts/localization/zero_loss_key_map.json` (Baseline commit, Baseline key → current keys); `--release` checks, for each Baseline key with a Baseline translation, that every mapped current key's Catalog wording equals the Baseline wording in every locale.
2. **Pair code places again at each release** — ADR-0067 unchanged; release runs fail on every file with a new or removed lookup and are judged by hand.
3. **Compare the release Catalog with the merge-time Catalog** — checks drift, but no longer against the Baseline.

## Decision outcome

**Chosen:** option 1 (owner decision 2026-11-19). Release mode reads the key map, refuses `--baseline`, `--derived-data` and `--write-key-map`, needs no build, runs checks 1, 4, 5 and 6 of `scripts/localization/ZERO_LOSS_CHECK.md`, and in place of checks 2–3 runs the key check: a difference is a `key` finding. A deliberate wording change since the Baseline also fails as a `key` finding and is judged by hand; there is no list of accepted changes.

## Consequences

**Positive**
- Release runs do not depend on code places, so later code changes do not fail them.
- The key map is a reviewable record of every Moved key (old → new), which the deferred translation-service transfer also needs (spec §8 Q2).

**Negative**
- A text whose code place was deleted after the merge is still checked through the map until the 3 releases are over.
- Every deliberate wording change in those releases needs a hand judgement.

**Neutral**
- The key map is written only by a passing pre-merge run and committed with the move; release mode never writes it.

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)
- Related ADR: [0067](0067-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md)

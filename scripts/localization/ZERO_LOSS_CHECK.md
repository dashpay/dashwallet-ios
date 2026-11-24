# Zero-loss check

> **ADRs:** [ADR-0066](../../docs/adr/0066-declare-the-app-and-the-zero-loss-check-as-the-feature-surfaces.md), [ADR-0069](../../docs/adr/0069-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md), [ADR-0072](../../docs/adr/0072-check-releases-through-the-key-map.md) · **Feature:** [String Catalog migration](../../docs/features/string-catalogs-migration/README.md)

The zero-loss check is the feature's one `cli` surface (ADR-0066). It proves that every lookup key the main app uses still resolves to its Baseline wording in all 43 locales. The app's sources are every file under `DashWallet/` and every file the dashpay target compiles (for example the Objective-C under `DashPay/`), each side read from its own project file (`scripts/localization/dashpay_target.py`). The Today extension's lookups are not covered: the extension is not maintained. A Developer runs it before merge and after every rebase (AC-18); the person preparing each of the next 3 releases runs it again (release mode). This file fixes its command, flags, exit codes and report, so tests for AC-09 and AC-10 assert against it and every run reads the same way.

The `mobile-app` surface consumes no contract of its own (no new screen, ADR-0066). The old-call guard (`scripts/ci/check_no_old_swift_lookup.py`, AC-17) is an internal pull-request check, not part of this contract.

## Invocation

```
python3 scripts/localization/zero_loss_check.py [--baseline <rev>] --baseline-derived-data <path> [--derived-data <path>] [--write-key-map]
python3 scripts/localization/zero_loss_check.py --release
```

Runs on macOS from the repository root, with Xcode's `xcrun xcstringstool` and `swift` on `PATH`. It needs no simulator and no network: it never contacts the translation service (AC-10, AC-14) and reads the Baseline from git alone.

## Modes

| Mode | When | Pairs by | Needs a build | Writes |
|---|---|---|---|---|
| pre-merge (default) | before merge, after every rebase (AC-18) | each code place, by file and ordinal (ADR-0069) | yes — the `.stringsdata` of the newest simulator Debug `dashpay` build of this checkout (`--derived-data`) | nothing, or the key map with `--write-key-map` on a pass |
| release (`--release`) | each of the next 3 releases | each Baseline key, through the committed key map | no | nothing |

Release mode is decided by ADR-0072 (Proposed), which amends ADR-0069 for release runs.

**Why two modes.** Ordinal pairing (ADR-0069) holds only while the rewrite is one-for-one. After merge, any new lookup in a file shifts its ordinals, so a release-time run would fail on every such file. The pre-merge pass therefore records which current key replaced each Baseline key, and the release run checks the Catalog through that record.

## Flags

| Flag | Mode | Default | Meaning |
|---|---|---|---|
| `--baseline <rev>` | pre-merge | `git merge-base HEAD origin/develop` | The Baseline commit. The default re-takes the merge-base on every run, so after a rebase the check measures against the new one (AC-18). |
| `--derived-data <path>` | pre-merge | the newest simulator Debug (`Debug-iphonesimulator`) `dashpay` build under `~/Library/Developer/Xcode/DerivedData` whose `.stringsdata` sources lie under this checkout's root | Where the build's `.stringsdata` files are read from. A build of another checkout is skipped however new it is; none of this checkout → exit 2. A compiler place counts only when its file is a Swift file of the working tree, so an incremental build's data of a deleted or renamed file is ignored. Every record of a working-tree Swift file must be no older than that file (an interrupted incremental build, or a leftover folder of another architecture, fails this) → exit 2, naming the first such file. The test is by time, so it also refuses a file a branch switch or rebase rewrote without changing it, which Xcode does not rebuild: delete the DerivedData folder and build again (the rebase routine always does). |
| `--baseline-derived-data <path>` | pre-merge, required | — | The DerivedData folder of a `dashpay` build of the Baseline commit, made by `scripts/localization/build_baseline.sh`. The Baseline's Swift places are the compiler's `.stringsdata` there plus the legacy extraction of `NSLocalizedString`: a lightweight extraction cannot derive the keys of SwiftUI interpolations (owner decision 2026-11-19). Missing, empty (no `.stringsdata`) or not built from the Baseline commit in use → exit 2. Before building, the script (`prepare_baseline_folder.sh`) removes the two records of a folder that holds a finished build of the same commit, so a build that fails now leaves none; it deletes no folder and no build data, and refuses any other non-empty folder (another commit's build, a failed build, Xcode's own DerivedData) with the command that deletes it. It records two files in that folder after a successful build: `baseline-commit` (the full 40-hex commit it built) and `baseline-root` (the worktree root the build ran in). The check compares `baseline-commit` with the Baseline commit in use, also with an explicit `--baseline`; a missing record counts as a mismatch. It maps the Baseline's `.stringsdata` sources to repository files through `baseline-root`; when that file is absent it maps a source to the Swift file of the Baseline commit its path ends with. A compiler place counts only when its file is a Swift file of the Baseline commit. |
| `--write-key-map` | pre-merge | off | On a pass, write the key map (below). On a failure, write nothing. If the Catalog or the key map changed on disk after the run read them, write nothing and stop with an error (exit 2). The key map is put in place only over the bytes the run read: a save that lands while it is written stays (in place, or in a conflict file next to it that the error names) and the run stops with exit 2. |
| `--release` | release | off | Release mode. Reads the Baseline commit from the key map; refuses `--baseline`, `--baseline-derived-data`, `--derived-data` and `--write-key-map`. |
| `-h`, `--help` | both | — | Usage. Exit 0. |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Pass: every check below held. |
| `1` | Fail: at least one finding. Every finding is printed; no partial success is reported. |
| `2` | Cannot run: bad flags, not a git repository, Baseline revision not found, `xcstringstool` or `swift` missing, no `.stringsdata` or a `.stringsdata` record older than its own working-tree Swift file (ADR-0069), no `dashpay` build of this checkout in DerivedData, a missing or empty Baseline build folder, a missing or mismatching `baseline-commit` record (rebuild with `build_baseline.sh`), key map missing or unreadable in release mode, or the formatter self-test failed (below). Nothing is compared. |

## What it checks

Pre-merge mode, in order (ADR-0069):

1. **Self-test.** A counted phrase formatted under `uk` must give different text for 2 and for 5; otherwise the formatter is not applying the locale's plural rules and the run stops with exit 2.
2. **Place counts.** Each source file has as many lookup places at the Baseline as now (Swift places from `.stringsdata`, each counted only when its file is a Swift file of that side's tree; Objective-C places from `xcstringstool extract --legacy-localizable-strings`). A file that differs is a `file-places` finding.
3. **Wording.** For each of the 43 locales and each place whose Baseline key had a Baseline translation in that locale, both sides are formatted by Foundation with the same sample arguments — a distinct value per argument position; counted phrases at counts 0, 1, 2, 4, 5, 21, 101, 1000000, which reach every plural category an integer selects in the 43 locales (Slovenian `few`, Filipino `other`, the `many` of ca/es/fr/it/pt; categories only a decimal selects, such as the `other` of pl/ru/uk, cannot occur with an integer count) — and must give equal text (exact match without placeholders). A difference is a `place` finding (AC-09). A Baseline translation whose format codes take a sample argument as another type — an object code for a number, an integer code for an object or a float, read by number (`%2$@`) or by order — formats undefined text on a phone, so it cannot be compared: it is a **baseline defect**, left out of both columns and printed, not a finding. The rule judges the codes, never the key, so it is no list of accepted changes; a text with a plural variable (`%#@name@`) or under substitutions is not judged (owner decision 2026-11-19).
4. **Key set.** The Catalog's keys are the Baseline's keys, with each Moved key in place of its Baseline key (AC-06). A Baseline key with no entry and no Moved key is a `missing-key` finding, whether or not it had translations. The comparison runs both ways (owner decision 2026-11-19): the Catalog's keys must be exactly (Baseline keys − moved-from keys) ∪ moved-to keys, where a moved-from key is a Baseline key that some place now reads under a different current key. A Catalog key outside that set is an `extra-key` finding; a Catalog key that is a moved-from key (a leftover old copy of a Moved key) is an `old-copy` finding. Carve-out: a key that a current lookup place asks for is never a finding, so a text a Developer adds after the move is legitimate. Unused entries are Baseline keys that no place reads, so they are neither moved-from nor extra. An `old-copy` is reported only while a key that replaced it is in the Catalog too; when the replacement is missing, the wording findings already name the gap. Release mode has no places, so it cannot tell a text added after the move from a stray key: it reports `old-copy` from the key map but never `extra-key`. For the same reason a release-mode `old-copy` can be a legitimate text: a lookup added after the merge that uses a moved-from key again (for example an integer kept on `String(format:)` with its Baseline key, ADR-0068) brings that key back while the key map still maps it to its Moved key. The check has no way to accept it; the person preparing the release judges it by hand (see «Judging a release finding» below).
5. **Unused entries.** Every Unused entry (`extractionState: stale`) still holds each Baseline translation of its key (AC-04, AC-10). A lost one is an `unused` finding.
5b. **Unmapped entries.** Every other entry kept under its Baseline key that no wording row compares (pre-merge: no place reads it; release: not in the key map) still holds each Baseline translation of its key, whatever its `extractionState` — e.g. a `manual` key only the Today extension looks up, or an Unused entry a later lookup made live again (AC-10). A lost one is an `unmapped` finding.
6. **Watch files.** Every `WatchApp/<lang>.lproj/Interface.strings` is byte-identical to the Baseline commit (AC-15). A difference is a `watch` finding.

Release mode runs 1, 4, 5, 5b and 6 as above, and in place of 2–3: for each Baseline key in the key map that had a Baseline translation, and each locale, the current key's Catalog wording formatted with the same sample arguments must equal the Baseline wording. A difference is a `key` finding; a baseline defect is left out as in 3. A deliberate wording change since the Baseline also fails as a `key` finding. The check has no list of accepted changes.

### Judging a release finding

Every release finding is judged by hand by the person preparing the release (owner: Roman), from the printed texts and the history of the file it names (`git log <Baseline>.. -- <file>`). A deliberate change after the merge, made in its own reviewed pull request, is not a loss; anything else is:

- `key`: acceptable when a later pull request changed that wording on purpose (its English text or a translation) and the printed texts differ only by that change. A translation that is gone, or that reads as another text, is a loss.
- `old-copy`: acceptable when a current lookup asks for that key (for example an integer kept on `String(format:)` with its Baseline key, ADR-0068).
- `missing-key`, `unused`, `unmapped`: acceptable when a later pull request deleted that text on purpose — it removed the text's last lookup and deleted its entry (or that locale's translation) in the same change. An entry or translation that disappeared in any other change is a loss.
- `watch`: acceptable when every change to that `Interface.strings` since the Baseline came from a reviewed Watch translation update (the Watch texts still sync with the translation service, `.tx/config` `watch-interface-strings`) in a commit of its own, and the file keeps its encoding and its keys: only translated values changed. A changed key, encoding or line order, or a change made inside another commit, is a loss.

Every other finding is a loss to fix before the release. The pre-merge run accepts no finding: it must pass with 0 findings.

## Report

Plain text on stdout, deterministic: rows sorted by locale, findings sorted by kind, then file and line or key, then locale. Keys and texts are printed as JSON strings, so every finding stays on one line.

```
zero-loss check — mode: <pre-merge|release>
baseline: <12-hex commit> (<merge-base of HEAD and origin/develop | --baseline <rev> | key map>)
locale       places   same
<locale>     <n>      <n>
…            (one row per locale, 43 rows)
baseline defects: <n> left out        (only when n > 0)
<baseline defects, one per line>
unused entries: <n> checked, <n> with lost translations
unmapped entries: <n> checked, <n> with lost translations
watch files: <n> identical, <n> differ
<findings, one per line>
RESULT: <PASS|FAIL> (<n> findings)
```

`places` is the number of places (release mode: Baseline keys) whose Baseline key had a Baseline translation in that locale; `same` is the number of those whose current key resolves to the same wording. A pass needs `places == same` on all 43 rows (AC-10). In release mode the column header reads `keys` instead of `places`.

**Findings.**

| Kind | Mode | Line |
|---|---|---|
| `place` | pre-merge | `FAIL place <file>:<line> locale=<locale> current_key=<json> baseline_key=<json> expected=<json> actual=<json>` |
| `file-places` | pre-merge | `FAIL file-places <file> baseline=<n> current=<n>` |
| `key` | release | `FAIL key baseline_key=<json> current_key=<json> locale=<locale> expected=<json> actual=<json>` |
| `missing-key` | both | `FAIL missing-key baseline_key=<json>` |
| `extra-key` | pre-merge | `FAIL extra-key key=<json>` |
| `old-copy` | both | `FAIL old-copy key=<json>` |
| `unused` | both | `FAIL unused key=<json> locale=<locale>` |
| `unmapped` | both | `FAIL unmapped key=<json> locale=<locale>` |
| `watch` | both | `FAIL watch <file>` |

**Baseline defects** (not findings; sorted like findings):

| Mode | Line |
|---|---|
| pre-merge | `DEFECT <file>:<line> locale=<locale> baseline_key=<json> translation=<json>` |
| release | `DEFECT baseline_key=<json> locale=<locale> translation=<json>` |

`translation` is the first Baseline text of that locale that takes an argument as the wrong type.

`<file>` is relative to the repository root; `<line>` is the line of the current place. `expected` is the Baseline wording, `actual` the current one, both after formatting; when the current key has no entry, `actual` is the key itself, as on a phone. For a counted phrase, `expected` and `actual` show the first count that differs.

Exit-2 errors go to stderr as one line, `error: <reason>`, and print no report.

## Key map

`scripts/localization/zero_loss_key_map.json`, UTF-8 without BOM, committed with the move. Written only by a passing pre-merge run with `--write-key-map`; byte-identical for the same input; read only by release mode.

```json
{
  "baseline": "<40-hex commit>",
  "keys": {
    "<baseline key>": ["<current key>"]
  }
}
```

| Field | Type | Constraints |
|---|---|---|
| `baseline` | string | 40-hex commit; the merge-base the passing run measured against. |
| `keys` | object | One member per Baseline key a place used; sorted by key. |
| `keys.<baseline key>` | array of string | The current keys the places of that Baseline key ask for, sorted, at least one. The same key when it did not move; the Moved key when it did (ADR-0068). |

## Examples

Placeholder keys and wording only.

**Pass (pre-merge):**

```
$ python3 scripts/localization/zero_loss_check.py --baseline-derived-data ~/Library/Caches/dashwallet-regenerate/baseline-0123456789ab
zero-loss check — mode: pre-merge
baseline: 0123456789ab (merge-base of HEAD and origin/develop)
locale       places   same
ar           1200     1200
…
zh-Hant-TW   1200     1200
unused entries: 4 checked, 0 with lost translations
unmapped entries: 3 checked, 0 with lost translations
watch files: 43 identical, 0 differ
RESULT: PASS (0 findings)
$ echo $?
0
```

**Fail (pre-merge, AC-09):**

```
$ python3 scripts/localization/zero_loss_check.py --baseline-derived-data ~/Library/Caches/dashwallet-regenerate/baseline-0123456789ab
zero-loss check — mode: pre-merge
baseline: 0123456789ab (merge-base of HEAD and origin/develop)
locale       places   same
ar           1200     1199
…
FAIL place DashWallet/Sources/UI/Example/ExampleView.swift:42 locale=ar current_key="Sample %lld items" baseline_key="Sample %d items" expected="<ar wording> 1001" actual="Sample 1001 items"
…
RESULT: FAIL (43 findings)
$ echo $?
1
```

**Fail (release, a wording changed since the Baseline):**

```
$ python3 scripts/localization/zero_loss_check.py --release
zero-loss check — mode: release
baseline: 0123456789ab (key map)
locale       keys     same
de           1150     1149
…
FAIL key baseline_key="Sample title" current_key="Sample title" locale=de expected="Beispieltitel" actual="Neuer Beispieltitel"
RESULT: FAIL (1 findings)
```

**Cannot run:**

```
$ python3 scripts/localization/zero_loss_check.py --baseline-derived-data ~/Library/Caches/dashwallet-regenerate/baseline-0123456789ab
error: the dashpay build's .stringsdata is older than 1 working-tree file(s), first DashWallet/Sources/UI/Home/HomeView.swift; build the dashpay target first (delete <derived data> if a record of another architecture or an interrupted build is left over)
$ echo $?
2
```

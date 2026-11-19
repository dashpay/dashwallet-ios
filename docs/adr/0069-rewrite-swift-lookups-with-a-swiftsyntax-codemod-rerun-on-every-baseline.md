# 0069 — Rewrite Swift lookups with a SwiftSyntax codemod re-run on every Baseline

- **Status:** Proposed
- **Date:** 2026-11-18
- **Deciders:** Roman Chornyi (owner), with Claude during the design walk

## Context

3681 Swift places in 391 files move to `String(localized:)` in the form ADR-0066 sets: plain texts keep their literal key, texts with arguments become interpolations. 560 calls span several lines; many sit inside `String(format:)` or `String.localizedStringWithFormat` with their arguments, which must land in the interpolation in the order their format codes consume them (positional codes included). The pull request is rebased onto develop many times before merge (spec §1), and develop keeps changing the same Swift files.

## Decision drivers

- AC-08: no Swift place in the app or its unit tests keeps the old call.
- AC-09 / wording preservation: a wrong argument order or a changed key must not slip through.
- AC-18: a rebase must not turn into hand-merging thousands of rewritten lines.
- Reviewability: a reviewer cannot check 3681 hand edits, but can check a tool and its tests.

## Considered options

1. **A SwiftSyntax codemod** — a small Swift command under `scripts/localization/` that parses each file with Apple's swift-syntax, rewrites each lookup deterministically and lists what it leaves alone; re-run after every rebase.
2. **A Python codemod on tokens** — the same re-runnable approach with a hand-written parser of Swift strings, parentheses and arguments.
3. **Rewrite by coding agents, file by file** — no tool; the zero-loss check is the safety net; rebase conflicts resolved by hand.

## Decision outcome

**Chosen:** option 1, the SwiftSyntax codemod. A real Swift parser handles multi-line calls, escaped quotes, raw and multi-line strings and nested calls that a hand-written parser gets wrong (option 2), and a deterministic tool makes every rebase a re-run instead of a hand merge across the files develop touched (option 3).

How the pull request is built (each rebase repeats steps 2–5 as described in step 4):
1. Tool commits: the Catalog generator (ADR-0065), the codemod, the entry mover, the zero-loss check (ADR-0067), with their fixture tests; plus the build-setting, `.tx/config`, script and documentation changes.
2. On the merge-base: generate the Catalog, run the codemod, build the `dashpay` target.
3. The entry mover pairs places as the zero-loss check does and moves each entry whose key changed to its derived key, rewriting format codes in all 43 locales (ADR-0066).
4. Build again, so the sync normalizes the Catalog (spec §6 Catalog stability); one generated commit holds this state of steps 2–3's output; hand fixes for what the codemod listed live in their own commits after it. A rebase moves only the commits before the generated one onto develop, regenerates, then re-applies every later commit in its old order and the tool-removal commit last.
5. The zero-loss check must pass before the pull request leaves draft.

What the codemod leaves alone and lists for a hand fix: a key that is not a string literal (a variable or an expression), a fixed-precision float whose interpolation would format differently, and any call shape it does not recognize.

## Consequences

**Positive**
- Rebases cost one re-run plus re-applying the later commits in order; the 3681 rewritten places never conflict.
- The codemod's rules are tested on fixtures (a positional `%1$d`, a `%%`, a multi-line call, a counted phrase), so a reviewer reviews rules, not 3681 edits.

**Negative**
- An own Swift tool with a swift-syntax package dependency under `scripts/` (not linked into the app); its swift-syntax version must build with Xcode 26.6 and 27.2.
- A re-applied later commit can conflict where the new Baseline changed the few files it touches.

**Neutral**
- The codemod, the Catalog generator and the entry mover leave the repository in the pull request's last commit (owner decision 2026-11-19); a rebase sets that commit aside, so the tools are present while it regenerates. The zero-loss check stays (spec §7).
- Argument-order errors are caught by the zero-loss check, which uses a distinct sample value per argument position (ADR-0067).

## Links

- Feature summary: [docs/features/string-catalogs-migration/README.md](../features/string-catalogs-migration/README.md)
- Related ADR: [0065](0065-generate-the-catalog-from-the-baseline-lists-with-a-repository-script.md), [0066](0066-rewrite-formatted-lookups-as-interpolations-and-move-their-entries.md), [0067](0067-prove-zero-loss-by-pairing-each-code-place-with-its-baseline-key.md)

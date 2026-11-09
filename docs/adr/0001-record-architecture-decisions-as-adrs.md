# 0001 — Record architecture decisions as ADRs

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** romchornyi (author). Team agreement: approval of #1308 by llbartekll.

## Context

dashwallet-ios has no agreed place for decisions. Decisions are not recorded in a form that says what was decided, why, and what later replaced it. Developers re-argue settled choices, Reviewers judge changes without the reasoning, and AI agents read only the agent instructions file (`CLAUDE.md`). The team is also starting to use a feature-spec pipeline that writes feature ADRs under its own per-feature numbering. Its working drafts are not committed; a feature publishes a short summary and its ADRs. The repository is public, so every document is published the moment its branch is pushed.

## Decision drivers

- Every significant decision has one findable record with its reasoning and current status, in one place and under one numbering.
- The rule is shared: the whole team agrees to it and writes ADRs, not only the owner.
- Nothing published through the repository exposes customer data or exploitable security detail; 0 publicity-rule breaches reach the default branch.
- 100% of log ADRs are listed in the index with the correct status.
- Every primary source checked keeps one central, sequentially numbered log and states the threshold as a principle with exclusions, never as a pure category list (fact-check 2026-11-03: Nygard, MADR, Polar handbook).

## Considered options

1. **One central, sequentially numbered decision log with a rule that binds every Developer** — the rules below.
2. **ADRs kept by the owner alone, with no team rule** — less discipline asked of others, but the records cover only one person's work.
3. **ADRs only inside feature folders, under the pipeline's per-feature numbering, with no central log** — no extra step, but decisions are scattered under many numberings, and Developers who do not use the pipeline have nowhere to write.
4. **One central log as in option 1, but only feature ADRs above the significance threshold are promoted** — the log grows more slowly, but every feature PR needs a per-ADR judgement about which drafts to promote, and unpromoted drafts stay in feature folders as a second set of numbered decisions.

## Decision outcome

**Chosen:** option 1, with every feature ADR that the feature keeps promoted. It is the only option that meets the first two drivers together: one place and one numbering, shared by everyone. Over option 4 the owner chose one simple rule (promote everything) and accepted a faster-growing log; the threshold therefore governs decisions made outside the pipeline. The rules below also carry the publicity driver, which neither option 2 nor option 3 addresses.

### Rule 1 — Significance threshold

A decision needs an ADR when it is **hard to reverse, or affects more than one module or consumer**.

Examples in this wallet:

- a new dependency or SDK;
- a storage schema or migration;
- the key and security model;
- a module boundary;
- a contract with platform or rust-dashcore.

**Not needed** — a code comment or the PR description covers these:

- **N1** — a local, easily reversible choice inside one module (naming, internal structure, a private helper);
- **N2** — a temporary workaround, marked `TODO(label)` in the code;
- **N3** — a bug fix that restores the intended behaviour without changing a contract;
- **N4** — a change that follows an Accepted ADR without changing its decision.

The PR template's ADR item is answered with one of: `ADR-NNNN added`, `no significant decision`, or `not needed: <N1–N4>`.

### Rule 2 — Publicity

The repository is public. Everything that goes through it is public the moment it is pushed or posted:

- every committed file, anywhere in the tree: code and its comments, tests and fixtures, `docs/`, `CLAUDE.md`, the root documentation files, configuration;
- commit messages and branch names;
- the titles, descriptions and comments of PRs and issues, review comments and replies, and the files attached to them (screenshots, logs, crash reports).

Never put there:

- customer data, including anything taken from a support case;
- details of a vulnerability that is not fixed yet;
- secrets: keys, tokens, credentials, recovery phrases;
- step-by-step attack detail against keys, PIN or encryption.

Describing the security design at the level already public in the code is allowed. Content that the rule keeps out is left out of the repository and handled privately with the maintainers; a document, comment or PR may say only that the detail is handled privately. A support case is described by its symptom, never by the customer: no names, emails, addresses, transaction ids, wallet ids or unredacted logs and screenshots.

The author keeps such content out **before pushing**. The PR template's publicity item, checked by the Reviewer, is the last net and not the first. When a breach is found:

- in a file: it is removed and a short note says that the file was redacted and why. This redaction is allowed even in an Accepted ADR: the publicity rule wins over rule 3's "never edited". Git history still holds the removed text;
- in PR or issue text or an attachment: the comment or file is deleted, and an edited description also has the old revision deleted from its edit history, which GitHub otherwise shows to everyone.

A secret that reached any pushed branch or any PR text is treated as leaked and rotated, even if it was removed before merge.

### Rule 3 — Lifecycle, numbering and supersede

- A new ADR takes the next free log number, starts as **Proposed**, and is listed in the index (`docs/adr/README.md`) in the same PR.
- An ADR becomes **Accepted** only when a Reviewer who is not its author approves the PR that carries it. An AI agent's approval never counts. After the approval, the author sets Accepted in the ADR and in the index as the last change before merge; this status-only change needs no new approval.
- The Status line is the ADR's only status field. An ADR in `docs/adr/` has no frontmatter.
- An Accepted ADR is **never edited**. The only exceptions are its status line when it is superseded and a redaction that rule 2 requires.
- To change a decision, write a new ADR that names the old one. In the old ADR only the status line changes, to `Superseded by ADR-NNNN`.
- A number is **never reused**. If two open PRs take the same number, the author of the PR that merges second moves the ADR to the next free number when rebasing and updates every reference to the old number in that PR. A renumbering alone needs no new approval. Before merging, the author checks that the number is still free on `develop`.

### Rule 4 — Promotion of feature ADRs

Every feature ADR that the feature keeps goes to the decision log in the feature PR itself. A draft the pipeline rejected or replaced is not copied.

- it is copied to `docs/adr/` under the next free log number, without the pipeline's frontmatter, with the status Proposed, and listed in the index; from then on the copy in `docs/adr/` is the record;
- it becomes Accepted under rule 3, like any other ADR;
- the feature's public summary, `docs/features/<name>/README.md`, links it by its log number;
- the index lists log numbers only.

The status that the pipeline wrote into a draft does not count.

### Rule 5 — Shape, and who writes ADRs

- File: `docs/adr/NNNN-<decision-in-kebab-case>.md`. The title states the decision, not the problem.
- Body: the Status, Date and Deciders lines, then Context, Decision drivers, Considered options, Decision outcome, Consequences and Links. Considered options and Consequences are required. Decision outcome opens with one sentence, `**Chosen:** …`, that states the decision on its own. Feature ADRs use the same shape, so promotion is a copy, not a rewrite. Links are relative to the file (`../README.md`), so they work on GitHub and in a local checkout, and point only at what is in the repository.
- Index row: number, title, Area, Status and Superseded by. Area is one value from the fixed list under the index table; a new value is added to that list in the PR that first needs it.
- Every Developer writes ADRs for their significant decisions, whether or not they use the feature-spec pipeline. Feature summaries are optional.
- Past decisions get an ADR when they are next revisited; no retroactive backlog is required.

## Consequences

**Positive**
- Each significant decision has one record with its reasoning and its current status, findable from one index.
- Reviewers have a checklist item for asking for a missing ADR, and a written "not needed" list for accepting its absence.
- AI agents get a named source of settled decisions and a way to challenge one (supersede) instead of silently contradicting it.
- The publicity rule is written down and checked on every PR, for its files, its commits and its text.

**Negative**
- Every significant PR carries an extra document, and every PR carries two more checklist items.
- The log grows faster than a log that holds only threshold-level decisions, because every feature ADR that a feature keeps is promoted, including the small ones the pipeline produces by quota.
- Little is automated: the repository's gitleaks pre-commit hook (`.githooks/`, enabled per clone) catches secrets; index completeness, numbering and the other publicity cases rely on the Reviewer.

**Neutral**
- If the co-maintainers do not agree to a mandatory rule, this ADR is changed in its own PR before approval: the ADR checklist item becomes optional and ADRs are written by those who choose to. The publicity item stays mandatory, because the repository is public whatever the team decides.

## Links

- Feature summary: [docs/features/docs-and-adr-layout/README.md](../features/docs-and-adr-layout/README.md)
- Related ADR: [0002 — Keep the decision log in docs/adr](0002-keep-the-decision-log-in-docs-adr.md)

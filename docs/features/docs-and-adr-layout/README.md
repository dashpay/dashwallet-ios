# Docs folder layout and the decision log

**Owner:** romchornyi · Introduced in [#1308](https://github.com/dashpay/dashwallet-ios/pull/1308)

## Why

dashwallet-ios had no agreed place for its decisions. Nothing recorded what was decided, why, and
what later replaced it, so settled choices were re-argued and reviews ran without the reasoning.
The repository is public, so whatever is written under `docs/` is published from the first push.

## What changed

- **Decision log** in [`docs/adr/`](../../adr/README.md): one sequentially numbered log with an
  index. ADRs for significant decisions are required for everyone.
- **The rules** are in [ADR-0001](../../adr/0001-record-architecture-decisions-as-adrs.md): the
  significance threshold and its "not needed" cases, the publicity rule, the lifecycle
  (Proposed → Accepted → Superseded, numbers never reused) and the promotion of feature ADRs.
- **The location** of the log is [ADR-0002](../../adr/0002-keep-the-decision-log-in-docs-adr.md).
- **Docs folder guide**, [`docs/README.md`](../../README.md): what is required, what is optional,
  the layout, and the publicity rule in short. [`docs/architecture/`](../../architecture/README.md)
  is the home for living architecture docs.
- **PR template**: an ADR item and a publicity item.
- **`CLAUDE.md`**: AI agents read the Accepted ADRs, never silently contradict one, and the ADRs
  they draft stay Proposed.

## What it guarantees

- A significant decision gets an ADR in the same PR, with the next log number, status Proposed,
  its alternatives and consequences, and a row in the index.
- An ADR becomes Accepted only after a Reviewer who is not its author approves the PR.
- An Accepted ADR is never edited, except for a redaction that the publicity rule requires; a new ADR supersedes it.
- Nothing in the repository or on its PRs holds customer data, unfixed vulnerability detail, secrets or
  step-by-step attack detail against keys, PIN or encryption.

## Not in scope

- Moving the loose documentation files from the repository root into `docs/` is a follow-up PR.
- ADRs for past decisions are not written retroactively; a past decision gets one when it is next
  revisited.
- Little is enforced automatically: the gitleaks pre-commit hook (`.githooks/`, enabled per clone) catches
  secrets; the PR template and review carry the rest.

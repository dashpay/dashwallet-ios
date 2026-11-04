# docs

If this page and [ADR-0001](adr/0001-record-architecture-decisions-as-adrs.md) disagree, ADR-0001 wins.

This folder holds the written record of dashwallet-ios: decisions, architecture docs, feature
folders and review captures. The repository is public, so everything here is public from the
first push of its branch.

## Required

ADRs for significant decisions are required for everyone, whether or not you use the feature-spec
pipeline. An ADR (architecture decision record) is a short document that states one decision, why
it was made, the options considered and its consequences.

A decision is significant when it is hard to reverse, or affects more than one module or consumer.
The full rule, its examples and the "not needed" cases N1–N4 are in
[ADR-0001](adr/0001-record-architecture-decisions-as-adrs.md). The decision log and how to
add an ADR to it are in [adr/README.md](adr/README.md).

## Optional

Feature summaries are optional. A feature built with the feature-spec pipeline gets one file,
`docs/features/<name>/README.md`: what changed, why, and links to its ADRs. The pipeline's working
drafts (spec, design, tasks, reviews) are not committed. Its ADRs are copied into `docs/adr/` in the
feature PR and follow the same rules as any other ADR.

## Layout

| Path | Holds | Lifecycle |
|---|---|---|
| `docs/README.md` | this guide | edited as the layout changes |
| `docs/adr/` | the decision log: `NNNN-*.md` files and the index `README.md` | new entries; an existing Accepted ADR changes only in its status line when superseded (ADR-0001 rule 3) or by a redaction that the publicity rule requires (ADR-0001 rule 2) |
| `docs/architecture/` | architecture docs | living, edited as the code changes |
| `docs/features/<name>/README.md` | one summary per feature | written in the feature PR |
| `docs/review/` | review captures | unchanged |

## Publicity rule

The repository is public: everything here, and everything else committed, pushed or posted on its
PRs and issues, is public too. Never write, here or anywhere in the repository and its PRs:

- customer data, including anything taken from a support case;
- details of a vulnerability that is not fixed yet;
- secrets: keys, tokens, credentials, recovery phrases;
- step-by-step attack detail against keys, PIN or encryption.

Describing the security design at the level already public in the code is allowed. Leave content
the rule keeps out of the repository and handle it privately with the maintainers; a doc may say
only that the detail is handled privately. A support case is described by its symptom, never by
the customer. Keep it out before pushing: the PR template's publicity
item, checked by the Reviewer, is the last net, not the first. Full rule:
[ADR-0001, rule 2](adr/0001-record-architecture-decisions-as-adrs.md).

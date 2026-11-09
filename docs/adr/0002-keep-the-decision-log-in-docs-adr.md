# 0002 — Keep the decision log in docs/adr

- **Status:** Accepted
- **Date:** 2026-11-03
- **Deciders:** romchornyi (author)

## Context

The decision log needs a fixed path. `CLAUDE.md`, the PR template, the docs folder guide, the feature-spec pipeline's promotion step, and links from issues and PRs all refer to it. On `develop`, `docs/` holds only `docs/review/`. The rest of the docs folder layout is decided together with the log's home, because the guide explains all the sections in one place.

## Decision drivers

- One place for every ADR, named so that people, agents and links can find it.
- Links from issues and PRs are permanent, so the path should not change once ADRs are linked.
- The pipeline already writes feature ADRs to an `adr/` folder, and promotion copies them into the log (ADR-0001 rule 4).

## Considered options

1. **`docs/adr/`** — the name used by Nygard's original post and adr-tools, and the same name as the pipeline's feature-folder subfolder.
2. **`docs/decisions/`** — the folder MADR recommends since version 3; it avoids the acronym and matches the glossary term "decision log".

## Decision outcome

**Chosen:** option 1, `docs/adr/`. It matches the pipeline's own `adr/` folder that promotion copies from. Option 2's main advantage, avoiding the acronym, is covered by the docs folder guide, which explains what an ADR is.

The resulting layout of the docs folder:

| Path | Holds | Lifecycle |
|---|---|---|
| `docs/README.md` | the docs folder guide: what is required (ADRs for significant decisions, for everyone), what is optional (feature summaries), where architecture docs and reviews go, and the publicity rule in short | edited as the layout changes |
| `docs/adr/` | the decision log: `NNNN-*.md` files and the index `README.md` (`# \| Title \| Area \| Status \| Superseded by`) | new entries; an existing Accepted ADR changes only in its status line when superseded (ADR-0001 rule 3) or by a redaction that the publicity rule requires (ADR-0001 rule 2) |
| `docs/architecture/` | architecture docs | living, edited as the code changes |
| `docs/features/<name>/README.md` | one summary per feature: what changed, why, and links to its ADRs; the pipeline's working drafts are not committed | written in the feature PR |
| `docs/review/` | review captures (already exists) | unchanged |

## Consequences

**Positive**
- Promotion is a copy between two folders with the same name: `adr/` → `docs/adr/`.

**Negative**
- "adr" is jargon; a newcomer learns its meaning from `docs/README.md`, not from the path.

**Neutral**
- Renaming the folder later is a quick change inside the repository, but it breaks external links to ADRs. That is why this ADR exists.
- The loose root documentation files are not part of this layout until the follow-up PR moves them.

## Links

- Feature summary: [docs/features/docs-and-adr-layout/README.md](../features/docs-and-adr-layout/README.md)
- Related ADR: [0001 — Record architecture decisions as ADRs](0001-record-architecture-decisions-as-adrs.md)

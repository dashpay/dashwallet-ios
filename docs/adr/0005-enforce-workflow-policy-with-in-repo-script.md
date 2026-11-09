# 0005 — Enforce workflow policy with an in-repo script beside actionlint

- **Status:** Accepted
- **Date:** 2026-11-04
- **Deciders:** romchornyi (author). Approved in #1311 by llbartekll.

## Context

The workflow-lint PR check has four jobs. It must catch malformed workflows and error- or warning-level findings in inline shell. It must fail on steps from other repositories that are not pinned to a full commit, and on checkouts that leave the repository credential behind. It must warn on a changed step that only a release-credential workflow runs. actionlint with shellcheck covers the first, as in DashUIKit. The release-only warning needs custom diff-to-step logic whatever else is chosen. The open choice is what enforces the pinned-step and checkout-credential rules.

## Decision drivers

- The check runs on a secret-free `ubuntu-24.04` runner and reports within about 3 minutes of a push; no new macOS jobs.
- After landing, every new check passes on develop, with each old finding fixed or waived at its own line — no wholesale ignore list.
- Pull requests from forks get the same result without secrets.
- An audit of script injection in the workflows is a separate, later piece of work; this one must not pull it in.
- Repository convention: CI logic in `scripts/ci/` as Python with a self-test.

## Considered options

1. **In-repo policy script** — `scripts/ci/check_workflow_policy.py` (with `--self-test`) implements the pinned-step rule, the checkout-credential rule and the release-only warning. actionlint and shellcheck come in as hash-verified release binaries.
2. **zizmor for pins and credentials** — zizmor, a security linter for GitHub Actions, enforces pins (`unpinned-uses`) and credential-free checkout (`artipacked`). A small in-repo script keeps only the release-only warning.

## Decision outcome

**Chosen:** option 1, the in-repo script `scripts/ci/check_workflow_policy.py` enforces the pinned-step and checkout-credential rules and the release-only warning, next to actionlint. It implements exactly these rules with messages written for this repository, in one place with the release-only warning that has to be custom anyway. zizmor ships many other audits, template injection among them, that fire on today's workflows. With no wholesale ignore list allowed, option 2 would mean either config that turns those audits off or pulling the injection audit into this work.

## Consequences

**Positive**
- Rules, messages and line annotations are written for these rules one to one, and the self-test pins their behaviour.
- One job runs everything: actionlint (with shellcheck on inline `run:`), the policy script and the empty-test-run guard's self-test, on `pull_request` and `push` to develop, with no `paths` filter.
- The script also feeds the composite action's `run:` blocks to shellcheck, closing the gap actionlint leaves in `action.yml` ([ADR-0004](0004-read-xcode-version-file-via-composite-action.md)).

**Negative**
- We maintain the parser for `uses:` forms (`owner/repo[/path]@ref`, `docker://`, local `./`) and for any new form GitHub adds.
- Three tools to update by hand: actionlint, shellcheck and PyYAML, each pinned by hash.
- None of zizmor's wider checks come for free; the later injection audit starts from scratch or adopts zizmor then.

**Neutral**
- Adopting zizmor later for the injection audit can replace the pinned-step and checkout rules in the same move; the release-only warning stays in-repo either way.

## Links

- Feature summary: [docs/features/ci-workflow-hardening/README.md](../features/ci-workflow-hardening/README.md)
- The script: [scripts/ci/check_workflow_policy.py](../../scripts/ci/check_workflow_policy.py)
- The check: [.github/workflows/workflow-lint.yml](../../.github/workflows/workflow-lint.yml)
- Related ADR: [0004 — Read the Xcode version from a file through a composite action](0004-read-xcode-version-file-via-composite-action.md)

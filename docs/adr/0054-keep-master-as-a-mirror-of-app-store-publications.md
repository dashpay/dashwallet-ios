# 0054 — Keep master as a mirror of App Store publications

- **Status:** Proposed
- **Date:** 2026-11-20
- **Deciders:** llbartekll (author), romchornyi

## Context

Every pull request lands on `develop`, and release builds are cut from it. No branch shows what the App Store currently has. The old `master` held the abandoned 8.x line. Release tags were placed by hand, sometimes before publication and once on a moving branch name instead of a commit. One release, 9.1.4, shipped from a side branch that `develop` never merged.

Two things follow from that. A fix for the published version has no clear base when `develop` has moved on or is broken. And QA builds each feature branch before it merges, because a broken `develop` would block the next release.

The App Store observer (`appstore-schema-release.yml`) already runs on a schedule, sees each publication, and reads the build's recorded wallet commit from the release evidence.

## Decision drivers

- The published commit must be findable from a branch and a tag without anyone remembering to record it.
- TestFlight builds stay unrestricted: internal builds from any branch, external builds from `develop`.
- A hotfix must have a base that is exactly the published app.
- No new step for a person on a normal release.

## Considered options

1. **`master` mirrors publications, moved by the observer** — when a publication is observed, the observer tags its wallet commit `vX.Y.Z` and fast-forwards `master` to it.
2. **Release pull requests from `develop` into `master` before each release** — `master` gates the release; promotable builds are allowed only from `master` or from the head of such a pull request.
3. **Tags only, no release branch** — the observer places the tag and nothing else.
4. **Keep the current practice** — one working branch, tags by hand.

## Decision outcome

**Chosen:** option 1, `master` holds only commits the App Store has published, and the App Store observer keeps it there. Option 2 would restrict where TestFlight builds come from, which the team does not want, and it adds a manual step to every release. Option 3 records the commit but gives a hotfix no branch to target. Option 4 leaves the problems in Context as they are.

The rules:

- All work lands on `develop`. `master` takes no ordinary pull request.
- For each publication above 9.1.4 the observer creates the tag `vX.Y.Z` on the build's recorded wallet commit. It never moves an existing tag: one that names another commit is reported and left alone.
- The observer then advances `master` to that commit with a non-forced update, so only a fast-forward can happen. A commit already on `master` needs nothing. A commit that does not descend from `master` is reported and nothing is moved; the repair is a pull request that merges it into `master` with a merge commit.
- A hotfix branches from `master`, merges into `master` by pull request, and is built for release from `master`.
- When `master` holds commits that `develop` lacks, the observer opens a pull request from `master` into `develop`. It is merged with a merge commit, never a squash. A squash carries the changes without the history, and the next release from `develop` would then not descend from `master`.
- The observer runs every four hours, so `master` and the tag follow a publication by up to four hours.
- Publications up to 9.1.4 are not mirrored. `master` starts at `v9.1.3`, the last release that lies on `develop`. The old `master` stays reachable under the tag `archive/master-8.7.0`.

## Consequences

**Positive**
- `master` and the newest `vX.Y.Z` tag name the published commit, with no manual step.
- A hotfix has a base that matches the published app.
- A mistake cannot overwrite history: the branch update is never forced and tags are never moved.

**Negative**
- `master` does not gate a release. A broken `develop` still has to pass regression before an external build.
- The fast-forward depends on `develop` descending from `master`. One squashed or skipped merge of `master` back into `develop` makes the next publication fail to mirror until someone repairs it by hand.
- Until the first publication after 9.1.4, `master` is one release behind the App Store, and a hotfix for 9.1.4 starts from its tag.
- The observer's token needs write access to `master` and to pull requests. A branch rule on `master` must exempt it.

**Neutral**
- GitHub Releases are still written by hand, now against a tag that already exists.
- The cutoff version is a constant in the script; it is not expected to change.

## Links

- The observer: [.github/workflows/appstore-schema-release.yml](../../.github/workflows/appstore-schema-release.yml)
- The script: [.github/scripts/schema_release.rb](../../.github/scripts/schema_release.rb)
- Agent guidance: [AGENTS.md](../../AGENTS.md), section "Branches and releases"

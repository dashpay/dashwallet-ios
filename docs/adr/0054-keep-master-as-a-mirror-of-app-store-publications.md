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

**Chosen:** option 1, `master` follows what the App Store has published, is written only by the App Store observer, and holds nothing else. Option 2 would restrict where TestFlight builds come from, which the team does not want, and it adds a manual step to every release. Option 3 records the commit but gives a hotfix no branch to target. Option 4 leaves the problems in Context as they are.

The rules:

- All work lands on `develop`. `master` takes no pull request and no push; only the observer writes it.
- For each publication above 9.1.4 the observer creates the tag `vX.Y.Z` on the build's recorded wallet commit. It never moves an existing tag: one that names another commit is reported and left alone.
- A publication is mirrored only when the release workflow recorded the binding between its Apple build and its build evidence. Without it the commit is not established, and the observer reports that and writes nothing.
- Only publications App Store Connect lists in that run are mirrored, and only the newest of them moves `master`; an older one is tagged and nothing more. A manual retry of an older release therefore cannot choose the tip.
- For that newest publication the observer advances `master` to its commit with a non-forced update, so only a fast-forward can happen. A commit `master` is already at needs nothing. A commit that `master` is already past is an error: `master` then holds something the App Store has not published, or the newest version was cut from an older commit. It is reported, nothing is moved, and nothing is offered to `develop` in that run. A commit that does not descend from `master` is reported and nothing is moved; someone finds out how the two parted before anything is merged.
- A hotfix gets its own branch, `hotfix/X.Y.Z`, cut from `master`. Its pull requests target that branch, and the release is built from it. `master` does not move until the App Store publishes the build; the observer then fast-forwards `master` to it like any other publication.
- When `master` descends from `v9.1.3` and holds commits that `develop` lacks, the observer opens a pull request from `master` into `develop`, whether or not a publication could be mirrored in that run. That is the case after a published hotfix. A team that wants the fix on `develop` before publication merges the hotfix branch there itself, with a merge commit. The observer's pull request is merged with a merge commit, never a squash. A squash carries the changes without the history, and the next release from `develop` would then not descend from `master`.
- The observer runs every four hours, so `master` and the tag follow a publication by up to four hours.
- Publications up to 9.1.4 are not mirrored. `master` starts at `v9.1.3`, the last release that lies on `develop`. The old `master` stays reachable under the tag `archive/master-8.7.0`.

The cutover is done once, by hand, by someone allowed to force-push `master`:

1. Tag the tip of the old `master` as `archive/master-8.7.0`.
2. Reset `master` to the commit `v9.1.3` names. This is the only forced update `master` ever gets, so a branch rule on `master` is added after it, or lifted for it.
3. Check that `master` is an ancestor of `develop`.

Until the cutover `master` holds the 8.x line. The observer then tags publications, reports that it cannot move `master`, and offers nothing to `develop`.

## Consequences

**Positive**
- `master` and the newest `vX.Y.Z` tag name the published commit, with no manual step.
- A hotfix has a base that matches the published app.
- A mistake cannot overwrite history: the branch update is never forced and tags are never moved.

**Negative**
- A hotfix reaches `develop` through the observer only after publication, and its branch has to be deleted by hand afterwards. Merging hotfix pull requests into `master` first was considered and dropped: `master` would be ahead of the App Store for the length of Apple's review, people would need write access to it, and a rejected hotfix would have to be reverted there.
- `master` does not gate a release. A broken `develop` still has to pass regression before an external build.
- The fast-forward depends on `develop` descending from `master`. One squashed or skipped merge of `master` back into `develop` makes the next publication fail to mirror until someone repairs it by hand.
- From the cutover until the first publication after 9.1.4, `master` is one release behind the App Store, and a hotfix for 9.1.4 starts from the tag `v9.1.4`. Its publication does not descend from `master`, so the observer tags it and reports on every run that it cannot move `master`, until a later publication cut from `develop` does. Such a hotfix is merged into `develop` by hand.
- The observer's token needs write access to `master` and to pull requests. A branch rule on `master` must exempt it, and can refuse everyone else.

**Neutral**
- GitHub Releases are still written by hand, now against a tag that already exists.
- The cutoff version is a constant in the script; it is not expected to change.

## Links

- The observer: [.github/workflows/appstore-schema-release.yml](../../.github/workflows/appstore-schema-release.yml)
- The script: [.github/scripts/schema_release.rb](../../.github/scripts/schema_release.rb)
- Agent guidance: [AGENTS.md](../../AGENTS.md), section "Branches and releases"

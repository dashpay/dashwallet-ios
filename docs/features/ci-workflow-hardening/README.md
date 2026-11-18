# CI workflow hardening

**Owner:** romchornyi · Introduced in the PR that adds this file

## Why

The CI of dashwallet-ios lagged behind the practices of its sibling repository DashUIKit. Every
step taken from another repository followed a movable tag, including in the TestFlight and App
Store workflows that run next to the signing and store credentials. No check looked at the
workflows themselves, and the release workflows are never run by a pull request, so a broken
release step showed up only on release day. The app test check passed when it ran zero tests.
The Xcode version was hard-coded in four places, and the Rust version the workflows installed
was not the one the SDK was actually built with. Develop runs cancelled each other, so a
regression could not always be traced to the commit that caused it.

## What changed

- **Pinned steps.** Every step from another repository is pinned to a full commit, with the
  version it stands for in a comment. No step moved to a different version. Pins are updated by
  hand; there is no update bot.
- **Workflow-lint check** ([`workflow-lint.yml`](../../../.github/workflows/workflow-lint.yml)), on
  every pull request and every push to develop, on a secret-free Linux runner:
  - actionlint, with shellcheck at warning level and above on inline `run:` scripts;
  - [`scripts/ci/check_workflow_policy.py`](../../../scripts/ci/check_workflow_policy.py): fails on
    a step that is not pinned to a full commit and on a checkout that leaves the repository
    credential in the workspace, runs shellcheck on composite actions, and warns on a pull
    request that changes a step of a release-only workflow, deletes a release-only workflow, or
    changes `.xcode-version`;
  - the self-tests of both scripts and
    [`scripts/ci/test_ci_structure.py`](../../../scripts/ci/test_ci_structure.py), which guards
    the wiring of the CI steps these checks rely on.
- **Empty test runs fail.** The app test check fails when the run executed no non-skipped test,
  and its summary shows how many tests ran
  ([`check_test_count.py`](../../../scripts/ci/check_test_count.py)). A build failure still fails
  as a build failure.
- **One source for toolchain versions.** The Xcode version lives in
  [`.xcode-version`](../../../.xcode-version), applied by the composite action
  [`select-xcode`](../../../.github/actions/select-xcode/action.yml)
  ([ADR-0004](../../adr/0004-read-xcode-version-file-via-composite-action.md)). The Rust version
  is the one platform's `rust-toolchain.toml` names at `.platform-ref`
  ([ADR-0003](../../adr/0003-take-rust-toolchain-from-platform-pin.md)). The test and the release
  workflow read both from the branch they build and share one SDK cache entry. A version that
  does not exist fails before the build and before any release credential is read.
- **Every develop commit gets its own test run.** On pull requests a new push still cancels the
  older run.
- **No checkout leaves its credential behind**, in any workflow.
- **PR template.** A pull request that gets the release-only warning, changes `.xcode-version`, or
  bumps `.platform-ref` to a new Rust version links a manual run of the affected workflow on its
  final commit: an internal-only TestFlight release, or the App Store schema workflow's dry run.
- The pre-commit hook no longer claims that CI scans for secrets; no CI job does.

The choice of an in-repo policy script over zizmor is
[ADR-0005](../../adr/0005-enforce-workflow-policy-with-in-repo-script.md).

## How to use it

- **Bump Xcode:** change `.xcode-version`, then run the internal-only TestFlight release and the
  schema dry run from the branch before merging, as the PR template asks.
- **Bump Rust:** bump `.platform-ref`; Rust moves with it. workflow-lint does not flag this case,
  so the PR template item is the reminder.
- **Update a pinned step:** replace the commit and the version comment together. workflow-lint
  fails on anything other than a full commit.
- **Read a finding:** each workflow-lint error names the file, the line and the rule it breaks.

## Operational notes

- Migration: none.
- Configuration: none. Releases of branches cut before `.xcode-version` existed fall back to the
  release tooling's copy and need no edit.
- Rollback: revert the PR. No state outside the repository changes.

## Not in scope

- An audit of script injection in the workflows; [ADR-0005](../../adr/0005-enforce-workflow-policy-with-in-repo-script.md)
  notes how zizmor could take it over later.
- Secret scanning in CI, and a bot that updates the pins.
- Shell scripts outside workflows (for example under `scripts/`) are not linted by workflow-lint.

#!/usr/bin/env python3
"""Tests for the CI wiring that the scripts' own self-tests cannot see.

- Static checks on the real workflow files, the PR template and the repository
  root: the order and conditions of the steps that the CI guarantees rely on
  (guard after tests, lint on every pull request, toolchain before secrets and
  the like; each check's name says which). Each check is a function returning
  its problems; a test runs it on the real files (no problems) and on a broken
  copy (a problem), so a check that cannot fail fails its own test.
- The select-xcode script run over throwaway folders. It stops at the
  not-installed check for a version no runner has, which shows the version and
  file it selected, so it runs on any machine without touching xcode-select.
- Both workflows' Rust read and install scripts run over throwaway folders,
  with rustup and rustc faked on PATH.
- workflow-lint's own check steps run as the runner runs them: actionlint
  over a throwaway tree with broken workflows (needs actionlint and shellcheck
  on PATH: skipped without them, failed without them on GitHub Actions), and
  each Python check with a failing python3 faked on PATH.
- The policy script run end to end in throwaway git repositories, checked out
  the way the workflow-lint job checks out a pull request.

    python3 scripts/ci/test_ci_structure.py

Dependencies: stdlib + PyYAML (scripts/ci/requirements-workflow-lint.txt), git, bash;
actionlint and shellcheck for the actionlint step test.
"""

import copy
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
POLICY_SCRIPT = ROOT / "scripts/ci/check_workflow_policy.py"
UNIT_TESTS = ".github/workflows/unit-tests.yml"
RELEASE = ".github/workflows/release-dashpay-testflight.yml"
WORKFLOW_LINT = ".github/workflows/workflow-lint.yml"
PR_TEMPLATE = ".github/PULL_REQUEST_TEMPLATE.md"
SELECT_XCODE = ".github/actions/select-xcode/action.yml"

TEST_STEP = "Run DashWalletTests"
GUARD_STEP = "Fail on an empty test run"
CACHE_STEP = "Restore release XCFramework cache"
RUST_INSTALL_STEP = "Install Rust from platform's pin"
LINT_CHECK_STEPS = ("Self-test of the empty-test-run guard", "Self-test of the workflow policy script",
                    "CI structure tests", "actionlint", "Workflow policy")
BUILD_MARKERS = ("build_ios.sh", "xcodebuild build", "xcodebuild archive")
IGNORE_FILES = (".shellcheckrc", ".github/actionlint.yaml", ".github/actionlint.yml")
WAIVER = re.compile(r"#\s*shellcheck\s+disable=")
WAIVER_WITH_REASON = re.compile(r"#\s*shellcheck\s+disable=SC\d+(,SC\d+)*\s+#\s*\S")


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def load(rel):
    return yaml.safe_load(read(rel))


def triggers(doc):
    """The `on:` mapping; PyYAML reads the bare key `on` as True."""
    node = doc.get("on", doc.get(True))
    if isinstance(node, str):
        return {node: None}
    if isinstance(node, list):
        return {name: None for name in node}
    return node or {}


def job_with_step(doc, name):
    """The steps of the job that has a step called `name`."""
    for job in doc["jobs"].values():
        steps = job.get("steps", [])
        if any(step.get("name") == name for step in steps):
            return job, steps
    raise AssertionError("no job has a step '{}'".format(name))


def index(steps, **match):
    """Index of the first step whose keys equal `match`, or None."""
    return next((i for i, step in enumerate(steps) if all(step.get(k) == v for k, v in match.items())), None)


def first_build(steps):
    return next((i for i, step in enumerate(steps)
                 if any(marker in (step.get("run") or "") for marker in BUILD_MARKERS)), None)


def reads_secret(node):
    return "secrets." in yaml.safe_dump(node)


# Static checks: each returns a list of problems, empty when the property holds.

def check_guard_after_tests(unit_tests):
    job, steps = job_with_step(unit_tests, TEST_STEP)
    guard, test = index(steps, name=GUARD_STEP), index(steps, name=TEST_STEP)
    if guard is None:
        return ["no '{}' step".format(GUARD_STEP)]
    problems = ["{} has continue-on-error, so a failure there leaves the job green".format(what)
                for what, node in (("the job", job), ("the test step", steps[test]), ("the guard", steps[guard]))
                if "continue-on-error" in node]
    if guard < test:
        problems.append("the guard runs before the test step")
    if "if" in steps[guard]:
        problems.append("the guard has a condition ({}); it must run only after a successful test step"
                        .format(steps[guard]["if"]))
    return problems


def check_lint_on_every_pr(workflow_lint):
    pull_request = triggers(workflow_lint).get("pull_request", False)
    if pull_request is False:
        return ["no pull_request trigger"]
    return ["pull_request has a {} filter, so some pull requests get no workflow-lint result".format(key)
            for key in (pull_request or {})]


def check_lint_secret_free(workflow_lint):
    problems = []
    if reads_secret(workflow_lint):
        problems.append("reads a secret")
    extra = set(triggers(workflow_lint)) - {"pull_request", "push"}
    if extra:
        problems.append("has triggers beyond pull_request and push: {}".format(sorted(extra)))
    if workflow_lint.get("permissions") != {"contents": "read"}:
        problems.append("permissions are not contents: read")
    return problems


def check_no_ignore_files(root, policy_texts):
    problems = ["{} exists".format(rel) for rel in IGNORE_FILES if (root / rel).exists()]
    for rel, text in policy_texts.items():
        for number, line in enumerate(text.splitlines(), 1):
            if WAIVER.search(line) and not WAIVER_WITH_REASON.search(line):
                problems.append("{}:{}: waiver without a rule id and a reason".format(rel, number))
    return problems


def check_shared_cache_key(unit_tests, release):
    keys, problems = [], []
    for rel, doc in ((UNIT_TESTS, unit_tests), (RELEASE, release)):
        _, steps = job_with_step(doc, CACHE_STEP)
        keys.append(steps[index(steps, name=CACHE_STEP)]["with"]["key"])
        xcode, rust = index(steps, id="xcode"), index(steps, id="rust")
        if xcode is None or not steps[xcode].get("uses", "").endswith("/.github/actions/select-xcode"):
            problems.append("{}: step id xcode is not the select-xcode action".format(rel))
        if rust is None or "rust-toolchain.toml" not in (steps[rust].get("run") or ""):
            problems.append("{}: step id rust does not read platform's rust-toolchain.toml".format(rel))
    if keys[0] != keys[1]:
        problems.append("cache keys differ: {!r} vs {!r}".format(*keys))
    for part in ("steps.xcode.outputs.version", "steps.rust.outputs.version"):
        if part not in keys[0]:
            problems.append("cache key does not take {}".format(part))
    return problems


def check_toolchain_first(doc, before_secrets):
    job, steps = job_with_step(doc, CACHE_STEP)
    toolchain = {"select Xcode": index(steps, id="xcode"), "read Rust": index(steps, id="rust"),
                 "install Rust": index(steps, name=RUST_INSTALL_STEP),
                 "restore the cache": index(steps, name=CACHE_STEP)}
    limits = {"the build": first_build(steps)}
    if before_secrets:
        if reads_secret({k: v for k, v in job.items() if k != "steps"}):
            return ["the job itself reads a secret, so every step does"]
        limits["the first secret"] = next((i for i, step in enumerate(steps) if reads_secret(step)), None)
    problems = []
    for what, at in toolchain.items():
        for limit, bound in limits.items():
            if at is None or bound is None or at > bound:
                problems.append("{} does not come before {}".format(what, limit))
    return problems


def check_per_commit_runs(unit_tests):
    concurrency, problems = unit_tests.get("concurrency", {}), []
    group = concurrency.get("group", "")
    if "github.sha" not in group or "github.event_name != 'pull_request'" not in group:
        problems.append("the group does not add the commit for non-pull-request runs: {}".format(group))
    if concurrency.get("cancel-in-progress") != "${{ github.event_name == 'pull_request' }}":
        problems.append("cancel-in-progress is not limited to pull requests")
    if "develop" not in ((triggers(unit_tests).get("push") or {}).get("branches") or []):
        problems.append("no push trigger on develop")
    return problems


def check_pre_merge_item(template):
    items = [line for line in template.splitlines() if line.startswith("- [ ]")
             and all(part in line for part in ("release-dashpay-testflight.yml", "appstore-schema-release.yml",
                                               "wallet_ref", "internal-only", "dry_run: true", "final commit"))]
    return [] if len(items) == 1 else ["{} pre-merge release-run items, expected 1".format(len(items))]


def check_lint_runs_this_test(workflow_lint):
    _, steps = job_with_step(workflow_lint, "Workflow policy")
    runs = [step for step in steps if "scripts/ci/test_ci_structure.py" in (step.get("run") or "")]
    if not runs:
        return ["no step runs scripts/ci/test_ci_structure.py"]
    return [] if runs[0].get("if") == "${{ !cancelled() }}" else ["its step does not run after a failed check"]


def check_lint_steps_fail_the_job(workflow_lint):
    job, steps = job_with_step(workflow_lint, "Workflow policy")
    problems = ["the job has continue-on-error"] if "continue-on-error" in job else []
    if "if" in job:
        problems.append("the job runs under {!r}, so a skipped job leaves the check green".format(job["if"]))
    if "needs" in job:
        problems.append("the job needs {!r}, so a skipped dependency leaves the check green".format(job["needs"]))
    for name in LINT_CHECK_STEPS:
        at = index(steps, name=name)
        if at is None:
            problems.append("no '{}' step".format(name))
            continue
        if "continue-on-error" in steps[at]:
            problems.append("'{}' has continue-on-error, so its failure leaves the check green".format(name))
        if steps[at].get("if") != "${{ !cancelled() }}":
            problems.append("'{}' runs under {!r}, not after any earlier failure".format(name, steps[at].get("if")))
    return problems


def check_lint_compares_with_first_parent(workflow_lint):
    _, steps = job_with_step(workflow_lint, "Workflow policy")
    problems = []
    checkout = steps[index(steps, name="Checkout")]
    if (checkout.get("with") or {}).get("fetch-depth") != 2:
        problems.append("the checkout is not fetch-depth: 2 (the merge commit and its parents)")
    run = steps[index(steps, name="Workflow policy")].get("run") or ""
    if '[ "$GITHUB_EVENT_NAME" = pull_request ]' not in run or "--base HEAD^1" not in run:
        problems.append("the policy step does not pass --base HEAD^1 on pull_request")
    if "base.sha" in yaml.safe_dump(steps) or "git fetch" in run:
        problems.append("the policy step still fetches or reads the event's base SHA")
    return problems


def move(steps, name, to):
    """A copy of `steps` with the step called `name` moved to index `to`."""
    steps = copy.deepcopy(steps)
    steps.insert(to, steps.pop(index(steps, name=name)))
    return steps


def with_steps(doc, step_name, edit):
    """A copy of `doc` with `edit` applied to the steps of the job that has `step_name`."""
    doc = copy.deepcopy(doc)
    job, steps = job_with_step(doc, step_name)
    job["steps"] = edit(steps)
    return doc


class StaticChecks(unittest.TestCase):
    """Each property holds on the real files and is caught when broken."""

    def assert_holds_and_catches(self, check, real, broken):
        self.assertEqual(check(*real), [])
        self.assertNotEqual(check(*broken), [], "the check missed a broken copy")

    def test_guard_runs_only_after_a_successful_test_step(self):
        unit = load(UNIT_TESTS)
        self.assertEqual(check_guard_after_tests(unit), [])
        always = with_steps(unit, GUARD_STEP, lambda s: [dict(x, **({"if": "always()"} if x.get("name") == GUARD_STEP
                                                                    else {})) for x in s])
        self.assertNotEqual(check_guard_after_tests(always), [])
        early = with_steps(unit, GUARD_STEP, lambda s: move(s, GUARD_STEP, index(s, name=TEST_STEP)))
        self.assertNotEqual(check_guard_after_tests(early), [])

    def test_neither_the_test_step_nor_the_guard_may_continue_on_error(self):
        unit = load(UNIT_TESTS)
        for name in (TEST_STEP, GUARD_STEP):
            with self.subTest(step=name):
                broken = with_steps(unit, GUARD_STEP, lambda s: [
                    dict(x, **({"continue-on-error": True} if x.get("name") == name else {})) for x in s])
                self.assertNotEqual(check_guard_after_tests(broken), [])
        broken = copy.deepcopy(unit)
        job_with_step(broken, GUARD_STEP)[0]["continue-on-error"] = True
        self.assertNotEqual(check_guard_after_tests(broken), [])

    def test_workflow_lint_runs_on_every_pull_request(self):
        lint = load(WORKFLOW_LINT)
        self.assertEqual(check_lint_on_every_pr(lint), [])
        for key, value in (("paths", [".github/**"]), ("types", ["closed"]), ("branches", ["main"]),
                           ("branches-ignore", ["**"])):
            with self.subTest(filter=key):
                broken = copy.deepcopy(lint)
                broken[True]["pull_request"] = {key: value}
                self.assertNotEqual(check_lint_on_every_pr(broken), [])

    def test_workflow_lint_needs_no_secret_and_no_privileged_trigger(self):
        lint = load(WORKFLOW_LINT)
        self.assertEqual(check_lint_secret_free(lint), [])
        target = copy.deepcopy(lint)
        target[True]["pull_request_target"] = None
        self.assertNotEqual(check_lint_secret_free(target), [])
        secret = copy.deepcopy(lint)
        secret["env"] = {"TOKEN": "${{ secrets.SCHEMA_RELEASE_TOKEN }}"}
        self.assertNotEqual(check_lint_secret_free(secret), [])

    def test_no_ignore_file_and_every_waiver_has_its_reason(self):
        texts = {rel: read(rel) for rel in [p.relative_to(ROOT).as_posix() for p in
                                            sorted((ROOT / ".github").rglob("*.y*ml"))]}
        self.assert_holds_and_catches(check_no_ignore_files, (ROOT, texts),
                                      (ROOT, {"w.yml": "  # shellcheck disable=SC2086\n"}))
        self.assertEqual(check_no_ignore_files(ROOT, {"w.yml": "  # shellcheck disable=SC2086 # word split on purpose\n"}), [])
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / ".shellcheckrc").write_text("disable=SC2086\n", encoding="utf-8")
            self.assertNotEqual(check_no_ignore_files(Path(tmp), {}), [])

    def test_both_workflows_build_the_same_cache_key_from_the_single_sources(self):
        unit, release = load(UNIT_TESTS), load(RELEASE)
        broken = with_steps(release, CACHE_STEP, lambda s: [
            dict(x, **({"with": dict(x["with"], key=x["with"]["key"].replace("-v1-", "-v2-"))}
                       if x.get("name") == CACHE_STEP else {})) for x in s])
        self.assert_holds_and_catches(check_shared_cache_key, (unit, release), (unit, broken))

    def test_release_reads_its_toolchain_before_any_secret_and_the_build(self):
        release = load(RELEASE)
        early_secret = with_steps(release, CACHE_STEP, lambda s: move(s, "Validate release secrets", 0))
        self.assert_holds_and_catches(check_toolchain_first, (release, True), (early_secret, True))
        late_cache = with_steps(release, CACHE_STEP, lambda s: move(s, CACHE_STEP, len(s) - 1))
        self.assertNotEqual(check_toolchain_first(late_cache, True), [])
        late_rust = with_steps(release, CACHE_STEP, lambda s: move(
            s, RUST_INSTALL_STEP, index(s, name="Validate release secrets")))
        self.assertNotEqual(check_toolchain_first(late_rust, True), [], "the check missed a late Rust install")

    def test_unit_tests_reads_its_toolchain_before_the_build(self):
        unit = load(UNIT_TESTS)
        late_xcode = with_steps(unit, CACHE_STEP, lambda s: move(s, "Select Xcode from .xcode-version", len(s) - 1))
        self.assert_holds_and_catches(check_toolchain_first, (unit, False), (late_xcode, False))
        late_rust = with_steps(unit, CACHE_STEP, lambda s: move(s, RUST_INSTALL_STEP, len(s) - 1))
        self.assertNotEqual(check_toolchain_first(late_rust, False), [], "the check missed a late Rust install")

    def test_develop_runs_are_grouped_per_commit(self):
        unit = load(UNIT_TESTS)
        broken = copy.deepcopy(unit)
        broken["concurrency"]["group"] = "unit-tests-${{ github.ref }}"
        self.assert_holds_and_catches(check_per_commit_runs, (unit,), (broken,))

    def test_pr_template_has_one_pre_merge_release_run_item(self):
        template = read(PR_TEMPLATE)
        broken = "\n".join(line for line in template.splitlines() if "wallet_ref" not in line)
        self.assert_holds_and_catches(check_pre_merge_item, (template,), (broken,))

    def test_workflow_lint_compares_with_the_merge_commits_first_parent(self):
        lint = load(WORKFLOW_LINT)
        shallow = with_steps(lint, "Workflow policy", lambda s: [
            dict(x, **({"with": {"persist-credentials": False}} if x.get("name") == "Checkout" else {})) for x in s])
        event_base = with_steps(lint, "Workflow policy", lambda s: [
            dict(x, **({"run": x["run"].replace("--base HEAD^1", '--base "$BASE_SHA"')}
                       if x.get("name") == "Workflow policy" else {})) for x in s])
        self.assert_holds_and_catches(check_lint_compares_with_first_parent, (lint,), (shallow,))
        self.assertNotEqual(check_lint_compares_with_first_parent(event_base), [])

    def test_every_workflow_lint_check_can_fail_the_job(self):
        lint = load(WORKFLOW_LINT)
        self.assertEqual(check_lint_steps_fail_the_job(lint), [])
        for name in LINT_CHECK_STEPS:
            for key, value in (("continue-on-error", True), ("if", "success()")):
                with self.subTest(step=name, key=key):
                    broken = with_steps(lint, "Workflow policy", lambda s: [
                        dict(x, **({key: value} if x.get("name") == name else {})) for x in s])
                    self.assertNotEqual(check_lint_steps_fail_the_job(broken), [])
        for key, value in (("continue-on-error", True), ("if", "github.event_name == 'push'"), ("if", False),
                           ("needs", "gate")):
            with self.subTest(job=key, value=value):
                broken = copy.deepcopy(lint)
                job_with_step(broken, "Workflow policy")[0][key] = value
                self.assertNotEqual(check_lint_steps_fail_the_job(broken), [])

    def test_workflow_lint_runs_this_test(self):
        lint = load(WORKFLOW_LINT)
        broken = with_steps(lint, "Workflow policy", lambda s: [x for x in s if "test_ci_structure" not in
                                                                (x.get("run") or "")])
        self.assert_holds_and_catches(check_lint_runs_this_test, (lint,), (broken,))


class SelectXcode(unittest.TestCase):
    """The select-xcode script over throwaway folders."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.app, self.fallback = self.tmp / "app", self.tmp / "fallback"
        self.app.mkdir()
        self.fallback.mkdir()
        self.script = yaml.safe_load(read(SELECT_XCODE))["runs"]["steps"][0]["run"]

    def run_select(self, app=None, fallback=None, fallback_path=True):
        for folder, text in ((self.app, app), (self.fallback, fallback)):
            if text is not None:
                (folder / ".xcode-version").write_text(text, encoding="utf-8")
        output = self.tmp / "output"
        env = dict(os.environ, APP_PATH=str(self.app), FALLBACK_PATH=str(self.fallback) if fallback_path else "",
                   GITHUB_OUTPUT=str(output))
        return subprocess.run(["bash", "-c", self.script], capture_output=True, text=True, env=env)

    def assert_not_installed(self, result, version, folder):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("::error::select_xcode.not_installed: Xcode {} from {}/.xcode-version is not installed. "
                      "Available: ".format(version, folder), result.stdout)

    def test_branch_without_its_own_file_falls_back_to_the_release_tooling(self):
        result = self.run_select(fallback="0.0-fallback\n")
        self.assertIn("(fallback: {} has no .xcode-version)".format(self.app), result.stdout)
        self.assert_not_installed(result, "0.0-fallback", self.fallback)

    def test_branch_with_its_own_file_wins(self):
        self.assert_not_installed(self.run_select(app="0.0-app\n", fallback="0.0-fallback\n"), "0.0-app", self.app)

    def test_version_is_trimmed(self):
        self.assert_not_installed(self.run_select(app="  0.0-trim \n\n"), "0.0-trim", self.app)

    def test_version_not_on_the_runner_fails_and_lists_the_installed_ones(self):
        self.assert_not_installed(self.run_select(app="0.0-none", fallback_path=False), "0.0-none", self.app)

    def test_missing_or_empty_file_fails_with_its_own_reason(self):
        for app in (None, " \n"):
            with self.subTest(app=app):
                result = self.run_select(app=app, fallback_path=False)
                self.assertEqual(result.returncode, 1)
                self.assertIn("::error::select_xcode.version_file_missing: .xcode-version is missing or empty in "
                              "{}/.xcode-version. Rule: CI builds with the Xcode version named in .xcode-version "
                              "at the repository root.".format(self.app), result.stdout)
                self.assertNotIn("not_installed", result.stdout)


class RustToolchain(unittest.TestCase):
    """Both workflows' Rust read and install scripts over throwaway folders."""

    READ_STEP = "Read Rust version from platform"
    INSTALL_STEP = "Install Rust from platform's pin"
    SHA = "0123abc"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.platform, self.bin = self.tmp / "platform", self.tmp / "bin"
        self.platform.mkdir()
        self.bin.mkdir()

    def script(self, rel, name):
        _, steps = job_with_step(load(rel), name)
        return steps[index(steps, name=name)]["run"]

    def run_script(self, script, **env):
        output = self.tmp / "output"
        output.write_text("", encoding="utf-8")
        env = dict(os.environ, PLATFORM_SHA=self.SHA, GITHUB_OUTPUT=str(output),
                   PATH="{}:{}".format(self.bin, os.environ["PATH"]), **env)
        result = subprocess.run(["bash", "-c", script], cwd=self.platform, capture_output=True, text=True, env=env)
        return result, output.read_text(encoding="utf-8")

    def fake(self, tool, status):
        path = self.bin / tool
        path.write_text("#!/bin/sh\necho {} \"$@\"\nexit {}\n".format(tool, status), encoding="utf-8")
        path.chmod(0o755)

    def test_reads_the_toolchain_channel(self):
        (self.platform / "rust-toolchain.toml").write_text(
            '[other]\nchannel = "wrong"\n\n[toolchain]\nchannel = "1.98.1"\ncomponents = ["rustfmt"]\n', encoding="utf-8")
        for rel in (UNIT_TESTS, RELEASE):
            with self.subTest(workflow=rel):
                result, output = self.run_script(self.script(rel, self.READ_STEP))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(output, "version=1.98.1\n")

    def test_no_channel_fails_and_names_the_platform_commit(self):
        cases = {"no file": None, "no [toolchain]": '[other]\nchannel = "1.98.1"\n',
                 "no channel": '[toolchain]\ncomponents = ["rustfmt"]\n'}
        for rel in (UNIT_TESTS, RELEASE):
            for case, text in cases.items():
                with self.subTest(workflow=rel, case=case):
                    toml = self.platform / "rust-toolchain.toml"
                    if text is None:
                        toml.unlink(missing_ok=True)
                    else:
                        toml.write_text(text, encoding="utf-8")
                    result, output = self.run_script(self.script(rel, self.READ_STEP))
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn("::error::rust_toolchain.not_found: no [toolchain] channel in platform's "
                                  "rust-toolchain.toml at {}.".format(self.SHA), result.stdout)
                    self.assertEqual(output, "")

    def test_version_rustup_cannot_install_fails_and_names_it(self):
        self.fake("rustup", 1)
        for rel in (UNIT_TESTS, RELEASE):
            with self.subTest(workflow=rel):
                result, _ = self.run_script(self.script(rel, self.INSTALL_STEP), RUST_VERSION="0.0.0-none")
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("::error::rust_toolchain.not_found: Rust 0.0.0-none from platform's rust-toolchain.toml "
                              "at {} could not be installed.".format(self.SHA), result.stdout)

    def test_installs_the_version_it_read(self):
        self.fake("rustup", 0)
        self.fake("rustc", 0)
        for rel in (UNIT_TESTS, RELEASE):
            with self.subTest(workflow=rel):
                result, _ = self.run_script(self.script(rel, self.INSTALL_STEP), RUST_VERSION="1.98.1")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("rustup toolchain install 1.98.1 --profile minimal", result.stdout)
                self.assertNotIn("not_found", result.stdout)


SHELL_WORKFLOW = """\
on: push
jobs:
  a:
    runs-on: ubuntu-24.04
    steps:
      - name: Warning
        run: |
          export STAMP=$(date)
          echo "$STAMP"
      - name: Style only
        run: echo "Built at `date`"
"""


class LintSteps(unittest.TestCase):
    """workflow-lint's own check steps, run as the runner runs them."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.tree, self.bin = self.tmp / "tree", self.tmp / "bin"
        self.tree.mkdir()
        self.bin.mkdir()

    def run_step(self, name, **env):
        _, steps = job_with_step(load(WORKFLOW_LINT), name)
        step = steps[index(steps, name=name)]
        (self.tmp / "runner").mkdir(exist_ok=True)
        env = dict(os.environ, **(step.get("env") or {}), RUNNER_TEMP=str(self.tmp / "runner"),
                   GITHUB_STEP_SUMMARY=str(self.tmp / "summary"), **env)
        return subprocess.run(["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step["run"]],
                              cwd=self.tree, capture_output=True, text=True, env=env)

    def fake_python(self, status):
        path = self.bin / "python3"
        path.write_text("#!/bin/sh\nexit {}\n".format(status), encoding="utf-8")
        path.chmod(0o755)
        return "{}:{}".format(self.bin, os.environ["PATH"])

    def test_each_python_check_step_fails_when_its_tool_fails(self):
        python_steps = [(name, event) for name in LINT_CHECK_STEPS if name != "actionlint"
                        for event in (("pull_request", "push") if name == "Workflow policy" else ("pull_request",))]
        for status in (0, 1):
            path = self.fake_python(status)
            for name, event in python_steps:
                with self.subTest(step=name, event=event, tool_exit=status):
                    result = self.run_step(name, PATH=path, GITHUB_EVENT_NAME=event)
                    self.assertEqual(result.returncode != 0, status != 0, result.stdout + result.stderr)

    def test_actionlint_fixture_test_skips_only_outside_ci(self):
        test = "LintSteps.test_actionlint_step_fails_on_broken_workflows_with_file_and_line"
        env = {k: v for k, v in os.environ.items() if k != "GITHUB_ACTIONS"}
        for tools, missing in (((), ("actionlint", "shellcheck")), (("actionlint",), ("shellcheck",))):
            for tool in tools:
                (self.bin / tool).write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                (self.bin / tool).chmod(0o755)
            for ci in (False, True):
                with self.subTest(tools=tools, ci=ci):
                    run_env = dict(env, PATH=str(self.bin), **({"GITHUB_ACTIONS": "true"} if ci else {}))
                    result = subprocess.run([sys.executable, str(Path(__file__).resolve()), "-v", test],
                                            capture_output=True, text=True, env=run_env)
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode != 0, ci, output)
                    self.assertEqual("skipped" in output, not ci, output)
                    for name in missing:
                        self.assertIn(name, output)

    def test_actionlint_step_fails_on_broken_workflows_with_file_and_line(self):
        missing = [tool for tool in ("actionlint", "shellcheck") if not shutil.which(tool)]
        if missing:
            message = "{} not on PATH".format(" and ".join(missing))
            if os.environ.get("GITHUB_ACTIONS"):
                self.fail(message + "; workflow-lint installs them before the CI structure tests")
            self.skipTest(message)
        shutil.copytree(ROOT / ".github", self.tree / ".github")
        git(self.tree, "init", "-q")
        workflows = self.tree / ".github/workflows"
        (workflows / "malformed.yml").write_text("on: push\njobs:\n  a: [\n", encoding="utf-8")
        release = workflows / Path(RELEASE).name
        release.write_text(release.read_text(encoding="utf-8").replace("\njobs:\n", "\njobs:\n  broken: [\n", 1),
                           encoding="utf-8")
        (workflows / "shell.yml").write_text(SHELL_WORKFLOW, encoding="utf-8")
        result = self.run_step("actionlint")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        errors = annotations(result.stdout, "error")
        for rel in ("malformed.yml", Path(RELEASE).name):
            with self.subTest(file=rel):
                self.assertTrue([e for e in errors if e.startswith("::error file=.github/workflows/{},line=".format(rel))
                                 and "workflow_lint.actionlint:" in e], result.stdout)
        shell = [e for e in errors if "file=.github/workflows/shell.yml," in e]
        self.assertEqual(len(shell), 1, result.stdout)
        self.assertRegex(shell[0], r"^::error file=\.github/workflows/shell\.yml,line=\d+,col=\d+::"
                                   r"workflow_lint\.shellcheck: .*SC2155")
        files = {e.split(",", 1)[0] for e in errors}
        self.assertEqual(files, {"::error file=.github/workflows/" + name
                                 for name in ("malformed.yml", Path(RELEASE).name, "shell.yml")}, result.stdout)


RELEASE_WORKFLOW = """\
on:
  workflow_dispatch:
jobs:
  release:
    runs-on: macos-15
    environment: testflight
    steps:
      - name: Build
        run: |
          set -euo pipefail
          make build
      - name: Upload
        run: upload --key "$KEY"
        env:
          KEY: ${{ secrets.ASC_KEY }}
"""


def git(cwd, *args):
    """Run git with a fixed identity and no hooks; return its stdout."""
    result = subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "core.hooksPath=/dev/null",
         "-c", "init.defaultBranch=main", "-c", "protocol.file.allow=always"] + list(args),
        cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError("git {} failed: {}".format(" ".join(args), result.stderr))
    return result.stdout.strip()


class Repo:
    """A throwaway repository holding the policy script and the given files."""

    def __init__(self, tmp):
        self.path = Path(tmp) / "src"
        (self.path / "scripts/ci").mkdir(parents=True)
        shutil.copy(POLICY_SCRIPT, self.path / "scripts/ci")
        git(self.path, "init", "-q")
        git(self.path, "config", "uploadpack.allowAnySHA1InWant", "true")

    def commit(self, files):
        for rel, text in files.items():
            (self.path / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.path / rel).write_text(text, encoding="utf-8")
        git(self.path, "add", "-A")
        git(self.path, "commit", "-q", "-m", "commit")
        return git(self.path, "rev-parse", "HEAD")

    def merge(self, branch):
        """Merge `branch` into the current branch with a merge commit, as GitHub's pull request merge ref."""
        git(self.path, "merge", "-q", "--no-ff", "-m", "merge", branch)

    def checkout(self, depth=2):
        """A clone of HEAD at `depth`; workflow-lint checks out the merge commit at depth 2."""
        clone = self.path.parent / "clone"
        shutil.rmtree(clone, ignore_errors=True)
        git(self.path.parent, "clone", "-q", "--depth={}".format(depth), "file://{}".format(self.path), str(clone))
        return clone


def run_policy(checkout, *args):
    env = dict(os.environ)
    env.pop("GITHUB_STEP_SUMMARY", None)
    return subprocess.run([sys.executable, str(checkout / "scripts/ci/check_workflow_policy.py")] + list(args),
                          capture_output=True, text=True, env=env)


def annotations(output, level):
    return [line for line in output.splitlines() if line.startswith("::{} ".format(level))]


class PolicyEndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.repo = Repo(self.tmp)

    def test_edited_release_step_warns_once_from_a_shallow_checkout(self):
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW})
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW.replace(
            "make build", "make build ARCHS=arm64")})
        result = run_policy(self.repo.checkout(), "--base", "HEAD^1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        warnings = annotations(result.stdout, "warning")
        self.assertEqual(len(warnings), 1, result.stdout)
        self.assertIn("file=.github/workflows/release.yml,line=11::workflow_policy.release_only_step_changed: "
                      "no PR check runs step 'Build'", warnings[0])

    def test_line_deleted_inside_a_release_step_warns(self):
        guarded = RELEASE_WORKFLOW.replace("      - name: Upload\n", "      - name: Upload\n        if: inputs.x\n")
        self.repo.commit({".github/workflows/release.yml": guarded})
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW})
        result = run_policy(self.repo.checkout(), "--base", "HEAD^1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        warnings = annotations(result.stdout, "warning")
        self.assertEqual(len(warnings), 1, result.stdout)
        self.assertIn("line=12::workflow_policy.release_only_step_changed: no PR check runs step 'Upload'",
                      warnings[0])

    def test_only_the_pull_requests_own_changes_warn_after_the_base_branch_moved(self):
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW})
        git(self.repo.path, "checkout", "-q", "-b", "feature")
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW.replace(
            "make build", "make build ARCHS=arm64")})
        git(self.repo.path, "checkout", "-q", "main")
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW.replace(
            'upload --key "$KEY"', 'upload --verbose --key "$KEY"')})
        self.repo.merge("feature")
        result = run_policy(self.repo.checkout(), "--base", "HEAD^1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        warnings = annotations(result.stdout, "warning")
        self.assertEqual(len(warnings), 1, result.stdout)
        self.assertIn("no PR check runs step 'Build'", warnings[0])

    def test_checkout_without_the_base_fails_with_an_error(self):
        self.repo.commit({".github/workflows/release.yml": RELEASE_WORKFLOW})
        self.repo.commit({"README.md": "docs only\n"})
        result = run_policy(self.repo.checkout(depth=1), "--base", "HEAD^1")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("::error::cannot compare with --base HEAD^1:", result.stdout)

    def test_tagged_step_in_an_untouched_workflow_still_fails(self):
        self.repo.commit({".github/workflows/old.yaml": "on: push\njobs:\n  a:\n    runs-on: x\n"
                                                              "    steps:\n      - name: Cache\n"
                                                              "        uses: actions/cache@v5\n"})
        self.repo.commit({"README.md": "docs only\n"})
        for args in ((), ("--base", "HEAD^1")):
            with self.subTest(args=args):
                result = run_policy(self.repo.checkout() if args else self.repo.path, *args)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("::error file=.github/workflows/old.yaml,line=7::workflow_policy.unpinned_step: "
                              "step 'Cache' uses 'actions/cache@v5'", result.stdout)

    def test_changed_xcode_version_warns_and_passes(self):
        self.repo.commit({".xcode-version": "26.5\n"})
        self.repo.commit({".xcode-version": "26.6\n"})
        result = run_policy(self.repo.checkout(), "--base", "HEAD^1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(annotations(result.stdout, "warning"), [
            "::warning file=.xcode-version,line=1::workflow_policy.toolchain_source_changed: '.xcode-version' "
            "changed; the release workflows build with it next to release or store credentials, and no PR check "
            "runs them. Run them by hand on this commit before merging (TestFlight: internal-only upload; "
            "schema: dry run)."])


if __name__ == "__main__":
    unittest.main()

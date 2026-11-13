#!/usr/bin/env python3
"""Enforce the repository's GitHub Actions policy on every workflow and composite action.

Rules, on every file whether a pull request changed it or not:

- workflow_policy.unpinned_step: a `uses:` from another repository is not a full
  40-hex commit, or a `docker://` image is not a sha256 digest. Local `./` steps
  are exempt.
- workflow_policy.checkout_credential_left: an `actions/checkout` step does not
  set `persist-credentials: false`.
- workflow_lint.shellcheck: an error- or warning-level shellcheck finding in a
  composite action's bash `run:` block, at its action.yml line (actionlint
  checks inline workflow scripts but does not read action.yml).

Warnings, only with --base (the pull request base commit):

- workflow_policy.release_only_step_changed: the pull request changes a step of
  a release-only workflow, one that no PR check runs: no pull_request trigger,
  and a secret other than GITHUB_TOKEN or a job `environment:`.
- workflow_policy.toolchain_source_changed: the pull request changes .xcode-version.

    check_workflow_policy.py [--base <rev>]
    check_workflow_policy.py --self-test

Reads .github/workflows/*.yml and *.yaml, and every action.yml / action.yaml
under .github/actions, below the repository root. Findings go to stdout as workflow commands, and a summary
section goes to $GITHUB_STEP_SUMMARY when it is set.

Exit codes: 0 no error-level finding (warnings allowed); 1 at least one
error-level finding; 2 usage error or an input it cannot parse.
Dependencies: stdlib + PyYAML (scripts/ci/requirements-workflow-lint.txt).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import namedtuple
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]

UNPINNED = "workflow_policy.unpinned_step"
CHECKOUT = "workflow_policy.checkout_credential_left"
RELEASE_ONLY = "workflow_policy.release_only_step_changed"
TOOLCHAIN = "workflow_policy.toolchain_source_changed"
SHELLCHECK = "workflow_lint.shellcheck"
XCODE_VERSION_FILE = ".xcode-version"
ACTION_FILES = ("action.yml", "action.yaml")
PRE_MERGE_RUN = ("Run that workflow by hand on this commit before merging "
                 "(TestFlight: internal-only upload; schema: dry run).")

Finding = namedtuple("Finding", "level code path line message")


class ParseError(Exception):
    pass


PINNED_REPO = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
PINNED_IMAGE = re.compile(r"@sha256:[0-9a-f]{64}$")


def child(node, key):
    """The value node under `key` in a YAML mapping node, or None."""
    if not isinstance(node, yaml.MappingNode):
        return None
    for key_node, value_node in node.value:
        if isinstance(key_node, yaml.ScalarNode) and key_node.value == key:
            return value_node
    return None


def scalar(node):
    return node.value if isinstance(node, yaml.ScalarNode) else None


def items(node):
    if isinstance(node, yaml.SequenceNode):
        return node.value
    if isinstance(node, yaml.MappingNode):
        return [value for _, value in node.value]
    return []


def line_of(node):
    return node.start_mark.line + 1


def is_pinned(uses):
    if uses.startswith("./"):
        return True
    if uses.startswith("docker://"):
        return bool(PINNED_IMAGE.search(uses))
    return bool(PINNED_REPO.match(uses))


def steps_with_uses(path, root):
    """Every mapping that carries a `uses:` — workflow steps, reusable-workflow jobs, action steps."""
    if path.endswith(("/action.yml", "/action.yaml")):
        return [s for s in items(child(child(root, "runs"), "steps")) if child(s, "uses")]
    found = []
    for job in items(child(root, "jobs")):
        if child(job, "uses"):
            found.append(job)
        found += [s for s in items(child(job, "steps")) if child(s, "uses")]
    return found


def compose(text):
    """The YAML node tree of `text`; ParseError if it is not YAML or any mapping repeats a key.

    `child()` reads only the first of two equal keys, so a duplicate would hide the second value.
    """
    try:
        root = yaml.compose(text)
    except yaml.YAMLError as error:
        raise ParseError(str(error).replace("\n", " "))
    pending, seen = [root], set()
    while pending:
        node = pending.pop()
        if node is None or id(node) in seen:
            continue
        seen.add(id(node))
        if isinstance(node, yaml.MappingNode):
            keys = set()
            for key_node, value_node in node.value:
                key = scalar(key_node)
                if key is not None and key in keys:
                    raise ParseError("duplicate key '{}' at line {}".format(key, line_of(key_node)))
                keys.add(key)
                pending += [key_node, value_node]
        elif isinstance(node, yaml.SequenceNode):
            pending += node.value
    return root


def check_file(path, text):
    """Return the findings for one workflow or action file; ParseError if it is not YAML."""
    root = compose(text)
    findings = []
    for step in steps_with_uses(path, root):
        uses_node = child(step, "uses")
        uses = scalar(uses_node) or ""
        name = scalar(child(step, "name")) or uses
        if not is_pinned(uses):
            findings.append(Finding(
                "error", UNPINNED, path, line_of(uses_node),
                "{}: step '{}' uses '{}'. Rule: every step from another repository is a pinned "
                "step (a full 40-hex commit, or a sha256 image digest).".format(UNPINNED, name, uses)))
        if uses.split("@")[0].lower() == "actions/checkout":
            persist = scalar(child(child(step, "with"), "persist-credentials")) or ""
            if persist.lower() != "false":
                findings.append(Finding(
                    "error", CHECKOUT, path, line_of(step),
                    "{}: checkout step '{}' leaves the repository credential in the workspace. "
                    "Rule: a checkout must set persist-credentials: false.".format(CHECKOUT, name)))
    return findings


SECRET_REF = re.compile(r"secrets\.([A-Za-z0-9_-]+)")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def triggers(root):
    node = child(root, "on")
    if isinstance(node, yaml.ScalarNode):
        return {node.value}
    if isinstance(node, yaml.SequenceNode):
        return {scalar(item) for item in node.value}
    if isinstance(node, yaml.MappingNode):
        return {key.value for key, _ in node.value}
    return set()


def is_release_only(text):
    """True for a workflow no PR check runs that holds release or store credentials."""
    root = compose(text)
    if triggers(root) & {"pull_request", "pull_request_target"}:
        return False
    if any(name != "GITHUB_TOKEN" for name in SECRET_REF.findall(text)):
        return True
    return any(child(job, "environment") is not None for job in items(child(root, "jobs")))


def parse_diff(text):
    """Hunks of a `git diff --unified=0` as {head path: [(base_start, base_count, head_start, head_count)]}."""
    hunks, base_path, path = {}, None, None
    for line in text.splitlines():
        if line.startswith("--- "):
            base_path = line[6:] if line.startswith("--- a/") else None
        elif line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else base_path
            hunks.setdefault(path, [])
        elif path is not None:
            match = HUNK.match(line)
            if match:
                a, b, c, d = match.groups()
                hunks[path].append((int(a), int(b or 1), int(c), int(d or 1)))
    return hunks


def last_line(node, lines):
    """The 1-based last line of a node's own text, without trailing blank or comment lines."""
    end = node.end_mark
    before = lines[end.line][:end.column] if end.line < len(lines) else ""
    last = end.line if not before.strip() else end.line + 1
    while last > line_of(node) and (not lines[last - 1].strip() or lines[last - 1].strip().startswith("#")):
        last -= 1
    return last


def step_name(step):
    run = (scalar(child(step, "run")) or "").strip().splitlines()
    return scalar(child(step, "name")) or scalar(child(step, "uses")) or (run[0] if run else "?")


def job_steps(text):
    """[(job id, line of its `steps:` key, [(name, first line, last line)])] for a workflow."""
    root, lines = compose(text), text.splitlines()
    jobs = child(root, "jobs")
    found = []
    for key, job in (jobs.value if isinstance(jobs, yaml.MappingNode) else []):
        steps_key = next((k for k, _ in (job.value if isinstance(job, yaml.MappingNode) else [])
                          if k.value == "steps"), None)
        spans = [(step_name(s), line_of(s), last_line(s, lines)) for s in items(child(job, "steps"))]
        found.append((key.value, line_of(steps_key) if steps_key else line_of(job), spans))
    return found


def job_settings(text):
    """{job id: (first line, last line, steps first line, steps last line)}: a job's own lines
    are the first..last span outside the steps span (runner, env, defaults, environment)."""
    root, lines = compose(text), text.splitlines()
    jobs = child(root, "jobs")
    found = {}
    for key, job in (jobs.value if isinstance(jobs, yaml.MappingNode) else []):
        steps_key = next((k for k, _ in (job.value if isinstance(job, yaml.MappingNode) else [])
                          if k.value == "steps"), None)
        steps = child(job, "steps")
        span = (line_of(steps_key), last_line(steps, lines)) if steps_key and steps is not None else (0, -1)
        found[key.value] = (line_of(key), last_line(job, lines)) + span
    return found


def settings_job(jobs, lines, line):
    """The job whose own settings hold this line, or None (a step, a blank or comment line, or no job)."""
    text = lines[line - 1].strip() if 0 < line <= len(lines) else ""
    if not text or text.startswith("#"):
        return None
    for job, (first, last, steps_first, steps_last) in jobs.items():
        if first <= line <= last and not steps_first <= line <= steps_last:
            return job
    return None


def step_warnings(path, base_text, head_text, hunks):
    """release_only_step_changed findings for the steps of one workflow that the hunks touch."""
    head_jobs = job_steps(head_text)
    base_jobs = job_steps(base_text) if base_text else []
    warned = {}  # (job, step name, first line) -> line of the warning
    head_settings, head_lines = job_settings(head_text), head_text.splitlines()
    base_settings = job_settings(base_text) if base_text else {}
    base_lines = base_text.splitlines() if base_text else []

    for a, b, c, d in hunks:
        for line in range(c, c + d):
            job = settings_job(head_settings, head_lines, line)
            if job is not None:
                warned.setdefault((job, None, "job"), line)
        for line in range(a, a + b):
            job = settings_job(base_settings, base_lines, line)
            if job is not None:
                warned.setdefault((job, None, "job"), c + 1 if d == 0 else c)
        for line in range(c, c + d):
            for job, _, spans in head_jobs:
                for name, first, last in spans:
                    if first <= line <= last:
                        warned.setdefault((job, name, first), line)
        if not b:
            continue
        anchor = c + 1 if d == 0 else c
        for job, _, spans in base_jobs:
            head_job = next((j for j in head_jobs if j[0] == job), None)
            for name, first, last in spans:
                if a <= first and last < a + b:  # the whole step is gone from the head
                    later = [f for _, f, _ in head_job[2] if f >= anchor] if head_job else []
                    line = later[0] if later else (head_job[1] if head_job else anchor)
                    warned.setdefault((job, name, "deleted"), line)
                elif first <= a + b - 1 and a <= last:  # lines deleted inside a step
                    head = next((s for s in head_job[2] if s[0] == name), None) if head_job else None
                    if head:
                        warned.setdefault((job, name, head[1]), min(max(c, head[1]), head[2]))

    return [Finding("warning", RELEASE_ONLY, path, line,
                    "{}: no PR check runs job '{}'; its settings run next to release or store credentials "
                    "in '{}'. {}".format(RELEASE_ONLY, job, path, PRE_MERGE_RUN) if name is None else
                    "{}: no PR check runs step '{}'; it runs next to release or store credentials in "
                    "'{}'. {}".format(RELEASE_ONLY, name, path, PRE_MERGE_RUN))
            for (job, name, _), line in sorted(warned.items(), key=lambda item: item[1])]


def diff_findings(changed):
    """Warnings for {path: (base_text or None, head_text, hunks)}: release-only steps, .xcode-version."""
    findings = []
    for path, (base_text, head_text, hunks) in sorted(changed.items()):
        if path == XCODE_VERSION_FILE:
            findings.append(Finding(
                "warning", TOOLCHAIN, path, 1,
                "{}: '{}' changed; the release workflows build with it next to release or store "
                "credentials, and no PR check runs them. Run them by hand on this commit before "
                "merging (TestFlight: internal-only upload; schema: dry run).".format(TOOLCHAIN, path)))
            continue
        if not path.startswith(".github/workflows/"):
            continue
        if base_text is not None:
            try:
                compose(base_text)
            except ParseError:
                base_text = None  # a base that does not parse is what this pull request may repair
        if head_text is None:
            if base_text is not None and is_release_only(base_text):
                findings.append(Finding(
                    "warning", RELEASE_ONLY, path, 1,
                    "{}: '{}' is deleted; it held release or store credentials and no PR check runs it. "
                    "Confirm the release pipeline is meant to lose it.".format(RELEASE_ONLY, path)))
        elif is_release_only(head_text) or (base_text is not None and is_release_only(base_text)):
            findings += step_warnings(path, base_text, head_text, hunks)
    return findings


EXPRESSION = re.compile(r"\$\{\{.*?\}\}")


def shellcheck_findings(path, text):
    """workflow_lint.shellcheck findings for the bash run: blocks of a composite action."""
    root = compose(text)
    if scalar(child(child(root, "runs"), "using")) != "composite":
        return []
    findings = []
    for step in items(child(child(root, "runs"), "steps")):
        run = child(step, "run")
        shell = (scalar(child(step, "shell")) or "bash").split()[0]
        if run is None or shell not in ("bash", "sh"):
            continue
        # A block scalar's text starts on the line after `run: |`.
        first = line_of(run) + (1 if run.style in ("|", ">") else 0)
        # Like actionlint: blank out ${{ }} expressions, keeping the columns.
        script = EXPRESSION.sub(lambda m: "_" * len(m.group()), run.value)
        result = subprocess.run(
            ["shellcheck", "--severity=warning", "--shell=" + shell, "--format=json1", "-"],
            input=script, capture_output=True, text=True)
        if result.returncode not in (0, 1):
            raise ParseError("shellcheck failed on {}: {}".format(path, result.stderr.strip()))
        for comment in json.loads(result.stdout)["comments"]:
            findings.append(Finding(
                "error", SHELLCHECK, path, first + comment["line"] - 1,
                "{} SC{}: {}".format(SHELLCHECK, comment["code"], comment["message"])))
    return findings


def git(*args, root=ROOT):
    result = subprocess.run(["git", "-C", str(root)] + list(args), capture_output=True, text=True)
    if result.returncode != 0:
        raise ParseError("git {}: {}".format(" ".join(args), result.stderr.strip()))
    return result.stdout


def changed_files(base, root=ROOT):
    """{path: (base text or None, head text or None, hunks)} for the workflows and .xcode-version.

    Diffs `base` against HEAD directly, with no merge base: on a pull_request run HEAD is the
    merge commit and workflow-lint passes its first parent (HEAD^1, in the depth-2 checkout).
    """
    diff = git("diff", "--unified=0", "--no-color", "--no-ext-diff", "--no-renames",
               "--src-prefix=a/", "--dst-prefix=b/", base, "HEAD",
               "--", ".github/workflows", XCODE_VERSION_FILE, root=root)
    changed = {}
    for path, hunks in parse_diff(diff).items():
        try:
            base_text = git("show", "{}:{}".format(base, path), root=root)
        except ParseError:
            base_text = None
        head_file = root / path
        changed[path] = (base_text, head_file.read_text(encoding="utf-8") if head_file.exists() else None, hunks)
    return changed


WORKFLOW_FIXTURE = """\
on: push
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
{steps}
"""

SHA = "0123456789abcdef" * 2 + "01234567"  # a full 40-hex commit
DIGEST = "sha256:" + "a" * 64

SELF_TEST_FIXTURES = [
    # (name, path, file text, expected [(code, line, text the message must contain)])
    ("version tag", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - name: Cache\n        uses: actions/cache@v5"),
     [(UNPINNED, 7, "{}: step 'Cache' uses 'actions/cache@v5'. Rule: every step from another "
                    "repository is a pinned step (a full 40-hex commit, or a sha256 image "
                    "digest).".format(UNPINNED))]),
    ("branch", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: owner/tool@main"),
     [(UNPINNED, 6, "step 'owner/tool@main' uses 'owner/tool@main'")]),
    ("short SHA", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: owner/tool@0123456"),
     [(UNPINNED, 6, "uses 'owner/tool@0123456'")]),
    ("no ref", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: owner/tool"),
     [(UNPINNED, 6, "uses 'owner/tool'")]),
    ("full SHA with tag comment", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: owner/repo/path@{} # v4".format(SHA)),
     []),
    ("docker tag", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: docker://alpine:3.20"),
     [(UNPINNED, 6, "uses 'docker://alpine:3.20'")]),
    ("docker digest", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: docker://alpine@{}".format(DIGEST)),
     []),
    ("local action", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: ./.github/actions/select-xcode"),
     []),
    ("reusable workflow at a tag", ".github/workflows/w.yml",
     "on: push\njobs:\n  call:\n    uses: owner/repo/.github/workflows/x.yml@v1\n",
     [(UNPINNED, 4, "step 'owner/repo/.github/workflows/x.yml@v1'")]),
    ("checkout without with", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - name: Check out\n        uses: actions/checkout@" + SHA),
     [(CHECKOUT, 6, "{}: checkout step 'Check out' leaves the repository credential in the "
                    "workspace. Rule: a checkout must set persist-credentials: false.".format(CHECKOUT))]),
    ("checkout persist-credentials true", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: actions/checkout@" + SHA + "\n        with:\n"
                                   "          persist-credentials: true"),
     [(CHECKOUT, 6, "checkout step 'actions/checkout@" + SHA + "'")]),
    ("checkout persist-credentials false", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: actions/checkout@" + SHA + "\n        with:\n"
                                   "          persist-credentials: false"),
     []),
    ("unpinned checkout gets both", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: actions/checkout@v4"),
     [(UNPINNED, 6, "actions/checkout@v4"), (CHECKOUT, 6, "actions/checkout@v4")]),
    ("composite action", ".github/actions/a/action.yml",
     "name: a\nruns:\n  using: composite\n  steps:\n    - uses: actions/cache@v5\n",
     [(UNPINNED, 5, "actions/cache@v5")]),
    ("mixed-case checkout without with", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: Actions/Checkout@" + SHA),
     [(CHECKOUT, 6, "checkout step 'Actions/Checkout@" + SHA + "'")]),
    ("mixed-case checkout persist-credentials false", ".github/workflows/w.yml",
     WORKFLOW_FIXTURE.format(steps="      - uses: ACTIONS/checkout@" + SHA + "\n        with:\n"
                                   "          persist-credentials: false"),
     []),
    ("mixed-case checkout in a composite action", ".github/actions/a/action.yml",
     "name: a\nruns:\n  using: composite\n  steps:\n    - uses: actions/CHECKOUT@" + SHA + "\n",
     [(CHECKOUT, 5, "checkout step 'actions/CHECKOUT@" + SHA + "'")]),
]


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
      # a comment between steps
      - name: Upload
        run: upload --key "$KEY"
        env:
          KEY: ${{ secrets.ASC_KEY }}
      - name: Tag
        run: git tag v1
"""

RELEASE_JOB_ENV = RELEASE_WORKFLOW.replace(
    "    environment: testflight\n",
    "    environment: testflight\n    env:\n      FASTLANE_VERSION: 2.228.0\n", 1)

DUPLICATE_KEY_FIXTURES = [
    # (name, path, file text) — each must raise ParseError
    ("duplicate with: in an action step", ".github/actions/a/action.yml",
     "runs:\n  using: composite\n  steps:\n"
     "    - uses: actions/checkout@{0}\n      with:\n        persist-credentials: false\n"
     "      with:\n        persist-credentials: true\n".format(SHA)),
    ("duplicate on:", ".github/workflows/w.yml",
     "on: workflow_dispatch\non: pull_request\njobs:\n  build:\n    runs-on: ubuntu-24.04\n"
     "    steps:\n      - run: echo\n"),
]

CLASSIFIER_FIXTURES = [
    # (name, workflow text, release-only?)
    ("dispatch + environment", "on: workflow_dispatch\njobs:\n  r:\n    environment: prod\n"
                               "    runs-on: macos-15\n    steps:\n      - run: x\n", True),
    ("dispatch + store secret", "on: [workflow_dispatch, push]\njobs:\n  r:\n    runs-on: x\n"
                                "    steps:\n      - run: echo ${{ secrets.ASC_KEY }}\n", True),
    ("pull_request + secret", "on:\n  pull_request:\n  workflow_dispatch:\njobs:\n  r:\n"
                              "    runs-on: x\n    steps:\n      - run: echo ${{ secrets.ASC_KEY }}\n", False),
    ("pull_request_target", "on: pull_request_target\njobs:\n  r:\n    environment: prod\n"
                            "    runs-on: x\n    steps:\n      - run: x\n", False),
    ("dispatch + GITHUB_TOKEN only", "on: workflow_dispatch\njobs:\n  r:\n    runs-on: x\n"
                                     "    steps:\n      - run: echo ${{ secrets.GITHUB_TOKEN }}\n", False),
]

DIFF_FIXTURE = """\
diff --git a/.github/workflows/release.yml b/.github/workflows/release.yml
index 1111111..2222222 100644
--- a/.github/workflows/release.yml
+++ b/.github/workflows/release.yml
@@ -12 +12 @@ jobs:
-          make build
+          make build ARCHS=arm64
@@ -20,0 +21,2 @@ jobs:
+        with:
+          retries: 2
diff --git a/.xcode-version b/.xcode-version
new file mode 100644
--- /dev/null
+++ b/.xcode-version
@@ -0,0 +1 @@
+26.6
"""


def edit(text, old, new):
    assert old in text, old
    return text.replace(old, new, 1)


STEP_FIXTURES = [
    # (name, base text, head text, hunks, expected [(line, text the message must contain)])
    ("edited run line", RELEASE_WORKFLOW, edit(RELEASE_WORKFLOW, "make build", "make build ARCHS=arm64"),
     [(11, 1, 11, 1)],
     [(11, "{}: no PR check runs step 'Build'; it runs next to release or store credentials in "
           "'.github/workflows/release.yml'. {}".format(RELEASE_ONLY, PRE_MERGE_RUN))]),
    ("two lines in one step", RELEASE_WORKFLOW,
     edit(RELEASE_WORKFLOW, "run: upload --key \"$KEY\"\n        env:\n          KEY:",
          "run: upload -v --key \"$KEY\"\n        env:\n          KEY2:"),
     [(14, 1, 14, 1), (16, 1, 16, 1)], [(14, "step 'Upload'")]),
    ("comment between steps", RELEASE_WORKFLOW,
     edit(RELEASE_WORKFLOW, "# a comment between steps", "# another comment"), [(12, 1, 12, 1)], []),
    ("on: block", RELEASE_WORKFLOW, edit(RELEASE_WORKFLOW, "  workflow_dispatch:", "  workflow_dispatch: {}"),
     [(2, 1, 2, 1)], []),
    ("deleted step", RELEASE_WORKFLOW,
     edit(RELEASE_WORKFLOW, "      - name: Upload\n        run: upload --key \"$KEY\"\n        env:\n"
                            "          KEY: ${{ secrets.ASC_KEY }}\n", ""),
     [(13, 4, 12, 0)], [(13, "step 'Upload'")]),
    ("deleted last step", RELEASE_WORKFLOW,
     edit(RELEASE_WORKFLOW, "      - name: Tag\n        run: git tag v1\n", ""),
     [(17, 2, 16, 0)], [(7, "step 'Tag'")]),
    ("new step", RELEASE_WORKFLOW, edit(RELEASE_WORKFLOW, "      - name: Tag\n", "      - name: Lint\n"
                                        "        run: lint\n      - name: Tag\n"),
     [(16, 0, 17, 2)], [(17, "step 'Lint'")]),
    ("line deleted inside a step",
     edit(RELEASE_WORKFLOW, "      - name: Upload\n", "      - name: Upload\n        if: inputs.channel == 'external'\n"),
     RELEASE_WORKFLOW, [(14, 1, 13, 0)], [(13, "step 'Upload'")]),
    ("edited job runner", RELEASE_WORKFLOW, edit(RELEASE_WORKFLOW, "macos-15", "macos-26"), [(5, 1, 5, 1)],
     [(5, "{}: no PR check runs job 'release'; its settings run next to release or store credentials in "
          "'.github/workflows/release.yml'. {}".format(RELEASE_ONLY, PRE_MERGE_RUN))]),
    ("edited job env", RELEASE_JOB_ENV, edit(RELEASE_JOB_ENV, "2.228.0", "2.229.0"), [(8, 1, 8, 1)],
     [(8, "job 'release'")]),
    ("deleted job env", RELEASE_JOB_ENV, RELEASE_WORKFLOW, [(7, 2, 6, 0)], [(7, "job 'release'")]),
    ("job runner and a step", RELEASE_WORKFLOW,
     edit(edit(RELEASE_WORKFLOW, "macos-15", "macos-26"), "make build", "make build ARCHS=arm64"),
     [(5, 1, 5, 1), (11, 1, 11, 1)], [(5, "job 'release'"), (11, "step 'Build'")]),
]


COMPOSITE_FIXTURE = """\
name: a
runs:
  using: composite
  steps:
    - name: Go
      shell: bash
      run: |
        set -euo pipefail
        export SHA=$(git rev-parse HEAD)
        echo "${{ inputs.app-path }}" "$SHA"
    - name: Style and info only
      shell: bash
      run: |
        when=`date`
        echo $1 "$when"
    - name: Not shell
      shell: pwsh
      run: cd foo
"""


def self_test_shellcheck():
    """Failures in the composite-action shellcheck fixture; None when shellcheck is absent locally."""
    if not shutil.which("shellcheck"):
        if os.environ.get("CI"):
            print("FAIL shellcheck: not installed")
            return 1
        print("SKIP shellcheck fixture: shellcheck is not installed (CI fails here)")
        return None
    found = [(f.code, f.line, f.message.split(":")[0]) for f in
             shellcheck_findings(".github/actions/a/action.yml", COMPOSITE_FIXTURE)]
    want = [(SHELLCHECK, 9, SHELLCHECK + " SC2155")]
    if found != want:
        print("FAIL shellcheck: expected {}, got {}".format(want, found))
        return 1
    return 0


POLICY_TREE = [
    # (path under the root, read by the policy script?)
    (".github/workflows/a.yml", True),
    (".github/workflows/b.yaml", True),
    (".github/workflows/sub/c.yml", False),  # GitHub runs only top-level workflow files
    (".github/workflows/notes.md", False),
    (".github/actions/x/action.yml", True),
    (".github/actions/y/action.yaml", True),
    (".github/actions/group/z/action.yml", True),
    (".github/actions/x/helper.yml", False),
]


def self_test_policy_files():
    """1 when policy_files misses or over-reads a file of POLICY_TREE, else 0."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, _ in POLICY_TREE:
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text("on: push\n", encoding="utf-8")
        found = sorted(path.relative_to(root).as_posix() for path in policy_files(root))
    want = sorted(rel for rel, read in POLICY_TREE if read)
    if found != want:
        print("FAIL policy_files: expected {}, got {}".format(want, found))
        return 1
    return 0


def self_test_renamed_workflow():
    """1 when a release-only workflow renamed with a step deleted loses its warnings, else 0."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        workflows = root / ".github/workflows"
        workflows.mkdir(parents=True)

        def commit(message):
            git("add", "-A", root=root)
            git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", message, root=root)

        git("init", "-q", root=root)
        (workflows / "release.yml").write_text(RELEASE_WORKFLOW, encoding="utf-8")
        commit("base")
        (workflows / "release.yml").unlink()
        (workflows / "testflight.yml").write_text(
            edit(RELEASE_WORKFLOW, "      - name: Tag\n        run: git tag v1\n", ""), encoding="utf-8")
        commit("rename")
        found = [(f.path, f.line, f.message.split(";")[0]) for f in diff_findings(changed_files("HEAD~1", root))]
    want = [(".github/workflows/release.yml", 1, "{}: '.github/workflows/release.yml' is deleted".format(RELEASE_ONLY)),
            (".github/workflows/testflight.yml", 4, "{}: no PR check runs job 'release'".format(RELEASE_ONLY)),
            (".github/workflows/testflight.yml", 8, "{}: no PR check runs step 'Build'".format(RELEASE_ONLY)),
            (".github/workflows/testflight.yml", 13, "{}: no PR check runs step 'Upload'".format(RELEASE_ONLY))]
    if found != want:
        print("FAIL renamed workflow: expected {}, got {}".format(want, found))
        return 1
    return 0


def self_test_noprefix():
    """1 when a local `diff.noprefix=true` setting breaks the diff warnings, else 0."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        workflows = root / ".github/workflows"
        workflows.mkdir(parents=True)

        def commit(message):
            git("add", "-A", root=root)
            git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", message, root=root)

        git("init", "-q", root=root)
        git("config", "diff.noprefix", "true", root=root)
        (workflows / "release.yml").write_text(RELEASE_WORKFLOW, encoding="utf-8")
        commit("base")
        (workflows / "release.yml").write_text(
            edit(RELEASE_WORKFLOW, "make build", "make build ARCHS=arm64"), encoding="utf-8")
        commit("edit")
        try:
            found = [(f.path, f.line, f.message.split(";")[0])
                     for f in diff_findings(changed_files("HEAD~1", root))]
        except Exception as error:  # the failure this test guards is a crash
            found = "{}: {}".format(type(error).__name__, error)
    want = [(".github/workflows/release.yml", 11, "{}: no PR check runs step 'Build'".format(RELEASE_ONLY))]
    if found != want:
        print("FAIL diff.noprefix=true: expected {}, got {}".format(want, found))
        return 1
    return 0


def self_test_summary():
    """1 when the summary of a pull request run without warnings claims more than the check covers."""
    with tempfile.TemporaryDirectory() as folder:
        summary = Path(folder) / "summary.md"
        os.environ["GITHUB_STEP_SUMMARY"] = str(summary)
        try:
            write_summary([], "origin/develop")
        finally:
            del os.environ["GITHUB_STEP_SUMMARY"]
        text = summary.read_text(encoding="utf-8")
    want = ("No release-only step or job changes, release-only workflow deletions or "
            ".xcode-version changes detected.")
    if want not in text:
        print("FAIL summary without warnings: expected {!r}, got {!r}".format(want, text))
        return 1
    return 0


def self_test():
    failures = self_test_policy_files() + self_test_renamed_workflow()
    shellcheck_result = self_test_shellcheck()
    failures += shellcheck_result or 0
    for name, text, want in CLASSIFIER_FIXTURES:
        if is_release_only(text) != want:
            failures += 1
            print("FAIL classifier {}: expected release-only={}".format(name, want))
    for name, base, head, hunks, expected in STEP_FIXTURES:
        found = [(f.line, f.message) for f in step_warnings(".github/workflows/release.yml", base, head, hunks)]
        ok = len(found) == len(expected) and all(
            line == want_line and want_text in message
            for (line, message), (want_line, want_text) in zip(found, expected))
        if not ok:
            failures += 1
            print("FAIL steps {}: expected {}, got {}".format(name, expected, found))
    parsed = parse_diff(DIFF_FIXTURE)
    want_parsed = {".github/workflows/release.yml": [(12, 1, 12, 1), (20, 0, 21, 2)],
                   ".xcode-version": [(0, 0, 1, 1)]}
    if parsed != want_parsed:
        failures += 1
        print("FAIL parse_diff: expected {}, got {}".format(want_parsed, parsed))
    toolchain = [(f.level, f.code, f.path, f.line, f.message) for f in diff_findings(
        {".xcode-version": (None, "26.6\n", [(0, 0, 1, 1)]),
         ".github/workflows/unit-tests.yml": (WORKFLOW_FIXTURE.format(steps="      - run: a"),
                                              WORKFLOW_FIXTURE.format(steps="      - run: b"),
                                              [(6, 1, 6, 1)])})]
    if toolchain != [("warning", TOOLCHAIN, ".xcode-version", 1,
                      "{}: '.xcode-version' changed; the release workflows build with it next to release or "
                      "store credentials, and no PR check runs them. {}".format(
                          TOOLCHAIN, PRE_MERGE_RUN.replace("that workflow", "them")))]:
        failures += 1
        print("FAIL diff_findings: expected one {} warning, got {}".format(TOOLCHAIN, toolchain))
    deleted = [(f.level, f.code, f.path, f.line, f.message) for f in diff_findings(
        {".github/workflows/release.yml": (CLASSIFIER_FIXTURES[0][1], None, [(1, 7, 0, 0)]),
         ".github/workflows/lint.yml": (WORKFLOW_FIXTURE.format(steps="      - run: a"), None, [(1, 6, 0, 0)])})]
    if deleted != [("warning", RELEASE_ONLY, ".github/workflows/release.yml", 1,
                    "{}: '.github/workflows/release.yml' is deleted; it held release or store credentials "
                    "and no PR check runs it. Confirm the release pipeline is meant to lose it.".format(
                        RELEASE_ONLY))]:
        failures += 1
        print("FAIL deleted workflow: expected one {} warning for release.yml, got {}".format(RELEASE_ONLY, deleted))
    unmarked = edit(edit(RELEASE_WORKFLOW, "    environment: testflight\n", ""),
                    "      - name: Upload\n        run: upload --key \"$KEY\"\n        env:\n"
                    "          KEY: ${{ secrets.ASC_KEY }}\n", "")
    unmarked_found = [(f.path, f.line, f.message.split(";")[0]) for f in diff_findings(
        {".github/workflows/release.yml": (RELEASE_WORKFLOW, unmarked, [(6, 1, 5, 0), (13, 4, 11, 0)])})]
    if unmarked_found != [(".github/workflows/release.yml", 6, "{}: no PR check runs job 'release'".format(RELEASE_ONLY)),
                          (".github/workflows/release.yml", 12,
                           "{}: no PR check runs step 'Upload'".format(RELEASE_ONLY))]:
        failures += 1
        print("FAIL last release markers removed: expected {} warnings for job 'release' and 'Upload', got {}".format(
            RELEASE_ONLY, unmarked_found))
    try:
        unparsable_base = [(f.path, f.line, f.message.split(";")[0]) for f in diff_findings(
            {".github/workflows/release.yml": ("jobs:\n  a: [\n",
                                               edit(RELEASE_WORKFLOW, "make build", "make build ARCHS=arm64"),
                                               [(1, 2, 11, 1)])})]
    except ParseError as error:
        unparsable_base = "ParseError: {}".format(error)
    if unparsable_base != [(".github/workflows/release.yml", 11,
                            "{}: no PR check runs step 'Build'".format(RELEASE_ONLY))]:
        failures += 1
        print("FAIL base that does not parse: expected one {} warning for 'Build', got {}".format(
            RELEASE_ONLY, unparsable_base))
    failures += self_test_summary() + self_test_noprefix()
    expected_total = len(CLASSIFIER_FIXTURES) + len(STEP_FIXTURES) + 7 + (shellcheck_result is not None)
    for name, path, text, expected in SELF_TEST_FIXTURES:
        found = [(f.code, f.line, f.message) for f in check_file(path, text)]
        ok = len(found) == len(expected) and all(
            code == want_code and line == want_line and want_text in message
            for (code, line, message), (want_code, want_line, want_text) in zip(found, expected))
        if not ok:
            failures += 1
            print("FAIL {}: expected {}, got {}".format(name, expected, found))
    try:
        check_file(".github/workflows/bad.yml", "jobs: [unclosed\n")
        failures += 1
        print("FAIL malformed YAML: expected a parse error, got none")
    except ParseError:
        pass
    for name, path, text in DUPLICATE_KEY_FIXTURES:
        try:
            check_file(path, text)
            failures += 1
            print("FAIL {}: expected a parse error, got none".format(name))
        except ParseError:
            pass
    total = len(SELF_TEST_FIXTURES) + 3 + expected_total + len(DUPLICATE_KEY_FIXTURES)
    if failures:
        print("\n{}/{} fixtures failed".format(failures, total))
        return 1
    print("All {} fixtures pass".format(total))
    return 0


def policy_files(root):
    workflows = [p for p in (root / ".github/workflows").glob("*") if p.suffix in (".yml", ".yaml")]
    actions = [p for p in (root / ".github/actions").rglob("*") if p.name in ACTION_FILES]
    return sorted(workflows) + sorted(actions)


def write_summary(findings, base):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    counts = {}
    for finding in findings:
        counts[finding.code] = counts.get(finding.code, 0) + 1
    lines = ["### Workflow policy", ""]
    if counts:
        lines += ["- `{}`: {}".format(code, count) for code, count in sorted(counts.items())]
    else:
        lines.append("No workflow policy findings.")
    lines.append("")
    warnings = [f for f in findings if f.code in (RELEASE_ONLY, TOOLCHAIN)]
    if base is None:
        lines.append("Release-only changes: not checked (no pull request base).")
    elif warnings:
        lines += ["#### Release-only changes", ""]
        lines += ["- `{}:{}` {}".format(f.path, f.line, f.message) for f in warnings]
    else:
        lines.append("No release-only step or job changes, release-only workflow deletions or "
                     ".xcode-version changes detected.")
    with open(path, "a", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n\n")


def main(argv):
    parser = argparse.ArgumentParser(description="Check the GitHub Actions policy.")
    parser.add_argument("--base", metavar="REV", help="pull request base for the diff-based warnings")
    parser.add_argument("--self-test", action="store_true", help="run the fixtures and exit")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()

    findings = []
    for path in policy_files(ROOT):
        rel = path.relative_to(ROOT).as_posix()
        try:
            text = path.read_text(encoding="utf-8")
            findings += check_file(rel, text)
            if path.name in ACTION_FILES:
                if not shutil.which("shellcheck"):
                    print("::error::shellcheck is not installed; it checks {}".format(rel))
                    return 2
                findings += shellcheck_findings(rel, text)
        except ParseError as error:
            print("::error file={}::cannot parse: {}".format(rel, error))
            return 2
    if args.base:
        try:
            findings += diff_findings(changed_files(args.base))
        except (ParseError, yaml.YAMLError) as error:
            print("::error::cannot compare with --base {}: {}".format(args.base, error))
            return 2
    for finding in findings:
        print("::{} file={},line={}::{}".format(finding.level, finding.path, finding.line, finding.message))
    write_summary(findings, args.base)
    return 1 if any(f.level == "error" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

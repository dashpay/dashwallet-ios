#!/usr/bin/env python3
"""Fail the test check when the run executed no non-skipped test.

Reads the JSON of `xcrun xcresulttool get test-results summary --path <bundle>`
and counts executed non-skipped tests as totalTestCount - skippedTests. A run
that found no test, or skipped every test it found, is an empty test run: the
test step went green, but nothing was checked.

    check_test_count.py <summary.json>
    check_test_count.py --self-test

Exit codes: 0 at least one executed test; 1 empty test run; 2 missing or
unreadable summary. Stdlib only.
"""

import json
import os
import sys

EMPTY_RUN = "test_count.empty_test_run"
RULE = "a passing test check needs at least one executed, non-skipped test"


def evaluate(text):
    """Return (exit_code, output_line, summary_line) for a summary JSON text."""
    try:
        summary = json.loads(text)
        total = summary["totalTestCount"]
        skipped = summary["skippedTests"]
    except ValueError:
        return 2, "::error::missing or unreadable summary: not JSON", None
    except (KeyError, TypeError) as error:
        return 2, "::error::missing or unreadable summary: no field {}".format(error), None
    if not all(isinstance(value, int) for value in (total, skipped)):
        return 2, "::error::missing or unreadable summary: non-integer test counts", None
    executed = total - skipped
    line = "Executed tests: {} ({} skipped)".format(executed, skipped)
    if executed > 0:
        return 0, line, line
    return 1, ("::error::{}: the test run executed 0 non-skipped tests ({} found, {} skipped). "
               "Rule: {}.".format(EMPTY_RUN, total, skipped, RULE)), line


SELF_TEST_FIXTURES = [
    # (name, summary JSON text, expected exit code, text the output must contain)
    ("normal run",
     json.dumps({"totalTestCount": 412, "skippedTests": 3, "passedTests": 409}),
     0, "Executed tests: 409 (3 skipped)"),
    ("zero tests",
     json.dumps({"totalTestCount": 0, "skippedTests": 0, "passedTests": 0}),
     1, "::error::{}: the test run executed 0 non-skipped tests (0 found, 0 skipped). "
        "Rule: {}.".format(EMPTY_RUN, RULE)),
    ("all skipped",
     json.dumps({"totalTestCount": 7, "skippedTests": 7, "passedTests": 0}),
     1, "::error::{}: the test run executed 0 non-skipped tests (7 found, 7 skipped). "
        "Rule: {}.".format(EMPTY_RUN, RULE)),
    ("not JSON", "xcresulttool: error: bundle not found", 2, "unreadable"),
    ("field missing", json.dumps({"skippedTests": 0}), 2, "totalTestCount"),
]


def self_test():
    failures = 0
    for name, text, want_code, want_text in SELF_TEST_FIXTURES:
        code, output, _ = evaluate(text)
        if code != want_code or want_text not in output:
            failures += 1
            print("FAIL {}: expected exit {} with {!r}, got exit {} with {!r}".format(
                name, want_code, want_text, code, output))
    if failures:
        print("\n{}/{} fixtures failed".format(failures, len(SELF_TEST_FIXTURES)))
        return 1
    print("All {} fixtures pass".format(len(SELF_TEST_FIXTURES)))
    return 0


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    if len(argv) != 1 or argv[0].startswith("-"):
        print("usage: check_test_count.py <summary.json> | --self-test", file=sys.stderr)
        return 2
    try:
        with open(argv[0], encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        print("::error::missing or unreadable summary {}: {}".format(argv[0], error.strerror))
        return 2
    code, output, summary = evaluate(text)
    print(output)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary and summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(summary + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

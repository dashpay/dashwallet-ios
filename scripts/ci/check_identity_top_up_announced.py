#!/usr/bin/env python3
"""Fail when an identity top-up in the app is not announced as the wallet's own.

Every SDK call that adds credits to an identity must run inside
`IdentityTopUpDidComplete.announcing` (ADR-0034), in its argument list or its
trailing closure. The profile sheet's `IdentityTopUpViewModel.executeTopUp` path
is the other allowed place; its caller posts the event. A call that deliberately
goes unannounced carries `// top-up not announced: <reason>` on the line above
it. Without the event the Receive watcher sees the identity's credits rise and
shows the wallet's own top-up as «Received».

Scans the Swift files under DashWallet/Sources for calls of the top-up methods
below. Prints `<file>:<line>: <method> outside IdentityTopUpDidComplete.announcing`
per call outside an allowed place and exits 1 on any.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from check_no_old_swift_lookup import code_lines  # noqa: E402

SCANNED_DIR = os.path.join("DashWallet", "Sources")
# Every public SwiftDashSDK method that adds credits to an existing identity,
# deprecated spellings included.
TOP_UP_CALL = re.compile(
    r"\.(topUpIdentityWithFunding|topUpIdentityFromAddresses|topUpFromAddresses|"
    r"topUpExternalIdentityFromAddresses|resumeTopUpWithAssetLock|shieldedIdentityTopUpFromPool)\s*\("
)
# The explicit exception for one call, written on the line above it.
NOT_ANNOUNCED = re.compile(r"^\s*//\s*top-up not announced:\s*\S")
ANNOUNCING = re.compile(r"\bIdentityTopUpDidComplete\s*\.\s*announcing\s*\(")
# executeTopUp runs every route of the profile sheet's top-up (topUpFromShielded is
# its shielded leg); IdentityTopUpViewModel.topUp posts the event with its result.
ALLOWED_FUNCTIONS = {
    "SDKIdentityProfileSheet.swift": ("executeTopUp", "topUpFromShielded"),
}
PAIRS = {"(": ")", "{": "}"}


def matching(code, start):
    """Index just past the bracket that closes the one at `start`, or len(code)."""
    opener, closer, depth = code[start], PAIRS[code[start]], 0
    for i in range(start, len(code)):
        if code[i] == opener:
            depth += 1
        elif code[i] == closer:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(code)


def announcing_spans(code):
    """The argument list of each `announcing(` call, plus its trailing closure."""
    for match in ANNOUNCING.finditer(code):
        end = matching(code, match.end() - 1)
        rest = re.match(r"\s*\{", code[end:])
        if rest:
            end = matching(code, end + rest.end() - 1)
        yield match.start(), end


def function_spans(code, names):
    for name in names:
        for match in re.finditer(r"\bfunc\s+%s\b" % re.escape(name), code):
            brace = code.find("{", match.end())
            if brace != -1:
                yield match.start(), matching(code, brace)


def violations(root):
    base = os.path.join(root, SCANNED_DIR)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
            if not TOP_UP_CALL.search(text):
                continue
            raw = text.split("\n")
            code = "\n".join(line for _, line in code_lines(text))
            spans = list(announcing_spans(code))
            spans += list(function_spans(code, ALLOWED_FUNCTIONS.get(name, ())))
            rel = os.path.relpath(path, root)
            for call in TOP_UP_CALL.finditer(code):
                if any(start <= call.start() < end for start, end in spans):
                    continue
                line = code.count("\n", 0, call.start()) + 1
                if line >= 2 and NOT_ANNOUNCED.match(raw[line - 2]):
                    continue
                yield "%s:%d: %s outside IdentityTopUpDidComplete.announcing" % (rel, line, call.group(1))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    args = parser.parse_args(argv)
    hits = list(violations(args.root))
    for hit in hits:
        print(hit)
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""A Catalog key that Swift looks up only inside `#Preview` or `#if DEBUG` code is a `manual` entry.

The Xcode app does not extract strings from that code and marks such an entry stale after a build,
while the command-line sync phase keeps it; the two writers would disagree on every build. Neither
writer changes a `manual` entry (ADR-0071).
"""
import json
import os
import re
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCES = os.path.join(REPO, "DashWallet", "Sources")
CATALOG = os.path.join(REPO, "DashWallet", "Localizable.xcstrings")
LOOKUP = re.compile(r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"')


def lookups_by_region(text):
    """(keys looked up in debug-only code, keys looked up elsewhere) for one Swift file."""
    debug, other = set(), set()
    if_stack = []        # True for an `#if DEBUG` branch
    preview_depth = None  # brace depth at which the current #Preview started
    depth = 0
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if"):
            if_stack.append(stripped.split()[1:2] == ["DEBUG"])
        elif stripped.startswith("#else") or stripped.startswith("#elseif"):
            if if_stack:
                if_stack[-1] = False
        elif stripped.startswith("#endif"):
            if if_stack:
                if_stack.pop()
        if stripped.startswith("#Preview") and preview_depth is None:
            preview_depth = depth
        in_debug = any(if_stack) or preview_depth is not None
        for key in LOOKUP.findall(line):
            (debug if in_debug else other).add(key)
        depth += line.count("{") - line.count("}")
        if preview_depth is not None and depth <= preview_depth and "}" in line:
            preview_depth = None
    return debug, other


class PreviewOnlyKeysTests(unittest.TestCase):
    def test_debug_only_lookups_are_manual_entries(self):
        debug, other = set(), set()
        for root, _, files in os.walk(SOURCES):
            for name in files:
                if name.endswith(".swift"):
                    with open(os.path.join(root, name), encoding="utf-8") as f:
                        d, o = lookups_by_region(f.read())
                    debug |= d
                    other |= o
        with open(CATALOG, encoding="utf-8") as f:
            strings = json.load(f)["strings"]
        offenders = sorted(k for k in debug - other
                           if k in strings and strings[k].get("extractionState") != "manual")
        self.assertEqual(offenders, [], "looked up only in #Preview / #if DEBUG code but not manual")

    def test_the_scanner_tells_debug_code_from_release_code(self):
        source = ('let a = String(localized: "Shown")\n'
                  '#if DEBUG\nlet b = String(localized: "Debug only")\n#endif\n'
                  '#Preview("x") {\n    Text(String(localized: "Preview only"))\n}\n'
                  'let c = String(localized: "After")\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"Debug only", "Preview only"})
        self.assertEqual(other, {"Shown", "After"})


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""A Catalog key that the dashpay Debug build's sync cannot see is a `manual` entry.

- Swift looked up only inside `#Preview` or `#if DEBUG` code: the Xcode app does not extract
  strings from that code and marks such an entry stale after a build, while the command-line sync
  phase keeps it; the two writers would disagree on every build.
- Looked up only by the Today extension, which compiles the Catalog but has no sync phase, or only
  in Swift under `#if !DASHPAY`: the dashpay sync marks the entry stale, so it reads as an Unused
  entry while a target still shows it.

Neither writer changes a `manual` entry (ADR-0071).
"""
import json
import os
import re
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCES = os.path.join(REPO, "DashWallet", "Sources")
TODAY_SOURCES = os.path.join(REPO, "TodayExtension")
CATALOG = os.path.join(REPO, "DashWallet", "Localizable.xcstrings")
# `String(localized:)` and the SwiftUI initializers and modifiers whose first literal is a
# `LocalizedStringKey`; `Text(verbatim:)` and non-literal arguments are not lookups.
LOOKUP = re.compile(r'(?:String\(\s*localized:\s*'
                    r'|\b(?:Text|Button|Label|Toggle|Section|TextField|SecureField|Link|Picker|Menu'
                    r'|ContentUnavailableView|NavigationLink|ProgressView|Stepper|DatePicker'
                    r'|DisclosureGroup|LabeledContent|GroupBox|ColorPicker|LocalizedStringKey'
                    r'|navigationTitle|navigationSubtitle|alert|confirmationDialog|help)\(\s*)'
                    r'"((?:[^"\\]|\\.)*)"')
OBJC_LOOKUP = re.compile(r'NSLocalizedString\(\s*@"((?:[^"\\]|\\.)*)"')
# `#if` conditions whose branch the dashpay Debug sync does not see, and those whose `#else` it does not see.
UNSEEN_IF = {"DEBUG", "!DASHPAY"}
UNSEEN_ELSE = {"DASHPAY"}


def lookups_by_region(text):
    """(keys looked up in code the dashpay Debug sync does not see, keys looked up elsewhere) for one Swift file."""
    debug, other = set(), set()
    if_stack = []        # (condition, True while inside a branch the sync does not see)
    preview_depth = None  # brace depth at which the current #Preview started
    depth = 0
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if"):
            condition = "".join(stripped.split()[1:2])
            if_stack.append((condition, condition in UNSEEN_IF))
        elif stripped.startswith("#else") or stripped.startswith("#elseif"):
            if if_stack:
                condition = if_stack[-1][0]
                if_stack[-1] = (condition, stripped.startswith("#else") and condition in UNSEEN_ELSE)
        elif stripped.startswith("#endif"):
            if if_stack:
                if_stack.pop()
        if stripped.startswith("#Preview") and preview_depth is None:
            preview_depth = depth
        in_debug = any(unseen for _, unseen in if_stack) or preview_depth is not None
        for key in LOOKUP.findall(line):
            (debug if in_debug else other).add(key)
        depth += line.count("{") - line.count("}")
        if preview_depth is not None and depth <= preview_depth and "}" in line:
            preview_depth = None
    return debug, other


def scan(root):
    """(Swift keys in unseen code, Swift keys elsewhere, Objective-C keys) under `root`."""
    debug, other, objc = set(), set(), set()
    for directory, _, files in os.walk(root):
        for name in files:
            path = os.path.join(directory, name)
            if name.endswith(".swift"):
                with open(path, encoding="utf-8") as f:
                    d, o = lookups_by_region(f.read())
                debug |= d
                other |= o
            elif name.endswith(".m"):
                with open(path, encoding="utf-8") as f:
                    objc |= set(OBJC_LOOKUP.findall(f.read()))
    return debug, other, objc


def not_manual(keys):
    with open(CATALOG, encoding="utf-8") as f:
        strings = json.load(f)["strings"]
    return sorted(k for k in keys if k in strings and strings[k].get("extractionState") != "manual")


class PreviewOnlyKeysTests(unittest.TestCase):
    def test_debug_only_lookups_are_manual_entries(self):
        debug, other, objc = scan(SOURCES)
        self.assertEqual(not_manual(debug - other - objc), [],
                         "looked up only in #Preview / #if DEBUG / #if !DASHPAY code but not manual")

    def test_keys_only_the_today_extension_looks_up_are_manual_entries(self):
        _, other, objc = scan(SOURCES)
        today_debug, today_other, today_objc = scan(TODAY_SOURCES)
        today = today_debug | today_other | today_objc
        self.assertTrue(today, "no lookup found under TodayExtension")
        self.assertEqual(not_manual(today - other - objc), [],
                         "looked up only by the Today extension but not manual")

    def test_the_scanner_tells_dashpay_code_from_other_code(self):
        source = ('#if !DASHPAY\nlet a = String(localized: "Not dashpay")\n#else\n'
                  'let b = String(localized: "Dashpay one")\n#endif\n'
                  '#if DASHPAY\nlet c = String(localized: "Dashpay two")\n#else\n'
                  'let d = String(localized: "Not dashpay either")\n#endif\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"Not dashpay", "Not dashpay either"})
        self.assertEqual(other, {"Dashpay one", "Dashpay two"})

    def test_the_scanner_tells_debug_code_from_release_code(self):
        source = ('let a = String(localized: "Shown")\n'
                  '#if DEBUG\nlet b = String(localized: "Debug only")\n#endif\n'
                  '#Preview("x") {\n    Text(String(localized: "Preview only"))\n}\n'
                  'let c = String(localized: "After")\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"Debug only", "Preview only"})
        self.assertEqual(other, {"Shown", "After"})

    def test_the_scanner_sees_swiftui_literal_keys(self):
        source = ('Text("Shown text")\n'
                  '#Preview("x") {\n    Text("Preview text")\n    Button("Preview button") {}\n'
                  '    Label("Preview label", systemImage: "x")\n        .navigationTitle("Preview title")\n}\n'
                  'Text(verbatim: "Not a key")\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"Preview text", "Preview button", "Preview label", "Preview title"})
        self.assertEqual(other, {"Shown text"})

    def test_the_scanner_sees_the_other_swiftui_literal_keys(self):
        names = ["ContentUnavailableView", "NavigationLink", "ProgressView", "Stepper", "DatePicker",
                 "DisclosureGroup", "LabeledContent", "GroupBox", "ColorPicker"]
        modifiers = ["alert", "confirmationDialog", "help", "navigationSubtitle"]
        body = "".join(f'    {n}("{n} key")\n' for n in names)
        body += "".join(f'        .{m}("{m} key")\n' for m in modifiers)
        debug, other = lookups_by_region('#Preview("x") {\n' + body + "}\n")
        self.assertEqual(debug, {f"{n} key" for n in names + modifiers})
        self.assertEqual(other, set())


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""A Catalog key that the dashpay Debug build's sync cannot see is a `manual` entry.

- Swift looked up only inside `#Preview` or `#if DEBUG` code: the Xcode app does not extract
  strings from that code and marks such an entry stale after a build, while the command-line sync
  phase keeps it; the two writers would disagree on every build.
- Swift looked up only in a branch the dashpay Debug build does not compile (the `#else` of
  `#if DEBUG`, an undefined flag), and Objective-C looked up only under a positive `DEBUG`
  condition or `#if 0`: the sync marks the entry stale.
- Out of caution the scan also counts as unseen some code the sync may see: Swift in any other
  branch of an `#if` that names `DEBUG`, under a condition it cannot evaluate or in an `#elseif`
  branch, and Objective-C in any branch of a chain
  that names `DEBUG` other than a lone negative `DEBUG` branch or the `#else` of a lone positive one.
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
# Every directory with `.swift` / `.m` sources the dashpay target compiles.
DASHPAY_SOURCES = [os.path.join(REPO, name) for name in ("DashWallet", "DashPay", "Shared")]
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
# The dashpay Debug build's SWIFT_ACTIVE_COMPILATION_CONDITIONS.
DEBUG_BUILD_FLAGS = {"DEBUG", "PIGGYCARDS_ENABLED", "DASHPAY"}


def swift_branch_seen(condition, is_else):
    """True when the scan counts a Swift branch as seen: the dashpay Debug build compiles it and its condition
    does not name DEBUG (the Xcode app drops keys only `#if DEBUG` code looks up). A condition the scan cannot
    evaluate, or None for an `#elseif` chain, counts as unseen out of caution."""
    if condition is None or re.search(r"\bDEBUG\b", condition):
        return False
    flag = re.fullmatch(r"(!?)\s*(\w+)", condition)
    if not flag:
        return False
    compiled = (flag.group(2) in DEBUG_BUILD_FLAGS) != bool(flag.group(1))
    return compiled != is_else


def directive_condition(stripped, directive):
    return stripped[len(directive):].split("//")[0].strip()


def lookups_by_region(text):
    """(keys looked up in code the dashpay Debug sync does not see, keys looked up elsewhere) for one Swift file."""
    debug, other = set(), set()
    if_stack = []        # (condition, True while inside a branch the sync does not see)
    preview_depth = None  # brace depth at which the current #Preview started
    depth = 0
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if"):
            condition = directive_condition(stripped, "#if")
            if_stack.append((condition, not swift_branch_seen(condition, False)))
        elif stripped.startswith("#elseif"):
            if if_stack:
                if_stack[-1] = (None, True)
        elif stripped.startswith("#else"):
            if if_stack:
                condition = if_stack[-1][0]
                if_stack[-1] = (condition, not swift_branch_seen(condition, True))
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


OBJC_DIRECTIVE = re.compile(r"#\s*(ifdef|ifndef|if|elif|else|endif)\b(.*)")
LONE_DEBUG = re.compile(r"\(?\s*(!?)\s*(?:defined\s*\(\s*DEBUG\s*\)|defined\s+DEBUG|DEBUG)\s*\)?")


def objc_branch_seen(chain, is_else):
    """True when the scan counts an Objective-C branch as seen. `chain` holds the conditions of the `#if` and
    each `#elif` up to this branch (all of them for an `#else`). The sync marks stale a lookup under a positive
    DEBUG condition or `#if 0`; out of caution, a chain that names DEBUG is seen only in a lone negative DEBUG
    branch or in the `#else` of a lone positive one."""
    if not any(re.search(r"\bDEBUG\b", c) for c in chain):
        return is_else or chain[-1] != "0"
    lone = LONE_DEBUG.fullmatch(chain[0])
    return len(chain) == 1 and lone is not None and bool(lone.group(1)) != is_else


def objc_lookups_by_region(text):
    """(keys looked up only in branches the scan counts as unseen, keys looked up elsewhere) for one
    Objective-C file."""
    unseen_lines = set()
    stack = []  # (chain of conditions, True in the #else) of each open #if
    for number, line in enumerate(text.splitlines()):
        directive = OBJC_DIRECTIVE.match(line.strip())
        if directive:
            name = directive.group(1)
            condition = re.sub(r"/\*.*?\*/", " ", directive.group(2)).split("//")[0].strip()
            if name == "ifdef":
                stack.append(([condition], False))
            elif name == "ifndef":
                stack.append(([f"!{condition}"], False))
            elif name == "if":
                stack.append(([condition], False))
            elif name == "elif" and stack:
                stack[-1] = (stack[-1][0] + [condition], False)
            elif name == "else" and stack:
                stack[-1] = (stack[-1][0], True)
            elif name == "endif" and stack:
                stack.pop()
        if not all(objc_branch_seen(chain, is_else) for chain, is_else in stack):
            unseen_lines.add(number)
    unseen, seen = set(), set()
    for match in OBJC_LOOKUP.finditer(text):
        line = text.count("\n", 0, match.start())
        (unseen if line in unseen_lines else seen).add(match.group(1))
    return unseen, seen


def scan(roots):
    """(keys looked up only in code the scan counts as unseen, keys looked up elsewhere) under `roots`, Swift
    and Objective-C together."""
    unseen, seen = set(), set()
    for directory, _, files in (entry for root in roots for entry in os.walk(root)):
        for name in files:
            path = os.path.join(directory, name)
            if name.endswith(".swift"):
                regions = lookups_by_region
            elif name.endswith(".m"):
                regions = objc_lookups_by_region
            else:
                continue
            with open(path, encoding="utf-8") as f:
                u, s = regions(f.read())
            unseen |= u
            seen |= s
    return unseen, seen


def not_manual(keys):
    with open(CATALOG, encoding="utf-8") as f:
        strings = json.load(f)["strings"]
    return sorted(k for k in keys if k in strings and strings[k].get("extractionState") != "manual")


class PreviewOnlyKeysTests(unittest.TestCase):
    def test_debug_only_lookups_are_manual_entries(self):
        unseen, seen = scan(DASHPAY_SOURCES)
        self.assertEqual(not_manual(unseen - seen), [],
                         "looked up only in code the scan counts as unseen but not manual")

    def test_keys_only_the_today_extension_looks_up_are_manual_entries(self):
        _, seen = scan(DASHPAY_SOURCES)
        today = set().union(*scan([TODAY_SOURCES]))
        self.assertTrue(today, "no lookup found under TodayExtension")
        self.assertEqual(not_manual(today - seen), [],
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

    def test_both_branches_of_a_debug_condition_are_unseen(self):
        source = ('#if DEBUG\nlet a = String(localized: "Debug")\n#else\n'
                  'let b = String(localized: "Release banner")\n#endif\n'
                  '#if !DEBUG\nlet c = String(localized: "Not debug")\n#else\n'
                  'let d = String(localized: "Debug again")\n#endif\n'
                  '#if DEBUG || Testflight\nlet e = String(localized: "Debug or TestFlight")\n#else\n'
                  'let f = String(localized: "Neither")\n#endif\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"Debug", "Release banner", "Not debug", "Debug again",
                                 "Debug or TestFlight", "Neither"})
        self.assertEqual(other, set())

    def test_a_branch_the_dashpay_debug_build_does_not_compile_is_unseen(self):
        source = ('#if DASH_TESTNET\nlet a = String(localized: "Testnet")\n#else\n'
                  'let b = String(localized: "Not testnet")\n#endif\n'
                  '#if PIGGYCARDS_ENABLED\nlet c = String(localized: "Piggy")\n#else\n'
                  'let d = String(localized: "No piggy")\n#endif\n'
                  '#if !SNAPSHOT\nlet e = String(localized: "Not snapshot")\n#endif\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"Testnet", "No piggy"})
        self.assertEqual(other, {"Not testnet", "Piggy", "Not snapshot"})

    def test_a_condition_the_scan_cannot_evaluate_and_an_elseif_are_unseen(self):
        source = ('#if canImport(UIKit)\nlet a = String(localized: "UIKit")\n#else\n'
                  'let b = String(localized: "No UIKit")\n#endif\n'
                  '#if DASHPAY\nlet c = String(localized: "Dashpay")\n#elseif SNAPSHOT\n'
                  'let d = String(localized: "Snapshot")\n#else\nlet e = String(localized: "Other")\n#endif\n'
                  '#if DASHPAY\n#if DEBUG\nlet f = String(localized: "Nested debug")\n#endif\n'
                  'let g = String(localized: "Outer dashpay")\n#endif\n')
        debug, other = lookups_by_region(source)
        self.assertEqual(debug, {"UIKit", "No UIKit", "Snapshot", "Other", "Nested debug"})
        self.assertEqual(other, {"Dashpay", "Outer dashpay"})

    def test_objc_lookups_under_a_positive_debug_condition_are_unseen(self):
        source = ('NSLocalizedString(@"Plain", nil);\n'
                  '#ifdef DEBUG\nNSLocalizedString(@"Ifdef debug", nil);\n#else\n'
                  'NSLocalizedString(@"Else of ifdef debug", nil);\n#endif\n'
                  '#if DEBUG\nNSLocalizedString(@"If debug", nil);\n'
                  '#if DASHPAY\nNSLocalizedString(@"Nested", nil);\n#endif\n#endif\n'
                  '#if defined(DEBUG)\nNSLocalizedString(@"Defined debug", nil);\n#endif\n'
                  '#if !DEBUG\nNSLocalizedString(@"Not debug", nil);\n#endif\n'
                  '#ifndef DEBUG\nNSLocalizedString(@"Ifndef debug", nil);\n#endif\n'
                  '#if SNAPSHOT\nNSLocalizedString(@"Snapshot", nil);\n#else\n'
                  'NSLocalizedString(@"Else of snapshot", nil);\n#endif\n')
        unseen, seen = objc_lookups_by_region(source)
        self.assertEqual(unseen, {"Ifdef debug", "If debug", "Nested", "Defined debug"})
        self.assertEqual(seen, {"Plain", "Else of ifdef debug", "Not debug", "Ifndef debug",
                                "Snapshot", "Else of snapshot"})

    def test_objc_branches_are_seen_only_in_the_allowed_shapes(self):
        cases = [  # (source, unseen keys, seen keys)
            ('#if DEBUG && !SNAPSHOT\nA\n#endif\n', {"A"}, set()),
            ('#if defined(DEBUG) && !defined(SNAPSHOT)\nA\n#endif\n', {"A"}, set()),
            ('#if FRESH_INSTALL && !DEBUG\nA\n#else\nB\n#endif\n', {"A", "B"}, set()),
            ('#if DEBUG || SNAPSHOT\nA\n#else\nB\n#endif\n', {"A", "B"}, set()),
            ('#ifndef DEBUG\nA\n#elif SNAPSHOT\nB\n#else\nC\n#endif\n', {"B", "C"}, {"A"}),
            ('#if SNAPSHOT\nA\n#elif DEBUG\nB\n#else\nC\n#endif\n', {"B", "C"}, {"A"}),
            ('#if 0\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('# if DEBUG\nA\n# else\nB\n# endif\n', {"A"}, {"B"}),
            ('#ifdef DEBUG /* c */\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#if DEBUG // c\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#if (DEBUG)\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#if !defined(DEBUG)\nA\n#else\nB\n#endif\n', {"B"}, {"A"}),
            ('#if (!DEBUG)\nA\n#endif\n', set(), {"A"}),
            ('#if DASHPAY\n#ifndef DEBUG\nA\n#endif\n#endif\n', set(), {"A"}),
            ('#if DEBUG\n#else\n#if 0\nA\n#endif\n#endif\n', {"A"}, set()),
        ]
        for source, unseen, seen in cases:
            with self.subTest(source=source):
                source = re.sub(r"^([ABC])$", r'NSLocalizedString(@"\1", nil);', source, flags=re.M)
                self.assertEqual(objc_lookups_by_region(source), (unseen, seen))

    def test_every_source_the_dashpay_target_compiles_is_scanned(self):
        self.assertEqual(sorted(os.path.relpath(r, REPO) for r in DASHPAY_SOURCES),
                         ["DashPay", "DashWallet", "Shared"])
        _, seen = scan(DASHPAY_SOURCES)
        _, in_sources = scan([os.path.join(REPO, "DashWallet", "Sources")])
        _, in_dashpay = scan([os.path.join(REPO, "DashPay")])
        _, in_app_delegate = objc_lookups_by_region(
            open(os.path.join(REPO, "DashWallet", "AppDelegate.m"), encoding="utf-8").read())
        self.assertTrue(in_dashpay - in_sources, "no lookup only DashPay/ makes")
        self.assertLessEqual(in_dashpay | in_app_delegate, seen)

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

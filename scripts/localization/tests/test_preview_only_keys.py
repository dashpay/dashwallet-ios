#!/usr/bin/env python3
"""A Catalog key that the dashpay Debug build's sync cannot see is a `manual` entry.

- Swift looked up only inside `#Preview` or `#if DEBUG` code: the Xcode app does not extract
  strings from that code and marks such an entry stale after a build, while the command-line sync
  phase keeps it; the two writers would disagree on every build.
- Swift looked up only in a branch the dashpay Debug build does not compile (the `#else` of
  `#if DEBUG`, an undefined flag), and Objective-C looked up only where `xcstringstool extract`
  records a visibility the sync drops: a `DEBUG` condition that is not negated (alone or in a
  conjunction), `TARGET_OS_SIMULATOR`, or an always-false condition (`#if 0`, `#if false`, the
  `#else` of `#if 1`): the sync marks the entry stale.
- Out of caution the scan also counts as unseen some code the sync may see: Swift under a condition
  that names `DEBUG` anywhere (any branch of `#if DEBUG`, `#if FOO && !DEBUG`) or that is not built
  only of flags, `!`, `&&` and `||` (`os()`, `canImport()`, `targetEnvironment()`, `false`); and
  Objective-C whose visibility names `DEBUG` not negated anywhere (a disjunction, the `#else` of
  `FOO && !DEBUG`), names the simulator at all, or is a condition the extractor records as opaque
  (`#if DEBUG == 1`, `__has_feature`), a module check (`__has_include`) or Catalyst.
- Looked up only by the Today extension, which compiles the Catalog but has no sync phase, or only
  in Swift under `#if !DASHPAY`: the dashpay sync marks the entry stale, so it reads as an Unused
  entry while a target still shows it.

The lookups of both languages and their conditions come from `xcstringstool extract`: Objective-C
through the extraction the sync phase runs, Swift through its `String(localized:)` and SwiftUI
extraction, which stands in for the compiler's. Comments, calls wrapped over lines, line
continuations, `#elseif` and every directive shape read as the extractor reads them. The dashpay
files are the target's own list in `project.pbxproj`; a file in no target is not read.

Neither writer changes a `manual` entry (ADR-0071).
"""
import functools
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "scripts", "localization"))

import sync_catalog  # noqa: E402

PROJECT = os.path.join(REPO, "DashWallet.xcodeproj", "project.pbxproj")
SOURCE_SUFFIXES = (".swift", ".m", ".mm")
TODAY_SOURCES = os.path.join(REPO, "TodayExtension")
CATALOG = os.path.join(REPO, "DashWallet", "Localizable.xcstrings")
# The dashpay Debug build's SWIFT_ACTIVE_COMPILATION_CONDITIONS.
DEBUG_BUILD_FLAGS = {"DEBUG", "PIGGYCARDS_ENABLED", "DASHPAY"}


def swift_condition(visibility):
    """True or False for a condition built of `defined`, negation, conjunction and disjunction, evaluated for the
    dashpay Debug build's flags; None for any other shape."""
    kind = visibility.get("type") if isinstance(visibility, dict) else None
    if kind == "defined":
        return visibility["value"] in DEBUG_BUILD_FLAGS
    if kind == "negation":
        value = swift_condition(visibility["value"])
        return None if value is None else not value
    if kind in ("conjunction", "disjunction"):
        values = [swift_condition(v) for v in visibility["values"]]
        if None in values:
            return None
        return all(values) if kind == "conjunction" else any(values)
    return None


def names_debug(visibility):
    if not isinstance(visibility, dict):
        return False
    if visibility.get("type") == "defined":
        return visibility["value"] == "DEBUG"
    return any(names_debug(v) for v in [visibility.get("value")] + visibility.get("values", []))


def swift_visibility_seen(visibility):
    """True when the scan counts a Swift lookup as seen, from the visibility `xcstringstool extract` records for it:
    none, or a condition `swift_condition` evaluates to True that names no `DEBUG` (the Xcode app drops keys
    `#if DEBUG` code looks up). `preview`, `never`, `simulator`, `platform`, `availableModule` and any other shape
    count as unseen."""
    return visibility is None or (swift_condition(visibility) is True and not names_debug(visibility))


def objc_visibility_seen(visibility, negated=False):
    """True when the scan counts an Objective-C lookup as seen, from the visibility `xcstringstool extract`
    records for it: none, or one built only of `defined`, `platform`, negation, conjunction and disjunction that
    names `DEBUG` only under an odd number of negations. `never` (an always-false condition), `simulator`
    (`TARGET_OS_SIMULATOR`) and any other shape count as unseen."""
    if visibility is None:
        return True
    if not isinstance(visibility, dict):
        return False
    kind = visibility.get("type")
    if kind == "negation":
        return objc_visibility_seen(visibility["value"], not negated)
    if kind == "defined":
        return visibility["value"] != "DEBUG" or negated
    if kind == "platform":
        return True
    if kind in ("conjunction", "disjunction"):
        return all(objc_visibility_seen(v, negated) for v in visibility["values"])
    return False


def extracted_lookups(paths, seen_by, *modes):
    """(keys looked up where `seen_by` counts the visibility as unseen, keys looked up elsewhere) in `paths`,
    through `xcstringstool extract` in the given modes."""
    unseen, seen = set(), set()
    with tempfile.TemporaryDirectory() as tmp:
        for data in sync_catalog.extract(list(paths), tmp, *modes):
            with open(data, encoding="utf-8") as f:
                for entry in json.load(f)["tables"].get("Localizable", []):
                    (seen if seen_by(entry.get("visibility")) else unseen).add(entry["key"])
    return unseen, seen


def objc_lookups(paths):
    """extracted_lookups() for Objective-C files, through the extraction the sync phase runs on them."""
    return extracted_lookups(paths, objc_visibility_seen, "--legacy-localizable-strings")


def swift_lookups(paths):
    """extracted_lookups() for Swift files: `String(localized:)` and the SwiftUI APIs whose literal is a key."""
    return extracted_lookups(paths, swift_visibility_seen, "--modern-localizable-strings", "--SwiftUI")


def scan(paths):
    """(keys looked up only in code the scan counts as unseen, keys looked up elsewhere) in the given `.swift`,
    `.m` and `.mm` files, Swift and Objective-C together."""
    objc_unseen, objc_seen = objc_lookups([p for p in paths if p.endswith((".m", ".mm"))])
    swift_unseen, swift_seen = swift_lookups([p for p in paths if p.endswith(".swift")])
    return objc_unseen | swift_unseen, objc_seen | swift_seen


def files_under(root):
    return [os.path.join(d, n) for d, _, names in os.walk(root) for n in names if n.endswith(SOURCE_SUFFIXES)]


def dashpay_sources():
    """Every `.swift` / `.m` / `.mm` file the dashpay target compiles: the files of its Sources build phase and of
    its synchronized folders, less the folders' membership exceptions for it. A synchronized folder missing on
    disk compiles nothing."""
    objects = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", PROJECT],
                                        capture_output=True, check=True).stdout)["objects"]
    parent = {child: key for key, value in objects.items() for child in value.get("children", [])}

    def path(key):
        parts = []
        while key in objects:
            parts.append(objects[key].get("path", ""))
            if objects[key].get("sourceTree") != "<group>":
                break
            key = parent.get(key)
        return os.path.normpath(os.path.join(REPO, *reversed(parts)))

    target_key, target = next((k, v) for k, v in objects.items()
                              if v.get("isa") == "PBXNativeTarget" and v.get("name") == "dashpay")
    files = set()
    for phase in target["buildPhases"]:
        if objects[phase]["isa"] == "PBXSourcesBuildPhase":
            files |= {path(objects[f]["fileRef"]) for f in objects[phase]["files"] if "fileRef" in objects[f]}
    for group in target.get("fileSystemSynchronizedGroups", []):
        root = path(group)
        excluded = {os.path.join(root, name) for exception in objects[group].get("exceptions", [])
                    if objects[exception].get("target") == target_key
                    for name in objects[exception].get("membershipExceptions", [])}
        files |= set(files_under(root)) - excluded
    return sorted(f for f in files if f.endswith(SOURCE_SUFFIXES))


@functools.lru_cache(maxsize=None)
def dashpay_scan():
    return scan(dashpay_sources())


def lookups_in(source, name, lookups):
    """lookups() for one file called `name` holding `source`."""
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(source)
        return lookups([path])


def objc_lookups_in(source):
    return lookups_in(source, "a.m", objc_lookups)


def swift_lookups_in(source):
    return lookups_in(source, "a.swift", swift_lookups)


def not_manual(keys):
    with open(CATALOG, encoding="utf-8") as f:
        strings = json.load(f)["strings"]
    return sorted(k for k in keys if k in strings and strings[k].get("extractionState") != "manual")


class PreviewOnlyKeysTests(unittest.TestCase):
    def test_debug_only_lookups_are_manual_entries(self):
        unseen, seen = dashpay_scan()
        self.assertEqual(not_manual(unseen - seen), [],
                         "looked up only in code the scan counts as unseen but not manual")

    def test_keys_only_the_today_extension_looks_up_are_manual_entries(self):
        _, seen = dashpay_scan()
        today = set().union(*scan(files_under(TODAY_SOURCES)))
        self.assertTrue(today, "no lookup found under TodayExtension")
        self.assertEqual(not_manual(today - seen), [],
                         "looked up only by the Today extension but not manual")

    def test_the_scanner_tells_dashpay_code_from_other_code(self):
        source = ('#if !DASHPAY\nlet a = String(localized: "Not dashpay")\n#else\n'
                  'let b = String(localized: "Dashpay one")\n#endif\n'
                  '#if DASHPAY\nlet c = String(localized: "Dashpay two")\n#else\n'
                  'let d = String(localized: "Not dashpay either")\n#endif\n')
        debug, other = swift_lookups_in(source)
        self.assertEqual(debug, {"Not dashpay", "Not dashpay either"})
        self.assertEqual(other, {"Dashpay one", "Dashpay two"})

    def test_the_scanner_tells_debug_code_from_release_code(self):
        source = ('let a = String(localized: "Shown")\n'
                  '#if DEBUG\nlet b = String(localized: "Debug only")\n#endif\n'
                  '#Preview("x") {\n    Text(String(localized: "Preview only"))\n}\n'
                  'let c = String(localized: "After")\n')
        debug, other = swift_lookups_in(source)
        self.assertEqual(debug, {"Debug only", "Preview only"})
        self.assertEqual(other, {"Shown", "After"})

    def test_both_branches_of_a_debug_condition_are_unseen(self):
        source = ('#if DEBUG\nlet a = String(localized: "Debug")\n#else\n'
                  'let b = String(localized: "Release banner")\n#endif\n'
                  '#if !DEBUG\nlet c = String(localized: "Not debug")\n#else\n'
                  'let d = String(localized: "Debug again")\n#endif\n'
                  '#if DEBUG || Testflight\nlet e = String(localized: "Debug or TestFlight")\n#else\n'
                  'let f = String(localized: "Neither")\n#endif\n')
        debug, other = swift_lookups_in(source)
        self.assertEqual(debug, {"Debug", "Release banner", "Not debug", "Debug again",
                                 "Debug or TestFlight", "Neither"})
        self.assertEqual(other, set())

    def test_a_branch_the_dashpay_debug_build_does_not_compile_is_unseen(self):
        source = ('#if DASH_TESTNET\nlet a = String(localized: "Testnet")\n#else\n'
                  'let b = String(localized: "Not testnet")\n#endif\n'
                  '#if PIGGYCARDS_ENABLED\nlet c = String(localized: "Piggy")\n#else\n'
                  'let d = String(localized: "No piggy")\n#endif\n'
                  '#if !SNAPSHOT\nlet e = String(localized: "Not snapshot")\n#endif\n')
        debug, other = swift_lookups_in(source)
        self.assertEqual(debug, {"Testnet", "No piggy"})
        self.assertEqual(other, {"Not testnet", "Piggy", "Not snapshot"})

    def test_a_module_check_and_the_branches_after_a_compiled_one_are_unseen(self):
        source = ('#if canImport(UIKit)\nlet a = String(localized: "UIKit")\n#else\n'
                  'let b = String(localized: "No UIKit")\n#endif\n'
                  '#if DASHPAY\nlet c = String(localized: "Dashpay")\n#elseif SNAPSHOT\n'
                  'let d = String(localized: "Snapshot")\n#else\nlet e = String(localized: "Other")\n#endif\n'
                  '#if DASHPAY\n#if DEBUG\nlet f = String(localized: "Nested debug")\n#endif\n'
                  'let g = String(localized: "Outer dashpay")\n#endif\n')
        debug, other = swift_lookups_in(source)
        self.assertEqual(debug, {"UIKit", "No UIKit", "Snapshot", "Other", "Nested debug"})
        self.assertEqual(other, {"Dashpay", "Outer dashpay"})

    def test_swift_branches_are_seen_only_in_the_allowed_shapes(self):
        cases = [  # (source, unseen keys, seen keys)
            # A lookup wrapped over lines is still a lookup.
            ('#if DEBUG\nlet a = String(\n    localized: "A")\n#endif\nlet b = String(\n    localized: "B")\n',
             {"A"}, {"B"}),
            # Comments: a commented-out lookup is no lookup, and a commented-out directive opens no branch.
            ('// let a = String(localized: "A")\n/* let b = String(localized: "B") */\n', set(), set()),
            ('/*\n#if DEBUG\n*/\nlet a = String(localized: "A")\n/* #endif */\n', set(), {"A"}),
            ('import SwiftUI\n#Preview {\n    Text(String(\n        localized: "A"))\n}\n', {"A"}, set()),
            # An `#elseif` branch is evaluated from its full condition.
            ('#if SNAPSHOT\nlet a = String(localized: "A")\n#elseif DASHPAY\nlet b = String(localized: "B")\n'
             '#else\nlet c = String(localized: "C")\n#endif\n', {"A", "C"}, {"B"}),
            ('#if !SNAPSHOT && DASHPAY\nlet a = String(localized: "A")\n#endif\n', set(), {"A"}),
            ('#if SNAPSHOT || PIGGYCARDS_ENABLED\nlet a = String(localized: "A")\n#endif\n', set(), {"A"}),
            ('#if DASHPAY && !DEBUG\nlet a = String(localized: "A")\n#else\nlet b = String(localized: "B")\n'
             '#endif\n', {"A", "B"}, set()),
            # Conditions the scan does not evaluate.
            ('#if os(iOS)\nlet a = String(localized: "A")\n#endif\n', {"A"}, set()),
            ('#if targetEnvironment(simulator)\nlet a = String(localized: "A")\n#endif\n', {"A"}, set()),
            ('#if false\nlet a = String(localized: "A")\n#endif\n', {"A"}, set()),
            # A literal passed `as String` takes the verbatim overload: no lookup.
            ('import SwiftUI\n#if DEBUG\nlet a = Button("A" as String) {}\n#endif\n', set(), set()),
        ]
        for source, unseen, seen in cases:
            with self.subTest(source=source):
                self.assertEqual(swift_lookups_in(source), (unseen, seen))

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
        unseen, seen = objc_lookups_in(source)
        self.assertEqual(unseen, {"Ifdef debug", "If debug", "Nested", "Defined debug"})
        self.assertEqual(seen, {"Plain", "Else of ifdef debug", "Not debug", "Ifndef debug",
                                "Snapshot", "Else of snapshot"})

    def test_objc_branches_are_seen_only_in_the_allowed_shapes(self):
        cases = [  # (source, unseen keys, seen keys)
            ('#if DEBUG && !SNAPSHOT\nA\n#endif\n', {"A"}, set()),
            ('#if defined(DEBUG) && !defined(SNAPSHOT)\nA\n#endif\n', {"A"}, set()),
            ('#if FRESH_INSTALL && !DEBUG\nA\n#else\nB\n#endif\n', {"B"}, {"A"}),
            ('#if DEBUG || SNAPSHOT\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#ifndef DEBUG\nA\n#elif SNAPSHOT\nB\n#else\nC\n#endif\n', {"B", "C"}, {"A"}),
            ('#if SNAPSHOT\nA\n#elif DEBUG\nB\n#else\nC\n#endif\n', {"B"}, {"A", "C"}),
            ('#if 0\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('# if DEBUG\nA\n# else\nB\n# endif\n', {"A"}, {"B"}),
            ('#ifdef DEBUG /* c */\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#if DEBUG // c\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#if (DEBUG)\nA\n#else\nB\n#endif\n', {"A"}, {"B"}),
            ('#if !defined(DEBUG)\nA\n#else\nB\n#endif\n', {"B"}, {"A"}),
            ('#if (!DEBUG)\nA\n#endif\n', set(), {"A"}),
            ('#if DASHPAY\n#ifndef DEBUG\nA\n#endif\n#endif\n', set(), {"A"}),
            ('#if DEBUG\n#else\n#if 0\nA\n#endif\n#endif\n', {"A"}, set()),
            # The simulator and always-false conditions the sync marks stale.
            ('#if TARGET_OS_SIMULATOR\nA\n#else\nB\n#endif\n', {"A", "B"}, set()),
            ('#if TARGET_IPHONE_SIMULATOR\nA\n#endif\n', {"A"}, set()),
            ('#if (TARGET_OS_SIMULATOR && DASHPAY)\nA\n#endif\n', {"A"}, set()),
            ('#if (0)\nA\n#endif\n', {"A"}, set()),
            ('#if 0 && SNAPSHOT\nA\n#endif\n', {"A"}, set()),
            ('#if false\nA\n#endif\n', {"A"}, set()),
            ('#if 1\nA\n#else\nB\n#endif\n', {"B"}, {"A"}),
            ('#if 1\nA\n#elif SNAPSHOT\nB\n#endif\n', {"B"}, {"A"}),
            ('#if SNAPSHOT\nA\n#elifdef DEBUG\nB\n#endif\n', {"B"}, {"A"}),
            ('#if SNAPSHOT && \\\n    DEBUG\nA\n#endif\n', {"A"}, set()),
            ('#if TARGET_OS_IOS\nA\n#endif\n', set(), {"A"}),
            # Comments: a commented-out lookup is no lookup, and a commented-out directive opens no branch.
            ('// A\n/* B */\n', set(), set()),
            ('/*\n#if DEBUG\n*/\nA\n/* #endif */\n', set(), {"A"}),
        ]
        for source, unseen, seen in cases:
            with self.subTest(source=source):
                source = re.sub(r"^(// |/\* )?([ABC])( \*/)?$", r'\1NSLocalizedString(@"\2", nil);\3', source,
                                flags=re.M)
                self.assertEqual(objc_lookups_in(source), (unseen, seen))

    def test_the_scan_reads_exactly_the_files_the_dashpay_target_compiles(self):
        sources = {os.path.relpath(p, REPO) for p in dashpay_sources()}
        for name in ["DashWallet/AppDelegate.m",  # outside DashWallet/Sources
                     "DashWallet/Sources/UI/Views/SharedViews/SegmentedControl/DWProgressAnimator.mm",
                     "DashWallet/Sources/Infrastructure/Notifications/NotificationRouter.swift",  # synchronized
                     "Shared/Sources/UIImage+Utils.m"]:
            self.assertIn(name, sources)
        self.assertTrue(any(name.startswith("DashPay/") for name in sources))
        # In no target: its lookups must not count as seen.
        self.assertNotIn("DashWallet/Sources/UI/DashPay/Explore/Views/DWExploreHeaderView.m", sources)
        self.assertTrue(all(os.path.isfile(os.path.join(REPO, name)) for name in sources))
        _, seen = dashpay_scan()
        _, in_dashpay = scan([p for p in dashpay_sources() if os.path.relpath(p, REPO).startswith("DashPay/")])
        _, outside = scan([p for p in dashpay_sources() if not os.path.relpath(p, REPO).startswith("DashPay/")])
        self.assertTrue(in_dashpay - outside, "no lookup only DashPay/ makes")
        self.assertLessEqual(in_dashpay, seen)

    def test_the_scanner_sees_swiftui_literal_keys(self):
        source = ('import SwiftUI\nText("Shown text")\n'
                  '#Preview("x") {\n    Text("Preview text")\n    Button("Preview button") {}\n'
                  '    Label("Preview label", systemImage: "x")\n        .navigationTitle("Preview title")\n}\n'
                  'Text(verbatim: "Not a key")\n')
        debug, other = swift_lookups_in(source)
        self.assertEqual(debug, {"Preview text", "Preview button", "Preview label", "Preview title"})
        self.assertEqual(other, {"Shown text"})

    def test_the_scanner_sees_the_other_swiftui_literal_keys(self):
        calls = {"ContentUnavailableView": '("{}", systemImage: "x")',
                 "NavigationLink": '("{}") { EmptyView() }',
                 "ProgressView": '("{}")',
                 "Stepper": '("{}", value: $n)',
                 "DatePicker": '("{}", selection: $d)',
                 "DisclosureGroup": '("{}") { EmptyView() }',
                 "LabeledContent": '("{}", value: "v")',
                 "GroupBox": '("{}") { EmptyView() }',
                 "ColorPicker": '("{}", selection: $c)'}
        modifiers = {"alert": '("{}", isPresented: $b) {}',
                     "confirmationDialog": '("{}", isPresented: $b) {}',
                     "help": '("{}")',
                     "navigationSubtitle": '("{}")'}
        body = "".join(f'    {n}{call.replace("{}", n + " key", 1)}\n' for n, call in calls.items())
        body += "".join(f'        .{m}{call.replace("{}", m + " key", 1)}\n' for m, call in modifiers.items())
        debug, other = swift_lookups_in('import SwiftUI\n#Preview("x") {\n' + body + "}\n")
        self.assertEqual(debug, {f"{n} key" for n in list(calls) + list(modifiers)})
        self.assertEqual(other, set())


if __name__ == "__main__":
    unittest.main()

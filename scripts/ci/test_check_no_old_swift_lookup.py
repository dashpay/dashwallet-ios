#!/usr/bin/env python3
"""Tests for check_no_old_swift_lookup.py."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_no_old_swift_lookup.py")


class OldSwiftLookupGuardTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="old-lookup-guard-")
        self.addCleanup(shutil.rmtree, self.root, True)

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def run_guard(self):
        return subprocess.run([sys.executable, SCRIPT, "--root", self.root],
                              capture_output=True, text=True, timeout=60)

    def test_swift_call_in_the_app_fails_and_is_named(self):
        self.write("DashWallet/Sources/A.swift",
                   'let a = 1\nlet b = NSLocalizedString("k", comment: "")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("DashWallet/Sources/A.swift:2: NSLocalizedString in Swift", res.stdout)

    def test_swift_call_in_the_unit_tests_fails(self):
        self.write("DashWalletTests/T.swift", 'XCTAssertEqual(NSLocalizedString("k", comment: ""), "k")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("DashWalletTests/T.swift:1: NSLocalizedString in Swift", res.stdout)

    def test_comments_do_not_count(self):
        self.write("DashWallet/Sources/C.swift",
                   '// NSLocalizedString("k", comment: "")\n'
                   '/* NSLocalizedString("k", comment: "")\n'
                   '   /* nested */ NSLocalizedString("k", comment: "") */\n'
                   'let url = "https://example.com" // NSLocalizedString(\n'
                   '/// Replaces NSLocalizedString(_:comment:).\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 0, res.stdout)

    def test_a_call_after_a_string_with_slashes_still_counts(self):
        self.write("DashWallet/Sources/U.swift",
                   'let s = "a // b"; let t = NSLocalizedString("k", comment: "")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("U.swift:1:", res.stdout)

    def test_the_name_inside_a_string_literal_does_not_count(self):
        self.write("DashWallet/Sources/S.swift", 'let s = "NSLocalizedString("\n')
        self.assertEqual(self.run_guard().returncode, 0)

    def test_a_call_inside_a_string_interpolation_counts(self):
        self.write("DashWallet/Sources/I.swift",
                   'let a = "x \\(NSLocalizedString("k", comment: ""))"\n'
                   'let b = "y \\(foo(bar(NSLocalizedString("k", comment: ""))))"\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("I.swift:1:", res.stdout)
        self.assertIn("I.swift:2:", res.stdout)

    def test_a_call_after_a_raw_string_literal_counts(self):
        self.write("DashWallet/Sources/R.swift",
                   'let a = #"say "hi""#; let b = NSLocalizedString("k", comment: "")\n'
                   'let c = ##"x "# y"##; let d = NSLocalizedString("k", comment: "")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("R.swift:1:", res.stdout)
        self.assertIn("R.swift:2:", res.stdout)

    def test_the_name_inside_a_raw_string_literal_does_not_count(self):
        self.write("DashWallet/Sources/RS.swift",
                   'let a = #"NSLocalizedString("k", comment: "")"#\n'
                   'let b = ##"NSLocalizedString("#"##\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 0, res.stdout)

    def test_a_call_with_whitespace_before_the_paren_counts(self):
        self.write("DashWallet/Sources/W.swift",
                   'let a = NSLocalizedString ("k", comment: "")\n'
                   'let b = NSLocalizedString\t("k", comment: "")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 1)
        self.assertIn("W.swift:1:", res.stdout)
        self.assertIn("W.swift:2:", res.stdout)

    def test_objective_c_and_watch_swift_pass(self):
        self.write("DashWallet/Sources/L.m", 'NSString *s = NSLocalizedString(@"k", nil);\n')
        self.write("WatchApp Extension/W.swift", 'let w = NSLocalizedString("k", comment: "")\n')
        self.write("DashWallet/WatchApp/X.swift", 'let w = NSLocalizedString("k", comment: "")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 0, res.stdout)

    def test_the_new_call_passes(self):
        self.write("DashWallet/Sources/N.swift", 'let n = String(localized: "k", comment: "")\n')
        res = self.run_guard()
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "")


if __name__ == "__main__":
    unittest.main()

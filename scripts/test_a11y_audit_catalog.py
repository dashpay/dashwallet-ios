#!/usr/bin/env python3
"""Tests for a11y_audit.py on the String Catalog (string-catalogs-migration T15, AC-16).

The audit resolves accessibility-label keys from DashWallet/Localizable.xcstrings and
treats String(localized:) as a localized label, the same way it treats NSLocalizedString.
Run: python3 scripts/test_a11y_audit_catalog.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "a11y_audit.py")
CATALOG = "DashWallet/Localizable.xcstrings"


class AuditOnCatalogTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="a11y-catalog-")
        self.addCleanup(shutil.rmtree, self.root, True)

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def catalog(self, *keys):
        self.write(CATALOG, json.dumps(
            {"sourceLanguage": "en", "version": "1.0",
             "strings": {k: {} for k in keys}}, ensure_ascii=False, indent=2))

    def audit(self, swift):
        self.write("DashWallet/Sources/Screen.swift", swift)
        out = os.path.join(self.root, "findings.json")
        res = subprocess.run(
            [sys.executable, SCRIPT, "--repo-root", self.root, "--path", "DashWallet",
             "--baseline", os.path.join(self.root, "none.json"), "--json", out],
            capture_output=True, text=True, timeout=60)
        return res, (json.load(open(out))["findings"] if os.path.exists(out) else None)

    def rules(self, swift):
        res, findings = self.audit(swift)
        self.assertIsNotNone(findings, res.stdout + res.stderr)
        return [(f["rule"], f["detail"]) for f in findings]

    # A11Y009 — String(localized:) is a localized label, not a bare literal

    def test_string_localized_label_is_not_a_bare_literal(self):
        self.catalog("Close")
        self.assertEqual(self.rules(
            'x.accessibilityLabel(String(localized: "Close", comment: "Accessibility"))\n'), [])

    def test_string_localized_label_split_over_lines(self):
        self.catalog("Close")
        self.assertEqual(self.rules(
            'x.accessibilityLabel(Text(String(\n'
            '    localized: "Close",\n'
            '    comment: "Accessibility")))\n'), [])

    def test_a_bare_literal_label_still_fires(self):
        self.catalog("Close")
        self.assertEqual([r for r, _ in self.rules('x.accessibilityLabel("Close")\n')],
                         ["A11Y009"])

    # A11Y005 / A11Y004 — String(localized:) speaks for itself

    def test_toggle_titled_with_string_localized_has_a_label(self):
        self.catalog("Include diagnostic report")
        self.assertEqual(self.rules(
            'Toggle(String(localized: "Include diagnostic report", comment: ""), '
            'isOn: $on)\n'), [])

    def test_toggle_titled_with_string_localized_over_lines_has_a_label(self):
        self.catalog("Unban")
        self.assertEqual(self.rules(
            'Toggle(\n    String(localized: "Unban", comment: ""),\n    isOn: $on\n)\n'), [])

    # A11Y010 — keys resolve against the Catalog

    def test_key_in_the_catalog_passes(self):
        self.catalog("Add Wallet")
        self.assertEqual(self.rules(
            'b.accessibilityLabel(String(localized: "Add Wallet", comment: "Wallets"))\n'), [])

    def test_key_missing_from_the_catalog_fires_and_names_it(self):
        self.catalog("Add Wallet")
        found = self.rules(
            'b.accessibilityLabel(String(localized: "Add Purse", comment: "Wallets"))\n')
        self.assertEqual([r for r, _ in found], ["A11Y010"])
        self.assertIn('"Add Purse"', found[0][1])
        self.assertIn("Localizable.xcstrings", found[0][1])

    def test_objc_style_key_resolves_against_the_catalog(self):
        self.catalog("Close")
        self.assertEqual(self.rules(
            'b.accessibilityLabel(NSLocalizedString("Close", comment: ""))\n'), [])
        found = self.rules('b.accessibilityLabel(NSLocalizedString("Shut", comment: ""))\n')
        self.assertEqual([r for r, _ in found], ["A11Y010"])

    def test_interpolated_key_resolves_to_its_format_key(self):
        self.catalog("Reconnect %@", "Voting ends in %lld days")
        self.assertEqual(self.rules(
            'b.accessibilityLabel(Text(String(localized: "Reconnect \\(item.name)", '
            'comment: "")))\n'
            'c.accessibilityLabel(String(localized: "Voting ends in \\(days) days"))\n'), [])

    def test_interpolated_key_with_no_catalog_entry_fires(self):
        self.catalog("Reconnect %@")
        found = self.rules(
            'b.accessibilityLabel(String(localized: "Disconnect \\(item.name)"))\n')
        self.assertEqual([r for r, _ in found], ["A11Y010"])

    def test_quotes_inside_an_interpolation_do_not_end_the_key(self):
        self.catalog("%@ DASH")
        self.assertEqual(self.rules(
            'k.accessibilityLabel(Text(String(localized: '
            '"\\(typed.isEmpty ? "0" : typed) DASH", comment: "")))\n'), [])

    def test_escaped_characters_are_unescaped_before_the_lookup(self):
        self.catalog('Remove "%@"', "Line one\nLine two")
        self.assertEqual(self.rules(
            'a.accessibilityLabel(String(localized: "Remove \\"\\(name)\\""))\n'
            'b.accessibilityLabel(String(localized: "Line one\\nLine two"))\n'), [])

    # The check is never skipped because the lists are gone

    def test_without_a_catalog_the_audit_stops_instead_of_skipping_a11y010(self):
        res, _ = self.audit('b.accessibilityLabel(String(localized: "Close"))\n')
        self.assertEqual(res.returncode, 2, res.stdout + res.stderr)
        self.assertIn("Localizable.xcstrings", res.stderr)

    def test_without_a_catalog_other_rules_still_run_when_a11y010_is_off(self):
        self.write("DashWallet/Sources/Screen.swift", 'x.accessibilityLabel("Close")\n')
        res = subprocess.run(
            [sys.executable, SCRIPT, "--repo-root", self.root, "--path", "DashWallet",
             "--rule", "A11Y009", "--summary"],
            capture_output=True, text=True, timeout=60)
        self.assertNotEqual(res.returncode, 2, res.stderr)
        self.assertIn("A11Y009", res.stdout)


if __name__ == "__main__":
    unittest.main()

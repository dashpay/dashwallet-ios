#!/usr/bin/env python3
"""Tests for convert_strings_to_utf8.sh on the String Catalog.

Run: python3 scripts/test_convert_strings_to_utf8.py
"""
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "convert_strings_to_utf8.sh")
CATALOG = "DashWallet/Localizable.xcstrings"
WATCH = "WatchApp/de.lproj/Interface.strings"
BODY = '{\n  "sourceLanguage" : "en",\n  "strings" : {\n    "Grüße" : {}\n  }\n}\n'


class EncodingScriptTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="encoding-script-")
        self.addCleanup(shutil.rmtree, self.root, True)
        os.makedirs(os.path.join(self.root, "scripts"))
        shutil.copy(SCRIPT, os.path.join(self.root, "scripts"))
        self.put(WATCH, b"\xff\xfe" + '"a.title" = "Hallo";\n'.encode("utf-16-le"))

    def put(self, rel, data):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    def get(self, rel):
        with open(os.path.join(self.root, rel), "rb") as f:
            return f.read()

    def run_script(self):
        return subprocess.run(
            ["bash", os.path.join(self.root, "scripts", "convert_strings_to_utf8.sh")],
            capture_output=True, text=True, timeout=60)

    def test_clean_catalog_is_reported_and_left_byte_identical(self):
        self.put(CATALOG, BODY.encode("utf-8"))
        res = self.run_script()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("UTF-8 without BOM", res.stdout)
        self.assertEqual(self.get(CATALOG), BODY.encode("utf-8"))

    def test_bom_is_stripped_and_a_second_run_is_byte_identical(self):
        self.put(CATALOG, b"\xef\xbb\xbf" + BODY.encode("utf-8"))
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.get(CATALOG), BODY.encode("utf-8"))
        res = self.run_script()
        self.assertEqual(res.returncode, 0)
        self.assertEqual(self.get(CATALOG), BODY.encode("utf-8"))

    def test_utf16_catalog_is_refused_and_left_alone(self):
        data = b"\xff\xfe" + BODY.encode("utf-16-le")
        self.put(CATALOG, data)
        res = self.run_script()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("UTF-16", res.stdout + res.stderr)
        self.assertEqual(self.get(CATALOG), data)

    def test_watch_files_are_untouched(self):
        self.put(CATALOG, b"\xef\xbb\xbf" + BODY.encode("utf-8"))
        before = self.get(WATCH)
        self.run_script()
        self.assertEqual(self.get(WATCH), before)

    def test_missing_catalog_fails(self):
        res = self.run_script()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Localizable.xcstrings", res.stdout + res.stderr)


if __name__ == "__main__":
    unittest.main()

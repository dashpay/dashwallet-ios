"""Tests for the build's Catalog sync phase (T10, ADR-0008).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

Contract of scripts/localization/sync_catalog.py (run as a subprocess, like the Xcode
run-script phase runs it): environment SRCROOT, OBJECT_FILE_DIR_normal, TARGET_NAME
(ARCHS / CURRENT_ARCH may be unset; every <arch> dir is scanned).
  - $SRCROOT/DashWallet/Localizable.xcstrings missing -> note on stdout, exit 0, nothing created.
  - Otherwise: xcstringstool sync with the compiler .stringsdata, plus a legacy extraction of
    the target's Swift files (<arch>/<TARGET_NAME>.SwiftFileList, `\\ `-escaped paths) and the
    .m/.mm files under SRCROOT named in the <arch>/*.d files; then re-serialized with
    catalog_io; written only when the bytes changed.
Fixtures (fixtures/sync/) hold `@SRCROOT@` placeholders, filled in a temp copy.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
FIXTURE = os.path.join(LOCALIZATION_DIR, "fixtures", "sync")
SCRIPT = os.path.join(LOCALIZATION_DIR, "sync_catalog.py")
sys.path.insert(0, LOCALIZATION_DIR)

import catalog_io  # noqa: E402


def entry(catalog, key):
    return catalog["strings"][key]


class SyncCatalogTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="sync-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = os.path.join(self.tmp, "root")
        shutil.copytree(FIXTURE, self.root)
        for dirpath, _, names in os.walk(self.root):
            for n in names:
                p = os.path.join(dirpath, n)
                if n.endswith((".stringsdata", ".SwiftFileList", ".d")):
                    with open(p, encoding="utf-8") as f:
                        text = f.read()
                    with open(p, "w", encoding="utf-8") as f:
                        f.write(text.replace("@SRCROOT@", os.path.join(self.root, "src")))
        self.srcroot = os.path.join(self.root, "src")
        os.makedirs(os.path.join(self.srcroot, "DashWallet"), exist_ok=True)
        self.catalog = os.path.join(self.srcroot, "DashWallet", "Localizable.xcstrings")
        shutil.copy(os.path.join(self.root, "DashWallet", "Localizable.xcstrings"), self.catalog)
        self.env = dict(os.environ, SRCROOT=self.srcroot,
                        OBJECT_FILE_DIR_normal=os.path.join(self.root, "obj"),
                        TARGET_NAME="Target")
        for k in ("ARCHS", "CURRENT_ARCH"):
            self.env.pop(k, None)

    def run_sync(self, env=None):
        return subprocess.run([sys.executable, SCRIPT], env=env or self.env,
                              capture_output=True, text=True, timeout=300)

    def read_bytes(self):
        with open(self.catalog, "rb") as f:
            return f.read()

    def test_stale_marking_follows_all_three_sources(self):
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        cat = catalog_io.read_catalog(self.catalog)
        self.assertEqual(entry(cat, "Used nowhere").get("extractionState"), "stale")
        for key in ("Hello from Swift", "Objc only", "Swift legacy only"):
            self.assertNotEqual(entry(cat, key).get("extractionState"), "stale", key)
            self.assertIn("de", entry(cat, key)["localizations"], key)

    def test_output_is_the_catalog_io_serialization(self):
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        expected = os.path.join(self.tmp, "expected.xcstrings")
        shutil.copy(self.catalog, expected)
        catalog_io.write_catalog(expected, catalog_io.read_catalog(self.catalog))
        with open(expected, "rb") as f:
            self.assertEqual(self.read_bytes(), f.read())

    def test_second_run_leaves_bytes_and_mtime(self):
        self.assertEqual(self.run_sync().returncode, 0)
        first = self.read_bytes()
        os.utime(self.catalog, (1000000000, 1000000000))
        self.assertEqual(self.run_sync().returncode, 0)
        self.assertEqual(self.read_bytes(), first)
        self.assertEqual(os.stat(self.catalog).st_mtime, 1000000000)

    def test_unchanged_inputs_skip_the_sync(self):
        self.assertEqual(self.run_sync().returncode, 0)
        second = self.run_sync()
        self.assertEqual(second.returncode, 0)
        self.assertIn("skipped", second.stdout)

    def test_a_changed_input_runs_the_sync_again(self):
        self.assertEqual(self.run_sync().returncode, 0)
        swift = os.path.join(self.srcroot, "DashWallet", "Sources", "Legacy.swift")
        with open(swift, "a", encoding="utf-8") as f:
            f.write("\n")
        again = self.run_sync()
        self.assertEqual(again.returncode, 0)
        self.assertNotIn("skipped", again.stdout)

    def test_a_hand_edited_catalog_runs_the_sync_again(self):
        self.assertEqual(self.run_sync().returncode, 0)
        normalized = self.read_bytes()
        with open(self.catalog, "wb") as f:
            f.write(normalized.replace(b"\n", b"\n ", 1))
        again = self.run_sync()
        self.assertEqual(again.returncode, 0)
        self.assertNotIn("skipped", again.stdout)
        self.assertEqual(self.read_bytes(), normalized)

    def test_debug_configuration_syncs(self):
        res = self.run_sync(dict(self.env, CONFIGURATION="Debug"))
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(entry(catalog_io.read_catalog(self.catalog), "Used nowhere").get("extractionState"), "stale")

    def test_other_configurations_leave_the_catalog_alone(self):
        # A Release build does not compile #if DEBUG code; syncing it would mark that code's texts stale.
        before = self.read_bytes()
        for configuration in ("Release", "TestFlight", "TestNet"):
            res = self.run_sync(dict(self.env, CONFIGURATION=configuration))
            self.assertEqual(res.returncode, 0, res.stderr)
            self.assertIn("Catalog sync skipped", res.stdout)
            self.assertEqual(self.read_bytes(), before, configuration)

    def test_missing_catalog_is_a_noop(self):
        os.remove(self.catalog)
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertFalse(os.path.exists(self.catalog))
        self.assertTrue(res.stdout.strip(), "expected a note on stdout")


if __name__ == "__main__":
    unittest.main()

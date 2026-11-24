"""Tests for the build's Catalog sync phase (ADR-0071).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

Contract of scripts/localization/sync_catalog.py (run as a subprocess, like the Xcode
run-script phase runs it): environment SRCROOT, OBJECT_FILE_DIR_normal, TARGET_NAME
(ARCHS set: only its <arch> dirs are scanned, and one without a dir is an error; unset: every
<arch> dir is scanned).
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
        self.arch_dir = os.path.join(self.root, "obj", "arm64")
        # What Xcode writes: <arch>/<TARGET_NAME>.LinkFileList names the target's object files.
        self.write_link_list(["My View.o", "Legacy Objc.o", "Legacy.o"])

    def write_link_list(self, object_names):
        with open(os.path.join(self.arch_dir, "Target.LinkFileList"), "w", encoding="utf-8") as f:
            f.write("".join(os.path.join(self.arch_dir, n).replace(" ", "\\ ") + "\n" for n in object_names))

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

    # --- The sync phase's edge cases: missing and leftover inputs ---

    def test_swift_files_without_any_stringsdata_fail_the_build(self):
        # Zero compiler .stringsdata with Swift files in the target means the compile output is
        # missing; syncing would mark every key stale.
        os.remove(os.path.join(self.arch_dir, "My View.stringsdata"))
        before = self.read_bytes()
        res = self.run_sync()
        self.assertNotEqual(res.returncode, 0, res.stdout)
        self.assertIn("error:", res.stderr)
        self.assertIn("stringsdata", res.stderr)
        self.assertEqual(self.read_bytes(), before)

    def test_leftover_inputs_of_a_deleted_source_do_not_count(self):
        # Deleted.m was removed; its .o is gone from the LinkFileList but its .stringsdata and
        # .d are still in the object directory.
        cat = catalog_io.read_catalog(self.catalog)
        # An entry the compiler extracted earlier, with a translation: the sync marks it stale once no
        # current input asks for it (a "manual" entry is never marked stale, so it would prove nothing).
        cat["strings"]["Leftover key"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "x"}}}}
        catalog_io.write_catalog(self.catalog, cat)
        gone = os.path.join(self.srcroot, "DashWallet", "Sources", "Deleted.m")
        with open(os.path.join(self.arch_dir, "Deleted.stringsdata"), "w", encoding="utf-8") as f:
            json.dump({"source": gone, "version": 2, "tables": {"Localizable": [
                {"key": "Leftover key", "comment": "", "location": {"startingLine": 1, "startingColumn": 1}}]}}, f)
        with open(os.path.join(self.arch_dir, "Deleted.d"), "w", encoding="utf-8") as f:
            f.write("dependencies: \\\n  %s\n" % gone)
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        cat = catalog_io.read_catalog(self.catalog)
        self.assertEqual(entry(cat, "Leftover key").get("extractionState"), "stale")
        self.assertNotEqual(entry(cat, "Hello from Swift").get("extractionState"), "stale")
        self.assertNotEqual(entry(cat, "Objc only").get("extractionState"), "stale")

    def leftover_arch(self):
        """An x86_64 folder left by an earlier build, whose own link list still names a deleted key's object."""
        cat = catalog_io.read_catalog(self.catalog)
        cat["strings"]["Leftover key"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "x"}}}}
        catalog_io.write_catalog(self.catalog, cat)
        old = os.path.join(self.root, "obj", "x86_64")
        os.makedirs(old)
        with open(os.path.join(old, "Target.LinkFileList"), "w", encoding="utf-8") as f:
            f.write(os.path.join(old, "Old.o") + "\n")
        with open(os.path.join(old, "Old.stringsdata"), "w", encoding="utf-8") as f:
            json.dump({"source": os.path.join(self.srcroot, "DashWallet", "Sources", "Old.swift"), "version": 2,
                       "tables": {"Localizable": [{"key": "Leftover key", "comment": "",
                                                   "location": {"startingLine": 1, "startingColumn": 1}}]}}, f)

    def test_a_build_reads_only_the_folders_of_its_architectures(self):
        self.leftover_arch()
        res = self.run_sync(dict(self.env, ARCHS="arm64"))
        self.assertEqual(res.returncode, 0, res.stderr)
        cat = catalog_io.read_catalog(self.catalog)
        self.assertEqual(entry(cat, "Leftover key").get("extractionState"), "stale")
        self.assertNotEqual(entry(cat, "Hello from Swift").get("extractionState"), "stale")

    def test_run_by_hand_without_archs_reads_every_folder(self):
        self.leftover_arch()
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertNotEqual(entry(catalog_io.read_catalog(self.catalog), "Leftover key").get("extractionState"), "stale")

    def test_an_architecture_of_the_build_without_a_folder_is_an_error(self):
        self.assert_sync_error(dict(self.env, ARCHS="arm64 x86_64"), "x86_64")

    def test_another_run_s_staging_file_does_not_fail_the_sync(self):
        # Two builds of one checkout can sync at once; a staging path one run holds must not break the other.
        os.makedirs(os.path.join(self.srcroot, "DashWallet", ".Localizable.xcstrings.sync.tmp"))
        cat = catalog_io.read_catalog(self.catalog)
        cat["strings"]["Leftover key"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "x"}}}}
        catalog_io.write_catalog(self.catalog, cat)
        os.chmod(self.catalog, 0o644)
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(entry(catalog_io.read_catalog(self.catalog), "Leftover key").get("extractionState"), "stale")
        self.assertEqual(os.stat(self.catalog).st_mode & 0o777, 0o644)
        left = [n for n in os.listdir(os.path.dirname(self.catalog))
                if n.startswith(".Localizable.xcstrings") and n != ".Localizable.xcstrings.sync.tmp"]
        self.assertEqual(left, [])

    def run_main_saving_during_sync(self, edit):
        """Run main() in-process; `edit` changes the live Catalog after the sync read it."""
        import sync_catalog
        from unittest import mock
        real_sync = sync_catalog.sync

        def sync_then_save(catalog_path, stringsdata, tmp):
            result = real_sync(catalog_path, stringsdata, tmp)
            edit()
            return result
        with mock.patch.dict(os.environ, self.env, clear=True), \
                mock.patch.object(sync_catalog, "sync", sync_then_save):
            return sync_catalog.main()

    def test_an_edit_saved_while_the_sync_runs_is_not_overwritten(self):
        # PP1: a translation saved in Xcode after the sync read the Catalog must survive the build.
        cat = catalog_io.read_catalog(self.catalog)
        cat["strings"]["Leftover key"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "x"}}}}
        catalog_io.write_catalog(self.catalog, cat)

        def save_translation():
            live = catalog_io.read_catalog(self.catalog)
            live["strings"]["Leftover key"]["localizations"]["uk"] = {
                "stringUnit": {"state": "translated", "value": "saved during the build"}}
            catalog_io.write_catalog(self.catalog, live)
        saved = None

        def edit():
            nonlocal saved
            save_translation()
            saved = self.read_bytes()
        self.assertEqual(self.run_main_saving_during_sync(edit), 1)
        self.assertEqual(self.read_bytes(), saved)
        self.assertFalse(os.path.exists(os.path.join(self.root, "obj", ".catalog-sync-stamp")))

    def test_a_sync_with_no_change_of_its_own_leaves_a_saved_edit_and_syncs_again(self):
        self.assertEqual(self.run_sync().returncode, 0)
        os.remove(os.path.join(self.root, "obj", ".catalog-sync-stamp"))
        saved = None

        def edit():
            nonlocal saved
            live = catalog_io.read_catalog(self.catalog)
            live["strings"][next(iter(live["strings"]))]["comment"] = "saved during the build"
            catalog_io.write_catalog(self.catalog, live)
            saved = self.read_bytes()
        self.assertEqual(self.run_main_saving_during_sync(edit), 0)
        self.assertEqual(self.read_bytes(), saved)
        again = self.run_sync()
        self.assertEqual(again.returncode, 0)
        self.assertNotIn("skipped", again.stdout)

    def test_an_input_changed_while_the_sync_runs_syncs_again_next_build(self):
        # The stamp describes the inputs as the sync read them, not as they are after it.
        swift = os.path.join(self.srcroot, "DashWallet", "Sources", "Legacy.swift")

        def edit():
            with open(swift, "a", encoding="utf-8") as f:
                f.write("\n")
        self.assertEqual(self.run_main_saving_during_sync(edit), 0)
        again = self.run_sync()
        self.assertEqual(again.returncode, 0)
        self.assertNotIn("skipped", again.stdout)

    def test_inputs_whose_object_is_listed_in_the_link_file_list_still_count(self):
        self.write_link_list(["My View.o"])  # Legacy Objc.o dropped: its .d must be ignored
        res = self.run_sync()
        self.assertEqual(res.returncode, 0, res.stderr)
        cat = catalog_io.read_catalog(self.catalog)
        self.assertNotEqual(entry(cat, "Hello from Swift").get("extractionState"), "stale")
        self.assertEqual(entry(cat, "Objc only").get("extractionState"), "stale")

    def assert_sync_error(self, env, fragment):
        res = self.run_sync(env)
        self.assertEqual(res.returncode, 1, res.stdout)
        self.assertIn("error: Catalog sync failed", res.stderr)
        self.assertIn(fragment, res.stderr)

    def test_each_missing_environment_variable_is_an_error(self):
        for name in ("SRCROOT", "OBJECT_FILE_DIR_normal", "TARGET_NAME"):
            env = dict(self.env)
            del env[name]
            self.assert_sync_error(env, name)

    def test_unreadable_object_directory_is_an_error(self):
        self.assert_sync_error(dict(self.env, OBJECT_FILE_DIR_normal=os.path.join(self.tmp, "nope")),
                               "OBJECT_FILE_DIR_normal")

    def test_a_listed_source_that_does_not_exist_is_an_error(self):
        os.remove(os.path.join(self.srcroot, "DashWallet", "Sources", "Legacy.swift"))
        self.assert_sync_error(self.env, "do not exist")

    def test_a_failing_xcstringstool_is_an_error(self):
        bin_dir = os.path.join(self.tmp, "bin")
        os.makedirs(bin_dir)
        fake = os.path.join(bin_dir, "xcrun")
        with open(fake, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\necho boom >&2\nexit 3\n")
        os.chmod(fake, 0o755)
        self.assert_sync_error(dict(self.env, PATH=bin_dir + os.pathsep + self.env["PATH"]), "boom")


if __name__ == "__main__":
    unittest.main()

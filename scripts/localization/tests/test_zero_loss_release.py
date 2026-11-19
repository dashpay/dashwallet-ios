"""Tests for the zero-loss check, release mode (contract: scripts/localization/ZERO_LOSS_CHECK.md).

Same temporary repository as test_zero_loss_check.py. setUp additionally runs a passing pre-merge run
with --write-key-map, so the key map the release run reads is the one the pre-merge mode wrote.
Release mode is run with no derived data at all.
"""
import json
import os
import shutil
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_zero_loss_check import (  # noqa: E402
    KEY_MAP, ZeroLossCase, finding_fields, fixture)


class ReleaseCase(ZeroLossCase):
    def setUp(self):
        super().setUp()
        res = self.run_cli("--write-key-map")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.map_path = os.path.join(self.repo, KEY_MAP)
        shutil.rmtree(self.derived)  # release mode never needs .stringsdata

    def read_map(self):
        with open(self.map_path, encoding="utf-8") as f:
            return json.load(f)

    def write_map(self, data):
        with open(self.map_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)

    def release(self, *args):
        return self.run_cli("--release", *args)


class ReleasePassTests(ReleaseCase):
    def test_pass_report_is_byte_for_byte_the_golden(self):
        res = self.release()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        golden = fixture("golden", "release_pass_report.txt").replace("{BASELINE12}", self.baseline[:12])
        self.assertEqual(res.stdout, golden)
        self.assertEqual(res.stderr, "")

    def test_pass_with_the_golden_key_map(self):
        self.write_map(json.loads(fixture("golden", "key_map.json").replace("{BASELINE40}", self.baseline)))
        res = self.release()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("mode: release", res.stdout)

    def test_release_does_not_write_the_key_map(self):
        with open(self.map_path, "rb") as f:
            before = f.read()
        self.release()
        with open(self.map_path, "rb") as f:
            self.assertEqual(f.read(), before)

    def test_new_lookup_after_the_move_does_not_matter(self):
        # a key the Baseline never had, added to the Catalog after the map was written
        self.cat["strings"]["Brand new"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "New"}}}}
        self.install_catalog()
        res = self.release()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)


class ReleaseFindingTests(ReleaseCase):
    def test_translation_changed_after_the_map_is_a_key_finding(self):
        self.cat["strings"]["Hello"]["localizations"]["de"]["stringUnit"]["value"] = "Hallo!"
        self.install_catalog()
        res = self.release()
        self.assert_fails_with(res, 1)
        kind, where, f = finding_fields(self.findings(res)[0])
        self.assertEqual((kind, where), ("key", None))
        self.assertEqual((f["baseline_key"], f["current_key"], f["locale"]), ("Hello", "Hello", "de"))
        self.assertEqual((f["expected"], f["actual"]), ("Hallo", "Hallo!"))
        self.assertEqual(self.row(res, "de"), (5, 4))
        self.assertIn("locale       keys     same", res.stdout)

    def test_moved_key_changed_after_the_map_names_both_keys(self):
        self.cat["strings"]["Sample %lld items"]["localizations"]["de"]["stringUnit"]["value"] = "Muster %lld Elemente"
        self.install_catalog()
        res = self.release()
        self.assert_fails_with(res, 1)
        kind, _, f = finding_fields(self.findings(res)[0])
        self.assertEqual(kind, "key")
        self.assertEqual((f["baseline_key"], f["current_key"]), ("Sample %d items", "Sample %lld items"))
        self.assertEqual(f["expected"], self.fmt("de", "Sample %d items"))

    def test_baseline_key_mapped_to_two_current_keys_checks_each(self):
        entry = json.loads(json.dumps(self.cat["strings"]["Hello"]))
        self.cat["strings"]["Hello again"] = entry
        self.install_catalog()
        data = self.read_map()
        data["keys"]["Hello"] = ["Hello", "Hello again"]
        self.write_map(data)
        res = self.release()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        entry["localizations"]["de"]["stringUnit"]["value"] = "Hallo zwei"
        self.install_catalog()
        res = self.release()
        self.assert_fails_with(res, 1)
        _, _, f = finding_fields(self.findings(res)[0])
        self.assertEqual((f["baseline_key"], f["current_key"], f["locale"]), ("Hello", "Hello again", "de"))
        self.assertEqual((f["expected"], f["actual"]), ("Hallo", "Hallo zwei"))

    def test_unused_entry_loss_is_found_in_release_mode(self):
        del self.cat["strings"]["Unused thing"]["localizations"]["de"]
        self.install_catalog()
        res = self.release()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], 'FAIL unused key="Unused thing" locale=de')

    def test_watch_file_change_is_found_in_release_mode(self):
        self.write("WatchApp/de.lproj/Interface.strings", '"title" = "Uhr 2";\n')
        res = self.release()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], "FAIL watch WatchApp/de.lproj/Interface.strings")

    def test_missing_key_is_found_in_release_mode(self):
        del self.cat["strings"]["Send"]
        self.install_catalog()
        res = self.release()
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn('FAIL missing-key baseline_key="Send"', res.stdout)


class ReleaseBaselineDefectTests(ReleaseCase):
    OVERLAY = "overlay_crash"

    def test_wrong_type_baseline_translation_is_left_out_not_a_key_finding(self):
        res = self.release()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(self.findings(res), [])
        self.assertEqual(self.row(res, "de"), (4, 4))
        self.assertIn("baseline defects: 1 left out", res.stdout.splitlines())
        self.assertIn('DEFECT baseline_key="Sample %d items" locale=de translation="%@ in %d Läden"',
                      res.stdout.splitlines())


class ReleaseCannotRunTests(ReleaseCase):
    def test_missing_key_map(self):
        os.remove(self.map_path)
        self.assert_cannot_run(self.release(), "key map")

    def test_unreadable_key_map(self):
        with open(self.map_path, "w") as f:
            f.write("{not json")
        self.assert_cannot_run(self.release(), "key map")

    def test_baseline_commit_not_in_the_repository(self):
        data = self.read_map()
        data["baseline"] = "0" * 40
        self.write_map(data)
        self.assert_cannot_run(self.release(), "baseline")

    def test_refused_flags(self):
        for flags in (["--baseline", self.baseline], ["--derived-data", self.derived], ["--write-key-map"]):
            with self.subTest(flags=flags):
                self.assert_cannot_run(self.release(*flags), "release")


if __name__ == "__main__":
    unittest.main()

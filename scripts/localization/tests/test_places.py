"""Tests for lookup places and pairing (T5: AC-09, AC-18).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

API under test (scripts/localization/places.py), places are
Place(file, line, column, key) with `file` relative to the repo root:

  baseline_places(repo, rev)            places at <rev>: Swift = xcstringstool
                                        --legacy-localizable-strings --SwiftUI,
                                        kept only if the key is in the Baseline en
                                        lists; Objective-C = legacy extraction.
  current_places(repo, stringsdata_dir) Swift from .stringsdata (searched
                                        recursively, deduped by file/line/col/key),
                                        Objective-C from the working tree.
                                        Raises NoStringsdataError if none found.
  pair(baseline, current)               -> (pairs, mismatched_files); pairs are
                                        (baseline_place, current_place) by ordinal
                                        within a file ordered by (line, column);
                                        mismatched_files are (file, n_baseline,
                                        n_current), sorted by file, never re-paired.
  build_is_stale(repo, stringsdata_dir) newest .stringsdata older than the newest
                                        Swift file under DashWallet/.
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
FIXTURES = os.path.join(LOCALIZATION_DIR, "fixtures", "places")
sys.path.insert(0, LOCALIZATION_DIR)

import places  # noqa: E402

SEND = "DashWallet/Sources/Send.swift"
LEGACY = "DashWallet/Sources/Legacy.m"


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True,
                          capture_output=True, text=True).stdout.strip()


class PlacesCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="places-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.repo = os.path.realpath(os.path.join(self.tmp, "repo"))
        os.makedirs(self.repo)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "commit.gpgsign", "false")
        shutil.copytree(os.path.join(FIXTURES, "repo", "DashWallet"),
                        os.path.join(self.repo, "DashWallet"))
        self.rev = self.commit()

    def commit(self, msg="baseline"):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", msg)
        return git(self.repo, "rev-parse", "HEAD")

    def write(self, rel, text):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)

    def stringsdata(self, *sets):
        """Copy fixture sets into one temp dir (each in its own subfolder),
        replacing __REPO__ with this repo's real path. Returns the dir."""
        out = os.path.join(self.tmp, "derived")
        for name in sets:
            dst = os.path.join(out, name)
            os.makedirs(dst, exist_ok=True)
            for fn in os.listdir(os.path.join(FIXTURES, "stringsdata", name)):
                with open(os.path.join(FIXTURES, "stringsdata", name, fn)) as f:
                    text = f.read().replace("__REPO__", self.repo)
                with open(os.path.join(dst, fn), "w") as f:
                    f.write(text)
        return out

    def write_stringsdata(self, derived, name, source_rel, entries):
        """entries: [(key, line, column)]"""
        doc = {"source": os.path.join(self.repo, source_rel), "version": 1,
               "tables": {"Localizable": [
                   {"key": k, "location": {"startingColumn": c, "startingLine": l}}
                   for k, l, c in entries]}}
        os.makedirs(derived, exist_ok=True)
        with open(os.path.join(derived, name), "w") as f:
            json.dump(doc, f)

    def keys(self, plist, file):
        return [p.key for p in sorted(plist, key=lambda p: (p.line, p.column))
                if p.file == file]


class BaselinePlacesTests(PlacesCase):
    def test_swift_places_include_swiftui_and_nslocalizedstring_in_order(self):
        got = places.baseline_places(self.repo, self.rev)
        self.assertEqual(self.keys(got, SEND), ["Send", "Cancel", "Hello", "%d coins"])

    def test_swiftui_literal_not_in_baseline_lists_is_not_a_place(self):
        got = places.baseline_places(self.repo, self.rev)
        self.assertNotIn("Not in the lists", [p.key for p in got])

    def test_objc_places_are_unfiltered_and_carry_line_and_column(self):
        got = [p for p in places.baseline_places(self.repo, self.rev) if p.file == LEGACY]
        self.assertEqual([(p.key, p.line, p.column) for p in got],
                         [("Obj title", 3, 48), ("Obj body", 4, 47)])

    def test_objc_place_with_key_missing_from_lists_is_still_a_place(self):
        self.write("DashWallet/Sources/Extra.m",
                   '@implementation E\n- (id)a { return NSLocalizedString(@"Unlisted", @""); }\n@end\n')
        rev = self.commit("extra")
        got = places.baseline_places(self.repo, rev)
        self.assertEqual(self.keys(got, "DashWallet/Sources/Extra.m"), ["Unlisted"])

    def test_reads_the_requested_rev_not_the_working_tree(self):
        self.write(SEND, "import SwiftUI\n")
        got = places.baseline_places(self.repo, self.rev)
        self.assertEqual(self.keys(got, SEND), ["Send", "Cancel", "Hello", "%d coins"])

    def test_two_places_on_one_line_are_ordered_by_column(self):
        got = [p for p in places.baseline_places(self.repo, self.rev) if p.line == 4 and p.file == SEND]
        self.assertEqual([(p.key, p.column) for p in sorted(got, key=lambda p: (p.line, p.column))],
                         [("Send", 23), ("Cancel", 37)])


class CurrentPlacesTests(PlacesCase):
    def test_swift_places_come_from_stringsdata_with_repo_relative_file(self):
        derived = self.stringsdata("same")
        got = [p for p in places.current_places(self.repo, derived) if p.file == SEND]
        self.assertEqual(sorted((p.line, p.column, p.key) for p in got),
                         [(4, 23, "Send"), (4, 37, "Cancel"), (6, 48, "Hello"), (7, 71, "%d coins")])

    def test_objc_places_come_from_the_working_tree(self):
        derived = self.stringsdata("same")
        self.write(LEGACY, "@implementation Legacy\n- (id)a { return NSLocalizedString(@\"Changed\", @\"\"); }\n@end\n")
        got = [p for p in places.current_places(self.repo, derived) if p.file == LEGACY]
        self.assertEqual([p.key for p in got], ["Changed"])

    def test_file_compiled_by_two_targets_is_counted_once_per_position(self):
        derived = self.stringsdata("same", "same-x86")
        got = [p for p in places.current_places(self.repo, derived) if p.file == SEND]
        self.assertEqual(len(got), 4)

    def test_no_stringsdata_raises_specific_error(self):
        empty = os.path.join(self.tmp, "empty")
        os.makedirs(empty)
        with self.assertRaises(places.NoStringsdataError):
            places.current_places(self.repo, empty)

    def test_missing_derived_data_dir_raises_specific_error(self):
        with self.assertRaises(places.NoStringsdataError):
            places.current_places(self.repo, os.path.join(self.tmp, "nope"))

    def test_sources_outside_app_folder_are_ignored(self):
        derived = self.stringsdata("same")
        self.write_stringsdata(derived, "T.stringsdata", "DashWalletTests/T.swift", [("X", 1, 1)])
        got = places.current_places(self.repo, derived)
        self.assertNotIn("DashWalletTests/T.swift", [p.file for p in got])


FAKE_ROOT = "/Users/ci/baseline-checkout"
INTERP = "DashWallet/Sources/Interp.swift"
EN_LIST = "DashWallet/en.lproj/Localizable.strings"


class BaselineStringsdataCase(PlacesCase):
    """Baseline Swift places from the compiler data of a build of the Baseline commit,
    whose `source` paths point into another checkout (FAKE_ROOT).

    API: baseline_places(repo, rev, baseline_stringsdata=None, baseline_root=None);
    with a directory, Swift places = its places (sources mapped to repo-relative paths) union
    the --legacy-localizable-strings places of the Baseline Swift files, both kept only if the
    key is in the Baseline en lists. `baseline_root` is the checkout root to strip; when None it
    is inferred: everything before the first "/DashWallet/" in the source is dropped.
    Without the directory the behaviour is the old one (--legacy --SwiftUI).
    """

    def setUp(self):
        super().setUp()
        self.write(INTERP, 'import SwiftUI\nstruct I: View {\n    var body: some View { Text("\\(x) DASH") }\n}\n')
        with open(os.path.join(self.repo, EN_LIST), "a") as f:
            f.write('"%@ DASH" = "%@ DASH";\n')
        self.rev = self.commit("interp")

    def baseline_data(self, interp=(("%@ DASH", 3, 28),)):
        out = os.path.join(self.tmp, "baseline-derived")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(FIXTURES, "stringsdata", "same", "Send.stringsdata")) as f:
            text = f.read().replace("__REPO__", FAKE_ROOT)
        with open(os.path.join(out, "Send.stringsdata"), "w") as f:
            f.write(text)
        doc = {"source": FAKE_ROOT + "/" + INTERP, "version": 1, "tables": {"Localizable": [
            {"key": k, "location": {"startingColumn": c, "startingLine": l}} for k, l, c in interp]}}
        with open(os.path.join(out, "Interp.stringsdata"), "w") as f:
            json.dump(doc, f)
        return out

    def test_interpolation_place_with_a_baseline_key_is_included(self):
        got = places.baseline_places(self.repo, self.rev, baseline_stringsdata=self.baseline_data())
        self.assertEqual([(p.key, p.line, p.column) for p in got if p.file == INTERP], [("%@ DASH", 3, 28)])

    def test_place_whose_key_is_not_in_the_baseline_lists_is_excluded(self):
        data = self.baseline_data(interp=(("%@ DASH", 3, 28), ("%@ not listed", 3, 60)))
        got = places.baseline_places(self.repo, self.rev, baseline_stringsdata=data)
        self.assertNotIn("%@ not listed", [p.key for p in got])

    def test_sources_are_mapped_to_repo_relative_files_and_nslocalizedstring_is_kept_once(self):
        got = places.baseline_places(self.repo, self.rev, baseline_stringsdata=self.baseline_data())
        self.assertEqual(self.keys(got, SEND), ["Send", "Cancel", "Hello", "%d coins"])
        self.assertTrue(all(not p.file.startswith("/") for p in got))

    def test_nslocalizedstring_comes_from_legacy_extraction_when_compiler_data_lacks_it(self):
        data = self.baseline_data()
        os.remove(os.path.join(data, "Send.stringsdata"))
        got = places.baseline_places(self.repo, self.rev, baseline_stringsdata=data)
        self.assertEqual(self.keys(got, SEND), ["Hello", "%d coins"])

    def test_explicit_checkout_root_is_stripped(self):
        out = os.path.join(self.tmp, "baseline-derived")
        os.makedirs(out)
        root = "/work/DashWallet/checkout"  # contains the marker itself, so it must be given
        doc = {"source": root + "/" + INTERP, "version": 1, "tables": {"Localizable": [
            {"key": "%@ DASH", "location": {"startingColumn": 28, "startingLine": 3}}]}}
        with open(os.path.join(out, "Interp.stringsdata"), "w") as f:
            json.dump(doc, f)
        got = places.baseline_places(self.repo, self.rev, baseline_stringsdata=out, baseline_root=root)
        self.assertEqual([p.key for p in got if p.file == INTERP], ["%@ DASH"])

    def test_pairs_with_the_current_side_for_a_file_with_an_interpolation_on_both(self):
        derived = self.stringsdata("same")
        self.write_stringsdata(derived, "Interp.stringsdata", INTERP, [("%@ DASH", 3, 28)])
        base = places.baseline_places(self.repo, self.rev, baseline_stringsdata=self.baseline_data())
        cur = places.current_places(self.repo, derived)
        pairs, mismatched = places.pair(base, cur)
        self.assertEqual(mismatched, [])
        self.assertIn(("%@ DASH", "%@ DASH"), [(b.key, c.key) for b, c in pairs if b.file == INTERP])

    def test_without_the_directory_the_old_behaviour_stays(self):
        got = places.baseline_places(self.repo, self.rev)
        self.assertEqual(self.keys(got, SEND), ["Send", "Cancel", "Hello", "%d coins"])


class CurrentModernExtractionTests(PlacesCase):
    """Swift files under DashWallet/ with no compiler .stringsdata source entry are extracted
    with --modern-localizable-strings."""

    def test_string_localized_in_a_file_without_compiler_data_is_a_place(self):
        derived = self.stringsdata("same")
        self.write("DashWallet/Sources/Only.swift", 'import Foundation\nlet a = String(localized: "Literal")\n')
        got = [p for p in places.current_places(self.repo, derived) if p.file == "DashWallet/Sources/Only.swift"]
        self.assertEqual([(p.key, p.line) for p in got], [("Literal", 2)])

    def test_interpolation_is_a_place_at_its_position(self):
        # the lightweight tool cannot derive the interpolation key (it reports "%arg coins"),
        # so only the position is asserted: the place must exist for pairing by ordinal
        derived = self.stringsdata("same")
        self.write("DashWallet/Sources/Only.swift",
                   'import Foundation\nfunc f(_ n: Int) -> String { String(localized: "\\(n) coins") }\n')
        got = [(p.line, p.column) for p in places.current_places(self.repo, derived)
               if p.file == "DashWallet/Sources/Only.swift"]
        self.assertEqual([l for l, _ in got], [2])

    def test_file_with_a_compiler_source_entry_is_not_extracted_again(self):
        derived = self.stringsdata("same")
        self.write(SEND, 'import Foundation\nlet a = String(localized: "Extra")\n')
        got = places.current_places(self.repo, derived)
        self.assertNotIn("Extra", [p.key for p in got])
        self.assertEqual(len([p for p in got if p.file == SEND]), 4)


class PairTests(PlacesCase):
    def pairs_at_baseline(self, set_name):
        base = places.baseline_places(self.repo, self.rev)
        cur = places.current_places(self.repo, self.stringsdata(set_name))
        return places.pair(base, cur)

    def test_no_rewrite_every_place_pairs_to_an_identical_key(self):
        pairs, mismatched = self.pairs_at_baseline("same")
        self.assertEqual(mismatched, [])
        self.assertEqual(len(pairs), 6)  # 4 in Send.swift, 2 in Legacy.m
        for b, c in pairs:
            self.assertEqual((b.file, b.key), (c.file, c.key))

    def test_rewritten_place_pairs_old_key_with_derived_key_by_ordinal(self):
        pairs, mismatched = self.pairs_at_baseline("rewritten")
        self.assertEqual(mismatched, [])
        by_base = {b.key: (c.key, c.line) for b, c in pairs}
        self.assertEqual(by_base["%d coins"], ("%lld coins", 7))
        self.assertEqual(by_base["Send"], ("Send", 4))

    def test_two_places_on_one_line_pair_in_column_order(self):
        # current fixture lists Cancel (col 37) before Send (col 23)
        pairs, _ = self.pairs_at_baseline("rewritten")
        by_base = {b.key: c.key for b, c in pairs}
        self.assertEqual((by_base["Send"], by_base["Cancel"]), ("Send", "Cancel"))

    def test_file_only_at_baseline_is_named_with_zero_now(self):
        self.write("DashWallet/Sources/Gone.swift", 'import SwiftUI\nlet a = Text("Send")\n')
        self.rev = self.commit("gone")
        _, mismatched = self.pairs_at_baseline("same")
        self.assertEqual(mismatched, [("DashWallet/Sources/Gone.swift", 1, 0)])

    def test_file_only_now_is_named_with_zero_at_baseline(self):
        derived = self.stringsdata("same")
        self.write_stringsdata(derived, "New.stringsdata", "DashWallet/Sources/New.swift",
                               [("Send", 1, 1), ("Cancel", 2, 1)])
        base = places.baseline_places(self.repo, self.rev)
        cur = places.current_places(self.repo, derived)
        _, mismatched = places.pair(base, cur)
        self.assertEqual(mismatched, [("DashWallet/Sources/New.swift", 0, 2)])

    def test_merged_lookups_are_a_named_mismatch_and_not_repaired(self):
        derived = self.stringsdata("same")
        # Send.swift now has 3 places instead of 4: two lookups merged into one
        self.write_stringsdata(derived, "Send.stringsdata", SEND,
                               [("Send", 4, 23), ("Hello", 6, 48), ("%d coins", 7, 71)])
        os.remove(os.path.join(derived, "same", "Send.stringsdata"))
        base = places.baseline_places(self.repo, self.rev)
        cur = places.current_places(self.repo, derived)
        pairs, mismatched = places.pair(base, cur)
        self.assertEqual(mismatched, [(SEND, 4, 3)])
        self.assertEqual([b.file for b, _ in pairs], [LEGACY, LEGACY])

    def test_mismatched_files_are_sorted_by_file(self):
        base = [places.Place("b.swift", 1, 1, "k"), places.Place("a.swift", 1, 1, "k")]
        _, mismatched = places.pair(base, [])
        self.assertEqual(mismatched, [("a.swift", 1, 0), ("b.swift", 1, 0)])

    def test_pair_orders_by_line_then_column_regardless_of_input_order(self):
        b = [places.Place("f.swift", 2, 1, "B2"), places.Place("f.swift", 1, 9, "B1b"),
             places.Place("f.swift", 1, 2, "B1a")]
        c = [places.Place("f.swift", 1, 2, "C1a"), places.Place("f.swift", 2, 1, "C2"),
             places.Place("f.swift", 1, 9, "C1b")]
        pairs, mismatched = places.pair(b, c)
        self.assertEqual(mismatched, [])
        self.assertEqual([(x.key, y.key) for x, y in pairs],
                         [("B1a", "C1a"), ("B1b", "C1b"), ("B2", "C2")])


class BuildIsStaleTests(PlacesCase):
    def setUp(self):
        super().setUp()
        self.derived = self.stringsdata("same")
        self.sd = os.path.join(self.derived, "same", "Send.stringsdata")
        self.swift = os.path.join(self.repo, SEND)

    def test_stale_when_a_swift_file_is_newer_than_every_stringsdata(self):
        os.utime(self.sd, (1000, 1000))
        os.utime(self.swift, (2000, 2000))
        self.assertTrue(places.build_is_stale(self.repo, self.derived))

    def test_fresh_when_newest_stringsdata_is_newer_than_every_swift_file(self):
        os.utime(self.swift, (1000, 1000))
        for root, _, files in os.walk(os.path.join(self.repo, "DashWallet")):
            for fn in files:
                os.utime(os.path.join(root, fn), (1000, 1000))
        os.utime(self.sd, (2000, 2000))
        self.assertFalse(places.build_is_stale(self.repo, self.derived))

    def test_newest_stringsdata_counts_not_the_oldest(self):
        self.stringsdata("same-x86")
        old = os.path.join(self.derived, "same", "Send.stringsdata")
        new = os.path.join(self.derived, "same-x86", "Send.stringsdata")
        os.utime(self.swift, (1500, 1500))
        os.utime(old, (1000, 1000))
        os.utime(new, (2000, 2000))
        self.assertFalse(places.build_is_stale(self.repo, self.derived))

    def test_swift_file_outside_app_folder_does_not_make_build_stale(self):
        for root, _, files in os.walk(os.path.join(self.repo, "DashWallet")):
            for fn in files:
                os.utime(os.path.join(root, fn), (1000, 1000))
        os.utime(self.sd, (2000, 2000))
        self.write("DashWalletTests/T.swift", "let x = 1\n")
        os.utime(os.path.join(self.repo, "DashWalletTests/T.swift"), (3000, 3000))
        self.assertFalse(places.build_is_stale(self.repo, self.derived))

    def test_no_stringsdata_raises_specific_error(self):
        empty = os.path.join(self.tmp, "empty")
        os.makedirs(empty)
        with self.assertRaises(places.NoStringsdataError):
            places.build_is_stale(self.repo, empty)


if __name__ == "__main__":
    unittest.main()

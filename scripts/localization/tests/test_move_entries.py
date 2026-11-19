"""Tests for the entry mover (T9: AC-06).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

API under test (scripts/localization/move_entries.py):

  plan_moves(pairs, objc_keys)            -> sorted distinct (old, new) where a paired
                                             place's key changed; MoveError if old is in
                                             objc_keys (names the key).
  apply_moves(catalog, moves, current_keys) -> new catalog; the old key is removed unless
                                             in current_keys; MoveError names both keys on
                                             a clash with different wording.
  run_moves(catalog_path, pairs, objc_keys) -> moves; writes via catalog_io, file untouched
                                             on error.
"""
import copy
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
FIXTURE = os.path.join(LOCALIZATION_DIR, "fixtures", "move", "catalog.json")
sys.path.insert(0, LOCALIZATION_DIR)

import catalog_io  # noqa: E402
import move_entries  # noqa: E402
from places import Place  # noqa: E402

F = "DashWallet/Sources/A.swift"


def load():
    with open(FIXTURE, encoding="utf-8") as f:
        return json.load(f)


def pairs_for(moves):
    return [(Place(F, i + 1, 1, old), Place(F, i + 1, 1, new)) for i, (old, new) in enumerate(moves)]


def value(catalog, key, locale):
    return catalog["strings"][key]["localizations"][locale]["stringUnit"]["value"]


def forms(catalog, key, locale):
    plural = catalog["strings"][key]["localizations"][locale]["variations"]["plural"]
    return {c: u["stringUnit"]["value"] for c, u in plural.items()}


def move(moves, current=()):
    return move_entries.apply_moves(load(), moves, set(current))


class PlanCase(unittest.TestCase):
    def test_collects_changed_keys_sorted_and_distinct(self):
        pairs = pairs_for([("%d b", "%lld b"), ("%d a", "%lld a"), ("same", "same"), ("%d a", "%lld a")])
        self.assertEqual(move_entries.plan_moves(pairs, set()),
                         [("%d a", "%lld a"), ("%d b", "%lld b")])

    def test_one_key_two_derived_keys_gives_two_moves(self):
        pairs = pairs_for([("%d left", "%lld left"), ("%d left", "%llu left")])
        self.assertEqual(move_entries.plan_moves(pairs, set()),
                         [("%d left", "%lld left"), ("%d left", "%llu left")])

    def test_key_shared_with_objc_is_an_error_naming_it(self):
        pairs = pairs_for([("%d shared", "%lld shared")])
        with self.assertRaises(move_entries.MoveError) as cm:
            move_entries.plan_moves(pairs, {"%d shared"})
        self.assertIn("%d shared", str(cm.exception))


class RewriteCase(unittest.TestCase):
    def test_d_becomes_lld_in_all_locales(self):
        c = move([("%d items", "%lld items")])
        self.assertEqual(value(c, "%lld items", "en"), "%lld items")
        self.assertEqual(value(c, "%lld items", "de"), "%lld Elemente")
        self.assertEqual(value(c, "%lld items", "uk"), "%lld елементів")
        self.assertNotIn("%d items", c["strings"])

    def test_swapped_translation_keeps_positions(self):
        c = move([("%1$d from %2$@", "%lld from %@")])
        self.assertEqual(value(c, "%lld from %@", "de"), "%2$@ hat %1$lld")
        self.assertEqual(value(c, "%lld from %@", "uk"), "%1$lld від %2$@")

    def test_english_of_multi_argument_key_is_positional(self):
        c = move([("%1$d from %2$@", "%lld from %@")])
        self.assertEqual(value(c, "%lld from %@", "en"), "%1$lld from %2$@")
        c = move([("%d of %d", "%lld of %lld")])
        self.assertEqual(value(c, "%lld of %lld", "en"), "%1$lld of %2$lld")

    def test_percent_percent_untouched(self):
        c = move([("%d%% done", "%lld%% done")])
        self.assertEqual(value(c, "%lld%% done", "en"), "%lld%% done")
        self.assertEqual(value(c, "%lld%% done", "de"), "%lld%% fertig")

    def test_unsigned_and_long(self):
        c = move([("%u points", "%llu points"), ("%ld steps", "%lld steps")])
        self.assertEqual(value(c, "%llu points", "de"), "%llu Punkte")
        self.assertEqual(value(c, "%lld steps", "de"), "%lld Schritte")

    def test_plural_variations_rewritten_in_every_form(self):
        c = move([("%d files", "%lld files")])
        self.assertEqual(forms(c, "%lld files", "en"), {"one": "%lld file", "other": "%lld files"})
        self.assertEqual(forms(c, "%lld files", "de"), {"one": "%lld Datei", "other": "%lld Dateien"})

    def test_substitutions_rewritten_and_arg_untouched(self):
        c = move([("%#@files@ in %d folders", "%lld files in %lld folders")])
        locs = c["strings"]["%lld files in %lld folders"]["localizations"]
        self.assertEqual(locs["en"]["stringUnit"]["value"], "%1$#@files@ in %2$lld folders")
        self.assertEqual(locs["de"]["stringUnit"]["value"], "%#@files@ in %lld Ordnern")
        for lc, one in (("en", "%arg file"), ("de", "%arg Datei")):
            sub = locs[lc]["substitutions"]["files"]
            self.assertEqual(sub["formatSpecifier"], "lld")
            self.assertEqual(sub["argNum"], 1)
            self.assertEqual(sub["variations"]["plural"]["one"]["stringUnit"]["value"], one)

    def test_translation_with_fewer_codes_rewrites_only_its_codes(self):
        c = move([("%d of %d", "%lld of %lld")])
        self.assertEqual(value(c, "%lld of %lld", "de"), "nur %lld")
        self.assertEqual(value(c, "%lld of %lld", "uk"), "Готово")

    def test_input_catalog_is_not_mutated(self):
        before = load()
        move([("%d items", "%lld items")])
        self.assertEqual(before, load())


class RemovalCase(unittest.TestCase):
    def test_old_key_removed_without_unused_copy(self):
        c = move([("%d items", "%lld items"), ("%u points", "%llu points")])
        self.assertNotIn("%d items", c["strings"])
        self.assertNotIn("%u points", c["strings"])
        for entry in c["strings"].values():
            self.assertNotIn("extractionState", entry)

    def test_old_key_kept_when_another_place_still_uses_it(self):
        c = move([("%d tries", "%lld tries")], current=["%d tries"])
        self.assertEqual(value(c, "%d tries", "de"), "%d Versuche")
        self.assertEqual(value(c, "%lld tries", "de"), "%lld Versuche")

    def test_one_key_two_derived_keys_both_copied_old_removed(self):
        c = move([("%d left", "%lld left"), ("%d left", "%llu left")])
        self.assertEqual(value(c, "%lld left", "de"), "%lld übrig")
        self.assertEqual(value(c, "%llu left", "de"), "%llu übrig")
        self.assertNotIn("%d left", c["strings"])

    def test_untouched_entries_stay(self):
        c = move([("%d items", "%lld items")])
        self.assertEqual(c["strings"]["Plain"], load()["strings"]["Plain"])


class ClashCase(unittest.TestCase):
    def clashing(self):
        c = load()
        c["strings"]["%lld items"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "%lld other wording"}}}}
        return c

    def test_derived_key_with_different_wording_is_an_error_naming_both(self):
        with self.assertRaises(move_entries.MoveError) as cm:
            move_entries.apply_moves(self.clashing(), [("%d items", "%lld items")], set())
        self.assertIn("%d items", str(cm.exception))
        self.assertIn("%lld items", str(cm.exception))

    def test_run_writes_nothing_on_a_clash(self):
        tmp = tempfile.mkdtemp(prefix="move-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "Localizable.xcstrings")
        catalog_io.write_catalog(path, self.clashing())
        with open(path, "rb") as f:
            before = f.read()
        with self.assertRaises(move_entries.MoveError):
            move_entries.run_moves(path, pairs_for([("%d items", "%lld items")]), set())
        with open(path, "rb") as f:
            self.assertEqual(before, f.read())


class RunCase(unittest.TestCase):
    def test_second_run_is_byte_identical(self):
        tmp = tempfile.mkdtemp(prefix="move-")
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        path = os.path.join(tmp, "Localizable.xcstrings")
        catalog_io.write_catalog(path, load())
        pairs = pairs_for([("%d items", "%lld items"), ("%1$d from %2$@", "%lld from %@"),
                           ("%d tries", "%lld tries"), ("%d tries", "%d tries")])
        move_entries.run_moves(path, pairs, set())
        with open(path, "rb") as f:
            first = f.read()
        move_entries.run_moves(path, pairs, set())
        with open(path, "rb") as f:
            self.assertEqual(first, f.read())


if __name__ == "__main__":
    unittest.main()

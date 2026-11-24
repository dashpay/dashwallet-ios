"""Tests for catalog_io.publish_text: the one writer of the key map and the plural-fidelity fixture.

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

Contract: publish_text(path, text, expect) writes `text` to `path` atomically, and only while every
file named in `expect` ({path: the bytes the caller read, or None for a file that did not exist})
still holds them; otherwise it raises CatalogIOError, writes nothing and leaves no staging file.
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import catalog_io  # noqa: E402


class PublishTextTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="catalog-io-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.source = os.path.join(self.tmp, "Localizable.xcstrings")
        self.out = os.path.join(self.tmp, "map.json")
        for path, text in ((self.source, b"source v1"), (self.out, b"old map")):
            with open(path, "wb") as f:
                f.write(text)

    def read(self, path):
        with open(path, "rb") as f:
            return f.read()

    def test_writes_while_every_read_file_is_unchanged(self):
        catalog_io.publish_text(self.out, "new map\n", {self.source: b"source v1", self.out: b"old map"})
        self.assertEqual(self.read(self.out), b"new map\n")
        self.assertEqual(sorted(os.listdir(self.tmp)), ["Localizable.xcstrings", "map.json"])

    def test_a_source_saved_after_it_was_read_refuses_the_write(self):
        with open(self.source, "wb") as f:
            f.write(b"source v2")
        with self.assertRaises(catalog_io.CatalogIOError) as cm:
            catalog_io.publish_text(self.out, "new map\n", {self.source: b"source v1"})
        self.assertIn(self.source, str(cm.exception))
        self.assertEqual(self.read(self.out), b"old map")
        self.assertEqual(sorted(os.listdir(self.tmp)), ["Localizable.xcstrings", "map.json"])

    def test_an_edit_of_the_target_itself_is_not_overwritten(self):
        with open(self.out, "wb") as f:
            f.write(b"hand-edited map")
        with self.assertRaises(catalog_io.CatalogIOError):
            catalog_io.publish_text(self.out, "new map\n", {self.out: b"old map"})
        self.assertEqual(self.read(self.out), b"hand-edited map")

    def test_a_file_that_appeared_after_it_was_read_as_absent_refuses_the_write(self):
        fresh = os.path.join(self.tmp, "fresh.json")
        with open(fresh, "wb") as f:
            f.write(b"someone else's")
        with self.assertRaises(catalog_io.CatalogIOError):
            catalog_io.publish_text(fresh, "mine\n", {fresh: None})
        self.assertEqual(self.read(fresh), b"someone else's")

    def test_read_bytes_is_none_for_a_missing_file(self):
        self.assertIsNone(catalog_io.read_bytes(os.path.join(self.tmp, "missing")))
        self.assertEqual(catalog_io.read_bytes(self.source), b"source v1")


class WritersGoThroughPublishTextTest(unittest.TestCase):
    """The key map and the plural-fidelity fixture refuse to replace what changed since it was read."""

    def setUp(self):
        import zero_loss_check
        self.zl = zero_loss_check
        self.repo = tempfile.mkdtemp(prefix="catalog-io-repo-")
        self.addCleanup(shutil.rmtree, self.repo, True)
        self.catalog = os.path.join(self.repo, zero_loss_check.CATALOG)
        self.key_map = os.path.join(self.repo, zero_loss_check.KEY_MAP)
        for path, text in ((self.catalog, b'{"strings": {}}'), (self.key_map, b'{"old": 1}\n')):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(text)
        self.read_before = {self.catalog: b'{"strings": {}}', self.key_map: b'{"old": 1}\n'}

    def test_the_key_map_is_not_written_over_a_catalog_saved_after_the_run_read_it(self):
        with open(self.catalog, "wb") as f:
            f.write(b'{"strings": {"saved later": {}}}')
        with self.assertRaises(catalog_io.CatalogIOError):
            self.zl.write_key_map(self.repo, "0" * 40, {"a": ["a"]}, self.read_before)
        with open(self.key_map, "rb") as f:
            self.assertEqual(f.read(), b'{"old": 1}\n')

    def test_the_key_map_is_written_when_nothing_changed(self):
        self.zl.write_key_map(self.repo, "0" * 40, {"a": ["a"]}, self.read_before)
        with open(self.key_map, encoding="utf-8") as f:
            self.assertEqual(json.load(f), {"baseline": "0" * 40, "keys": {"a": ["a"]}})

    def test_the_fixture_is_not_written_from_a_key_map_changed_after_it_was_read(self):
        import baseline_plural_forms
        with open(self.key_map, "wb") as f:
            f.write(b'{"new": 2}\n')
        with self.assertRaises(catalog_io.CatalogIOError):
            baseline_plural_forms.write_fixture(self.repo, {"counts": []}, b'{"old": 1}\n')
        self.assertFalse(os.path.exists(os.path.join(self.repo, baseline_plural_forms.OUT)))


if __name__ == "__main__":
    unittest.main()

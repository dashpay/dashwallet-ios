"""Tests for the Catalog generator (T2: AC-06, AC-07, AC-18).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

The Baseline lists live in a temporary git repository built in setUp from
scripts/localization/fixtures/catalog/<set>/, committed under DashWallet/.
The generator must read them with `git show <rev>:<path>`, so tests also
change the working tree and add later commits and expect the output to follow
the requested revision only.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
FIXTURES = os.path.join(LOCALIZATION_DIR, "fixtures", "catalog")
GENERATOR = os.path.join(LOCALIZATION_DIR, "generate_catalog.py")
sys.path.insert(0, LOCALIZATION_DIR)


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True,
                          capture_output=True, text=True).stdout.strip()


class RepoCase(unittest.TestCase):
    """Builds a temp git repo whose DashWallet/ holds a fixture set."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="catalog-gen-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(self.repo)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "commit.gpgsign", "false")
        self.out = os.path.join(self.tmp, "Localizable.xcstrings")

    def load_fixture(self, name):
        src = os.path.join(FIXTURES, name)
        dst = os.path.join(self.repo, "DashWallet")
        shutil.copytree(src, dst, dirs_exist_ok=True)

    def commit(self, msg="baseline"):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", msg)
        return git(self.repo, "rev-parse", "HEAD")

    def run_gen(self, rev, out=None):
        return subprocess.run(
            [sys.executable, GENERATOR, "--rev", rev, "--repo", self.repo,
             "--out", out or self.out],
            capture_output=True, text=True)

    def generate(self, rev):
        res = self.run_gen(rev)
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(self.out, "rb") as f:
            self.raw = f.read()
        return json.loads(self.raw.decode("utf-8"))

    def ordered(self):
        return json.loads(self.raw.decode("utf-8"), object_pairs_hook=OrderedDict)


class GenerateCatalogTests(RepoCase):
    def setUp(self):
        super().setUp()
        self.load_fixture("ok")
        self.rev = self.commit()
        self.cat = self.generate(self.rev)
        self.strings = self.cat["strings"]

    def loc(self, key, locale):
        return self.strings[key]["localizations"][locale]

    # --- top level ---------------------------------------------------------
    def test_top_level_fields(self):
        self.assertEqual(self.cat["sourceLanguage"], "en")
        self.assertEqual(self.cat["version"], "1.0")
        self.assertEqual(sorted(self.cat), ["sourceLanguage", "strings", "version"])

    def test_no_extraction_state_and_no_comment(self):
        for key, entry in self.strings.items():
            self.assertNotIn("extractionState", entry, key)
            self.assertNotIn("comment", entry, key)
            self.assertEqual(list(entry), ["localizations"], key)

    # --- plain keys --------------------------------------------------------
    def test_plain_key_per_locale(self):
        self.assertEqual(self.loc("Send", "en"), unit("Send"))
        self.assertEqual(self.loc("Send", "de"), unit("Senden"))

    def test_positional_format_key_kept_verbatim(self):
        key = "Confirmations: %1$d"
        self.assertEqual(self.loc(key, "en"), unit("Confirmations: %1$d"))
        self.assertEqual(self.loc(key, "de"), unit("Bestätigungen: %1$d"))
        self.assertEqual(self.loc(key, "pl"), unit("Potwierdzenia: %1$d"))

    def test_strings_escapes_decoded(self):
        self.assertEqual(self.loc("Quote", "en"), unit('Say "hi"\nnow \\ ok'))
        self.assertEqual(self.loc("Café", "en"), unit("Café time"))

    def test_comments_in_lists_are_not_carried(self):
        self.assertNotIn("Button title", self.raw.decode("utf-8"))

    def test_key_missing_in_a_locale(self):
        locs = self.strings["Send"]["localizations"]
        self.assertNotIn("pl", locs)
        self.assertEqual(sorted(self.strings["Size"]["localizations"]), ["de", "en"])

    def test_locale_names_verbatim(self):
        locs = self.strings["Send"]["localizations"]
        self.assertEqual(sorted(locs), sorted(
            ["en", "de", "zh", "zh_TW", "zh-Hans", "zh-Hant-TW", "sl_SI"]))
        self.assertEqual(locs["zh_TW"], unit("發送"))
        self.assertEqual(locs["sl_SI"], unit("Pošlji"))

    # --- plurals (AC-07) ---------------------------------------------------
    def test_plural_in_locale_with_few_and_many(self):
        self.assertEqual(self.loc("contacts_count", "pl"), {"variations": {"plural": {
            "one": unit("%d kontakt"), "few": unit("%d kontakty"),
            "many": unit("%d kontaktów"), "other": unit("%d kontaktu")}}})

    def test_plural_in_en_and_de(self):
        self.assertEqual(self.loc("contacts_count", "en"), {"variations": {"plural": {
            "one": unit("%d contact"), "other": unit("%d contacts")}}})
        self.assertEqual(sorted(self.loc("contacts_count", "de")["variations"]["plural"]),
                         ["one", "other"])

    def test_key_in_strings_and_stringsdict_takes_the_plural_form(self):
        # en has "contacts_count" in both lists; Foundation looks up .stringsdict first.
        en = self.loc("contacts_count", "en")
        self.assertEqual(list(en), ["variations"])
        self.assertNotIn("stringUnit", en)
        self.assertNotIn("old list value", self.raw.decode("utf-8"))
        self.assertEqual(en["variations"]["plural"]["other"], unit("%d contacts"))

    def test_english_only_plural_gives_no_variants_elsewhere(self):
        locs = self.strings["bytes_count"]["localizations"]
        self.assertEqual(list(locs), ["en"])
        self.assertEqual(locs["en"], {"variations": {"plural": {
            "one": unit("%d byte"), "other": unit("%d bytes")}}})

    def test_single_form_other_only_plural_is_plain_string_unit(self):
        self.assertEqual(self.loc("contacts_count", "zh_TW"), unit("%d contacts"))

    def test_plural_with_text_around_variable_uses_substitutions(self):
        expected = {
            "stringUnit": {"state": "translated",
                           "value": "%1$d of %2$#@nodes@ voted"},
            "substitutions": {"nodes": {
                "argNum": 2, "formatSpecifier": "d",
                "variations": {"plural": {
                    "one": unit("%arg node"), "other": unit("%arg nodes")}}}}}
        self.assertEqual(self.loc("voted_progress", "en"), expected)
        de = self.loc("voted_progress", "de")
        self.assertEqual(de["stringUnit"]["value"], "%1$d von %2$#@nodes@ abgegeben")
        self.assertEqual(de["substitutions"]["nodes"]["variations"]["plural"]["other"],
                         unit("%arg Knoten"))
        self.assertNotIn("variations", de)

    def test_plural_form_without_number_uses_substitutions(self):
        self.assertEqual(self.loc("notes_hidden", "en"), {
            "stringUnit": {"state": "translated", "value": "Total: %#@notes@"},
            "substitutions": {"notes": {
                "argNum": 1, "formatSpecifier": "d",
                "variations": {"plural": {
                    "one": unit("note"), "other": unit("notes")}}}}})

    # --- output format (ADR-0071, pilot rule 5) -----------------------------
    def test_bytes_utf8_no_bom_no_trailing_newline(self):
        self.assertFalse(self.raw.startswith(b"\xef\xbb\xbf"))
        self.assertFalse(self.raw.endswith(b"\n"))
        self.assertTrue(self.raw.endswith(b"}"))
        self.raw.decode("utf-8")

    def test_layout_two_space_indent_and_separator(self):
        text = self.raw.decode("utf-8")
        self.assertTrue(text.startswith('{\n  "sourceLanguage" : "en",\n  "strings" : {\n'))
        self.assertIn('\n    "Send" : {\n      "localizations" : {\n', text)
        self.assertTrue(text.endswith('\n  },\n  "version" : "1.0"\n}'))

    def test_non_ascii_unescaped_and_only_required_escapes(self):
        text = self.raw.decode("utf-8")
        self.assertIn("Größe", text)
        self.assertIn("发送", text)
        self.assertNotIn("\\u00", text)
        self.assertNotIn("\\/", text)
        self.assertIn('"Say \\"hi\\"\\nnow \\\\ ok"', text)

    def test_locale_keys_in_localized_standard_order(self):
        locales = list(self.ordered()["strings"]["Send"]["localizations"])
        self.assertEqual(locales,
                         ["de", "en", "sl_SI", "zh", "zh_TW", "zh-Hans", "zh-Hant-TW"])

    def test_plural_categories_in_localized_standard_order(self):
        pl = self.ordered()["strings"]["contacts_count"]["localizations"]["pl"]
        self.assertEqual(list(pl["variations"]["plural"]),
                         ["few", "many", "one", "other"])

    def test_entry_keys_in_localized_standard_order(self):
        keys = list(self.ordered()["strings"])
        self.assertLess(keys.index("apple"), keys.index("Banana"))  # case-insensitive
        self.assertLess(keys.index("Item 2"), keys.index("Item 10"))  # numeric

    # --- determinism and Baseline source (AC-18) ----------------------------
    def test_second_run_byte_identical(self):
        first = self.raw
        second_out = os.path.join(self.tmp, "second.xcstrings")
        res = self.run_gen(self.rev, out=second_out)
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(second_out, "rb") as f:
            self.assertEqual(f.read(), first)

    def test_reads_the_revision_not_the_working_tree(self):
        first = self.raw
        lst = os.path.join(self.repo, "DashWallet", "en.lproj", "Localizable.strings")
        with open(lst, "a", encoding="utf-8") as f:
            f.write('"Uncommitted" = "Uncommitted";\n')
        res = self.run_gen(self.rev)
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(self.out, "rb") as f:
            self.assertEqual(f.read(), first)

    def test_later_commit_is_picked_up_by_rev(self):
        lst = os.path.join(self.repo, "DashWallet", "de.lproj", "Localizable.strings")
        with open(lst, "a", encoding="utf-8") as f:
            f.write('"Send later" = "Später senden";\n')
        en = os.path.join(self.repo, "DashWallet", "en.lproj", "Localizable.strings")
        with open(en, "a", encoding="utf-8") as f:
            f.write('"Send later" = "Send later";\n')
        new_rev = self.commit("develop gained a text")
        cat = self.generate(new_rev)
        self.assertEqual(cat["strings"]["Send later"]["localizations"]["de"],
                         unit("Später senden"))
        old = self.generate(self.rev)
        self.assertNotIn("Send later", old["strings"])


class FailureTests(RepoCase):
    def assert_fails(self, fixture, expect_in_stderr):
        self.load_fixture(fixture)
        rev = self.commit()
        res = self.run_gen(rev)
        self.assertNotEqual(res.returncode, 0)
        for needle in expect_in_stderr:
            self.assertIn(needle, res.stderr)
        self.assertFalse(os.path.exists(self.out), "nothing may be written on failure")

    def test_duplicate_key_names_file_and_key(self):
        self.assert_fails("dup", ["en.lproj/Localizable.strings", "Alpha"])

    def test_unparseable_strings_list_fails(self):
        self.assert_fails("unparseable", ["en.lproj/Localizable.strings"])

    def test_unknown_stringsdict_shape_names_file_and_key(self):
        self.assert_fails("badshape", ["en.lproj/Localizable.stringsdict", "weird_entry"])

    def test_failure_does_not_replace_an_existing_output(self):
        with open(self.out, "wb") as f:
            f.write(b"previous")
        self.load_fixture("dup")
        res = self.run_gen(self.commit())
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("Alpha", res.stderr)
        with open(self.out, "rb") as f:
            self.assertEqual(f.read(), b"previous")


class CatalogIoTests(unittest.TestCase):
    """catalog_io.write_catalog(path, catalog) / read_catalog(path): shared with T9."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="catalog-io-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.path = os.path.join(self.tmp, "c.xcstrings")

    def test_empty_object_layout_and_roundtrip(self):
        import catalog_io
        cat = {"version": "1.0", "strings": {}, "sourceLanguage": "en"}
        catalog_io.write_catalog(self.path, cat)
        with open(self.path, "rb") as f:
            raw = f.read()
        self.assertEqual(
            raw.decode("utf-8"),
            '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}')
        self.assertEqual(catalog_io.read_catalog(self.path), cat)

    def test_escaping(self):
        import catalog_io
        value = 'a"b\\c\nd\té/ü€\x01'
        cat = {"sourceLanguage": "en", "version": "1.0",
               "strings": {"k": {"localizations": {"en": unit(value)}}}}
        catalog_io.write_catalog(self.path, cat)
        with open(self.path, "rb") as f:
            text = f.read().decode("utf-8")
        self.assertIn('"a\\"b\\\\c\\nd\\té/ü€\\u0001"', text)
        self.assertEqual(catalog_io.read_catalog(self.path), cat)


if __name__ == "__main__":
    unittest.main()

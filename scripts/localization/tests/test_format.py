"""Tests for the Foundation formatter wrapper (AC-02, AC-10).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

API under test (scripts/localization/foundation_format.py, see its docstring):
format_texts(lproj_root, [(locale, key, args_or_None)]) -> [{"locale", "key", "args", "text"}]
and `foundation_format.py --self-test` (exit 0 / 2; FORMATTER_FORCE_ROUTE forces the wrong route).
Fixtures: fixtures/format/<locale>.lproj for en, uk, zh-Hant-TW, de.
"""
import os
import subprocess
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
ROOT = os.path.join(LOCALIZATION_DIR, "fixtures", "format")
sys.path.insert(0, LOCALIZATION_DIR)

import foundation_format as formatter  # noqa: E402

COUNTS = (0, 1, 2, 5, 21, 101)
PARCELS = "%d parcels"
VISITED = "Visited %1$d of %2$#@places@ today"
SENTINEL = "\u27c2format-crash"
EN_ENV = {"LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"}


def fmt(locale, key, args=None):
    return formatter.format_texts(ROOT, [(locale, key, args)])[0]["text"]


class CountedPhraseTests(unittest.TestCase):
    def test_uk_forms_for_1_2_5_21(self):
        texts = [fmt("uk", PARCELS, [n]) for n in (1, 2, 5, 21)]
        self.assertEqual(texts, ["1 посилка", "2 посилки", "5 посилок", "21 посилка"])
        self.assertNotEqual(texts[1], texts[2])

    def test_batch_with_en_de_uk_uses_each_locale_in_an_en_process(self):
        reqs = [(loc, PARCELS, [n]) for n in (1, 2, 5, 21) for loc in ("en", "de", "uk")]
        with mock.patch.dict(os.environ, EN_ENV):
            out = formatter.format_texts(ROOT, reqs)
        got = {(r["locale"], r["args"][0]): r["text"] for r in out}
        self.assertEqual([r["locale"] for r in out], [q[0] for q in reqs])
        self.assertEqual([got[("uk", n)] for n in (1, 2, 5, 21)],
                         ["1 посилка", "2 посилки", "5 посилок", "21 посилка"])
        self.assertEqual([got[("en", n)] for n in (1, 2, 5, 21)],
                         ["1 parcel", "2 parcels", "5 parcels", "21 parcels"])
        self.assertEqual([got[("de", n)] for n in (1, 2, 5, 21)],
                         ["1 Paket", "2 Pakete", "5 Pakete", "21 Pakete"])

    def test_one_form_locale_uses_other_for_all_counts(self):
        for n in COUNTS:
            self.assertEqual(fmt("zh-Hant-TW", PARCELS, [n]), "%d 個包裹" % n)

    def test_text_around_the_counted_variable(self):
        self.assertEqual(fmt("en", VISITED, [3, 1]), "Visited 3 of 1 place today")
        self.assertEqual(fmt("en", VISITED, [3, 5]), "Visited 3 of 5 places today")
        self.assertEqual(fmt("uk", VISITED, [3, 2]), "Відвідано 3 з 2 місця сьогодні")
        self.assertEqual(fmt("uk", VISITED, [3, 5]), "Відвідано 3 з 5 місць сьогодні")


class PlainFormatTests(unittest.TestCase):
    def test_positional_swap_formats_by_position(self):
        res = formatter.format_texts(ROOT, [("de", "%1$d items for %2$@", None)])[0]
        self.assertEqual(res["text"], "‹a2› hat 1.001 Einträge")
        self.assertEqual(fmt("en", "%1$d items for %2$@"), "1,001 items for ‹a2›")

    def test_explicit_args_are_used_and_reported(self):
        res = formatter.format_texts(ROOT, [("de", "Hello %@", ["Mia"])])[0]
        self.assertEqual((res["locale"], res["key"], res["args"], res["text"]),
                         ("de", "Hello %@", ["Mia"], "Hallo Mia"))

    def test_double_percent_gives_one_percent(self):
        self.assertEqual(fmt("de", "Progress %d%%"), "Fortschritt 1.001%")
        self.assertEqual(fmt("uk", "Progress %d%%"), "Прогрес 1\u00a0001%")

    def test_key_absent_in_locale_returns_the_key(self):
        self.assertEqual(fmt("de", "Only in English"), "Only in English")
        self.assertEqual(fmt("uk", "No such key anywhere"), "No such key anywhere")

    def test_mismatched_codes_do_not_crash(self):
        # en has two %d, the de translation only one: Foundation drops the second argument.
        self.assertEqual(fmt("de", "Sum %d and %d"), "Summe 1.001")
        self.assertEqual(fmt("en", "Sum %d and %d"), "Sum 1,001 and 1,002")

    def test_sample_types_are_inferred_with_distinct_values_per_position(self):
        res = formatter.format_texts(ROOT, [("en", "Mix %@ %d %ld %lld %u %f", None)])[0]
        self.assertEqual(res["text"], "Mix ‹a1› 1,002 1,003 1,004 1,005 1,006.500000")
        self.assertEqual(res["args"], ["‹a1›", 1002, 1003, 1004, 1005, 1006.5])

    def test_string_sample_per_locale_table(self):
        self.assertEqual(fmt("zh-Hant-TW", "Hello %@"), "你好，‹a1›")
        self.assertEqual(fmt("uk", "Hello %@"), "Привіт, ‹a1›")


class RawAndCrashTests(unittest.TestCase):
    RAW = ["Price rose more than 50% since the last update.", "Spaced 100% sure", "Literal %% only"]

    def test_no_args_and_no_codes_returns_table_text_raw(self):
        for key in self.RAW:
            for loc in ("en", "de", "uk"):  # de/uk lack the key: the key itself, raw
                self.assertEqual(fmt(loc, key), key, (loc, key))

    def test_raw_return_is_deterministic(self):
        reqs = [("en", k, None) for k in self.RAW]
        first = formatter.format_texts(ROOT, reqs)
        second = formatter.format_texts(ROOT, reqs)
        self.assertEqual([r["text"] for r in first], self.RAW)
        self.assertEqual(first, second)

    def test_crashing_request_yields_the_sentinel(self):
        self.assertEqual(fmt("ja", "%d shops in %@", [3, "x"]), SENTINEL)
        self.assertEqual(fmt("ja", "%d shops in %@"), SENTINEL)

    def test_crash_does_not_kill_the_rest_of_the_batch(self):
        reqs = [("en", "Hello %@", ["A"]), ("ja", "%d shops in %@", [3, "x"]),
                ("de", "Hello %@", ["B"]), ("en", "%d shops in %@", [3, "x"]),
                ("ja", "%d shops in %@", [3, "x"]), ("en", "Hello %@", ["C"])]
        out = formatter.format_texts(ROOT, reqs)
        self.assertEqual([r["text"] for r in out],
                         ["Hello A", SENTINEL, "Hallo B", "3 shops in x", SENTINEL, "Hello C"])
        self.assertEqual(out, formatter.format_texts(ROOT, reqs))


class SelfTestTests(unittest.TestCase):
    SCRIPT = os.path.join(LOCALIZATION_DIR, "foundation_format.py")

    def run_self_test(self, extra_env):
        env = dict(os.environ, **EN_ENV)
        env.pop(formatter.FORCE_ROUTE_ENV, None)
        env.update(extra_env)
        return subprocess.run([sys.executable, self.SCRIPT, "--self-test"],
                              capture_output=True, text=True, env=env)

    def test_right_route_exits_0(self):
        res = self.run_self_test({})
        self.assertEqual(res.returncode, 0, res.stderr)

    def test_forced_wrong_route_exits_2(self):
        res = self.run_self_test({formatter.FORCE_ROUTE_ENV: formatter.WRONG_ROUTE})
        self.assertEqual(res.returncode, 2, res.stderr)
        self.assertTrue(res.stderr.strip(), "a failed self-test must say why on stderr")


if __name__ == "__main__":
    unittest.main()

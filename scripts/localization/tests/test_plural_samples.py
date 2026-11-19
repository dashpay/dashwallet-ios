"""Every plural position of a counted phrase gets its own count in the check's samples.

A phrase with two plural variables (%#@files@ in %#@folders@) that the move leaves with its arguments
swapped formats differently only when the two positions carry different counts. The zero-loss check and
the plural-fidelity fixture writer read the samples from one sampler, zero_loss_check.counted_samples.
"""
import ast
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

LOCALIZATION_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, LOCALIZATION_DIR)

import baseline_lists  # noqa: E402
import catalog_io  # noqa: E402
import zero_loss_check as zl  # noqa: E402

KEY = "%d files in %d folders"
COUNTS = (0, 1, 2, 5, 21, 101)


def plural(value_type, one, other):
    return {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": value_type,
            "one": one, "other": other}


TWO_PLURALS = {"NSStringLocalizedFormatKey": "%#@files@ in %#@folders@",
               "files": plural("d", "%d file", "%d files"),
               "folders": plural("d", "%d folder", "%d folders")}
THREE_PLURALS = {"NSStringLocalizedFormatKey": "%#@a@, %#@b@, %#@c@",
                 "a": plural("d", "%d a", "%d as"), "b": plural("d", "%d b", "%d bs"),
                 "c": plural("d", "%d c", "%d cs")}
ONE_PLURAL = {"NSStringLocalizedFormatKey": "%#@n@", "n": plural("d", "%d coin", "%d coins")}
MIXED = {"NSStringLocalizedFormatKey": "%1$@: %#@files@ in %#@folders@",
         "files": plural("d", "%d file", "%d files"), "folders": plural("d", "%d folder", "%d folders")}


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), check=True, capture_output=True, text=True).stdout.strip()


class SamplerTests(unittest.TestCase):
    def test_every_plural_position_covers_every_count(self):
        for spec, positions in ((ONE_PLURAL, [1]), (TWO_PLURALS, [1, 2]), (THREE_PLURALS, [1, 2, 3])):
            samples = zl.counted_samples(spec)
            self.assertEqual(len(samples), len(COUNTS))
            for p in positions:
                self.assertEqual({s[p - 1] for s in samples}, set(COUNTS), "position %d" % p)

    def test_plural_positions_of_one_sample_differ(self):
        for spec, positions in ((TWO_PLURALS, [1, 2]), (THREE_PLURALS, [1, 2, 3])):
            for sample in zl.counted_samples(spec):
                counts = [sample[p - 1] for p in positions]
                self.assertEqual(len(set(counts)), len(counts), "sample %r repeats a count" % (sample,))

    def test_other_positions_keep_a_distinct_non_count_value(self):
        for sample in zl.counted_samples(MIXED):
            self.assertEqual(len(sample), 3)
            self.assertIsInstance(sample[0], str)
            self.assertNotEqual(sample[1], sample[2])

    def test_one_plural_samples_are_the_counts_in_order(self):
        self.assertEqual([s[0] for s in zl.counted_samples(ONE_PLURAL)], list(COUNTS))


class SharedSamplerTests(unittest.TestCase):
    def test_plural_fixture_writer_reads_the_samples_from_the_same_sampler(self):
        path = os.path.join(LOCALIZATION_DIR, "baseline_plural_forms.py")
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read())
        called = {n.func.attr for n in ast.walk(tree)
                  if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                  and isinstance(n.func.value, ast.Name) and n.func.value.id == "zl"}
        self.assertIn("counted_samples", called)
        self.assertNotIn("counted_args", called, "a second per-count sampler would drift from the check's")


class SwappedArgumentsTests(unittest.TestCase):
    """A two-plural Baseline entry whose current entry swaps the plural arguments is a finding."""

    def setUp(self):
        self.repo = os.path.realpath(tempfile.mkdtemp(prefix="plural-samples-"))
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "commit.gpgsign", "false")
        lproj = os.path.join(self.repo, baseline_lists.LISTS_DIR, "en.lproj")
        os.makedirs(lproj)
        with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write('"unrelated" = "x";\n')
        with open(os.path.join(lproj, "Localizable.stringsdict"), "wb") as f:
            plistlib.dump({KEY: TWO_PLURALS}, f)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "baseline")
        self.rev = git(self.repo, "rev-parse", "HEAD")
        self.base = baseline_lists.build_catalog(self.repo, self.rev)

    def findings_for(self, current):
        os.makedirs(os.path.join(self.repo, "DashWallet"), exist_ok=True)
        catalog_io.write_catalog(os.path.join(self.repo, zl.CATALOG), current)
        _, findings, _ = zl.release_wording_check(self.repo, self.rev, {KEY: [KEY]}, self.base, ["en"])
        return findings

    def test_unchanged_two_plural_entry_passes(self):
        self.assertEqual(self.findings_for(self.base), [])

    def test_swapped_plural_arguments_are_a_finding(self):
        current = baseline_lists.build_catalog(self.repo, self.rev)
        subs = current["strings"][KEY]["localizations"]["en"]["substitutions"]
        subs["files"]["argNum"], subs["folders"]["argNum"] = 2, 1
        findings = self.findings_for(current)
        self.assertEqual(len(findings), 1, findings)


if __name__ == "__main__":
    unittest.main()

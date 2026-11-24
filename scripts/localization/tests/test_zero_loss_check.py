"""Tests for the zero-loss check, pre-merge mode (AC-04, AC-06, AC-09, AC-10, AC-14, AC-15, AC-18).

Run from the repository root:

    python3 -m unittest discover -s scripts/localization/tests -p 'test_*.py'

The CLI (scripts/localization/zero_loss_check.py, contract: scripts/localization/ZERO_LOSS_CHECK.md) is always run as a
subprocess with its working directory at the root of a temporary git repository built in setUp:

  * Baseline commit on branch `develop` (also `refs/remotes/origin/develop`): per-locale lists
    for en/de/uk, Swift/Objective-C sources and two Watch files, from fixtures/zero_loss/repo/.
  * Move commit on branch `work`: Swift rewritten to String(localized:) (fixtures/zero_loss/current/),
    the per-locale lists removed. The Catalog is written into the working tree
    (DashWallet/Localizable.xcstrings) from baseline_lists + the Moved keys `%lld coins` and
    `Sample %lld items`; `Unused thing` and `English only` are Unused entries (extractionState stale).
  * Hand-made .stringsdata in the compiler's shape (fixtures/zero_loss/stringsdata/ok/).

Choices where ZERO_LOSS_CHECK.md is silent (the implementation must follow them or the contract gets amended):
  * the 43-locale rows are the locales of the Baseline lists (3 here), sorted by locale code;
  * the Catalog is read from DashWallet/Localizable.xcstrings of the working tree;
  * the key map goes to <repo root>/scripts/localization/zero_loss_key_map.json (indent not fixed);
  * with `--baseline <rev>` the header parenthesis starts with `--baseline `.
"""
import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LOCALIZATION_DIR = os.path.dirname(HERE)
FIXTURES = os.path.join(LOCALIZATION_DIR, "fixtures", "zero_loss")
CLI = os.path.join(LOCALIZATION_DIR, "zero_loss_check.py")
sys.path.insert(0, LOCALIZATION_DIR)

import catalog_io  # noqa: E402
import foundation_format  # noqa: E402
import baseline_lists  # noqa: E402

SEND = "DashWallet/Sources/Send.swift"
GREETING = "DashWallet/Sources/Greeting.swift"
CATALOG = "DashWallet/Localizable.xcstrings"
KEY_MAP = "scripts/localization/zero_loss_key_map.json"
ITEMS_OLD, ITEMS_NEW = "Sample %d items", "Sample %lld items"
COINS_OLD, COINS_NEW = "%d coins", "%lld coins"
BASELINE_COMMIT_FILE = "baseline-commit"  # written by build_baseline.sh: the full 40-hex commit it built
BASELINE_ROOT_FILE = "baseline-root"  # written by build_baseline.sh: the worktree root the build ran in
UNUSED_KEYS = ("Unused thing", "English only")


def git(repo, *args, env=None):
    return subprocess.run(["git", "-C", repo] + list(args), check=True, capture_output=True,
                          text=True, env=env).stdout.strip()


def fixture(*parts):
    with open(os.path.join(FIXTURES, *parts), encoding="utf-8") as f:
        return f.read()


def finding_fields(line):
    """`FAIL place f:1 locale=de current_key="a" ...` -> (kind, positional, {name: parsed value})."""
    head, _, rest = line.partition(" ")
    assert head == "FAIL", line
    kind, _, rest = rest.partition(" ")
    positional = None
    if not re.match(r"\w+=", rest):
        positional, _, rest = rest.partition(" ")
    fields = {}
    for name, raw in re.findall(r'(\w+)=("(?:[^"\\]|\\.)*"|\S+)', rest):
        fields[name] = json.loads(raw) if raw.startswith('"') else raw
    return kind, positional, fields


def move_values(node):
    """Replace %d by %lld in every string value of a Catalog localization (what the move does)."""
    if isinstance(node, dict):
        return {k: (v.replace("%d", "%lld") if k == "value" and isinstance(v, str) else move_values(v))
                for k, v in node.items()}
    return node


class ZeroLossCase(unittest.TestCase):
    OVERLAY = None  # a fixtures/zero_loss/<dir> copied over the Baseline files before they are committed

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="zero-loss-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.repo = os.path.realpath(os.path.join(self.tmp, "repo"))
        os.makedirs(self.repo)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "commit.gpgsign", "false")
        git(self.repo, "symbolic-ref", "HEAD", "refs/heads/develop")
        shutil.copytree(os.path.join(FIXTURES, "repo"), self.repo, dirs_exist_ok=True)
        if self.OVERLAY:
            shutil.copytree(os.path.join(FIXTURES, self.OVERLAY), self.repo, dirs_exist_ok=True)
        self.baseline = self.commit("baseline")
        git(self.repo, "update-ref", "refs/remotes/origin/develop", self.baseline)
        git(self.repo, "checkout", "-q", "-b", "work")
        self.move_the_code()
        self.cat = self.moved_catalog(self.baseline)
        self.install_catalog()
        self.derived = os.path.join(self.tmp, "derived")
        self.install_stringsdata()
        # the compiler data of a build of the Baseline commit, rooted at some other checkout
        self.baseline_derived = os.path.join(self.tmp, "baseline-derived")
        shutil.copytree(os.path.join(FIXTURES, "baseline_stringsdata"), self.baseline_derived)
        # build_baseline.sh records the commit it built here
        self.write_baseline_record(self.baseline)

    def write_baseline_record(self, sha, folder=None):
        with open(os.path.join(folder or self.baseline_derived, BASELINE_COMMIT_FILE), "w") as f:
            f.write(sha + "\n")

    # -- repository helpers -------------------------------------------------------------

    def commit(self, msg):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", msg)
        return git(self.repo, "rev-parse", "HEAD")

    def write(self, rel, text):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def move_the_code(self):
        for name in ("Send.swift", "Greeting.swift"):
            shutil.copy(os.path.join(FIXTURES, "current", name),
                        os.path.join(self.repo, "DashWallet", "Sources", name))
        for loc in ("en", "de", "uk"):
            shutil.rmtree(os.path.join(self.repo, "DashWallet", loc + ".lproj"))
        os.makedirs(os.path.join(self.repo, os.path.dirname(KEY_MAP)), exist_ok=True)
        self.commit("move")

    def moved_catalog(self, rev):
        """Catalog generated from the lists at `rev`, with the Moved keys and the Unused entries."""
        cat = baseline_lists.build_catalog(self.repo, rev)
        strings = cat["strings"]
        for old, new in ((COINS_OLD, COINS_NEW), (ITEMS_OLD, ITEMS_NEW)):
            strings[new] = move_values(strings.pop(old))
        for key in UNUSED_KEYS:
            strings[key]["extractionState"] = "stale"
        return cat

    def install_catalog(self):
        catalog_io.write_catalog(os.path.join(self.repo, CATALOG), self.cat)

    def install_stringsdata(self):
        for fn in ("Send.stringsdata", "Greeting.stringsdata"):
            self.write_derived(fn, fixture("stringsdata", "ok", fn).replace("__REPO__", self.repo))

    def write_derived(self, name, text):
        os.makedirs(self.derived, exist_ok=True)
        path = os.path.join(self.derived, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        future = time.time() + 600  # a build newer than every source file
        os.utime(path, (future, future))

    def set_places(self, name, source_rel, entries):
        """Replace a .stringsdata with `entries` [(key, line, column)]."""
        doc = {"source": os.path.join(self.repo, source_rel), "version": 1, "tables": {"Localizable": [
            {"key": k, "location": {"startingColumn": c, "startingLine": l}} for k, l, c in entries]}}
        self.write_derived(name, json.dumps(doc, indent=2, sort_keys=True))

    # -- running the CLI ----------------------------------------------------------------

    def run_cli(self, *args, derived=True, cwd=None, env=None, extra_env=None):
        cmd = [sys.executable, CLI] + list(args)
        if derived and "--derived-data" not in args and "--release" not in args:
            cmd += ["--derived-data", self.derived]
        # pre-merge needs the Baseline build's compiler data too (owner decision 2026-11-19)
        if derived and "--baseline-derived-data" not in args and "--release" not in args:
            cmd += ["--baseline-derived-data", self.baseline_derived]
        full_env = dict(os.environ if env is None else env)
        full_env.update(extra_env or {})
        return subprocess.run(cmd, cwd=cwd or self.repo, capture_output=True, text=True,
                              encoding="utf-8", env=full_env)

    def findings(self, res):
        return [l for l in res.stdout.splitlines() if l.startswith("FAIL ")]

    def assert_fails_with(self, res, count):
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertEqual(len(self.findings(res)), count, res.stdout)
        self.assertIn("RESULT: FAIL (%d findings)" % count, res.stdout.splitlines()[-1])

    def assert_cannot_run(self, res, *words):
        self.assertEqual(res.returncode, 2, res.stdout + res.stderr)
        self.assertEqual(res.stdout, "", "exit 2 prints no report")
        lines = res.stderr.strip().splitlines()
        self.assertEqual(len(lines), 1, res.stderr)
        self.assertTrue(lines[0].startswith("error: "), res.stderr)
        if words:
            self.assertTrue(any(w.lower() in lines[0].lower() for w in words), res.stderr)

    def baseline_root(self):
        """The Baseline lists as a folder of <locale>.lproj, to compute expected texts with Foundation."""
        root = os.path.join(self.tmp, "baseline-lists")
        if not os.path.isdir(root):
            os.makedirs(root)
            for loc in ("en", "de", "uk"):
                shutil.copytree(os.path.join(FIXTURES, "repo", "DashWallet", loc + ".lproj"),
                                os.path.join(root, loc + ".lproj"))
        return root

    def fmt(self, locale, key, args=None):
        return foundation_format.format_texts(self.baseline_root(), [(locale, key, args)])[0]["text"]

    def row(self, res, locale):
        for line in res.stdout.splitlines():
            parts = line.split()
            if parts[:1] == [locale] and len(parts) == 3:
                return int(parts[1]), int(parts[2])
        self.fail("no row for %s in\n%s" % (locale, res.stdout))


class PassTests(ZeroLossCase):
    def test_pass_report_is_byte_for_byte_the_golden(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        golden = fixture("golden", "pass_report.txt").replace("{BASELINE12}", self.baseline[:12])
        self.assertEqual(res.stdout, golden)
        self.assertEqual(res.stderr, "")

    def test_pass_is_deterministic(self):
        first, second = self.run_cli(), self.run_cli()
        self.assertEqual((first.returncode, second.returncode), (0, 0), first.stdout + first.stderr)
        self.assertEqual(first.stdout, second.stdout)

    def test_pass_writes_nothing_without_write_key_map(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.repo, KEY_MAP)))

    def test_explicit_baseline_is_named_in_the_header(self):
        res = self.run_cli("--baseline", self.baseline)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(res.stdout.splitlines()[1].split(" (")[0], "baseline: " + self.baseline[:12])
        self.assertRegex(res.stdout.splitlines()[1], r"\(--baseline ")

    def test_help_exits_zero(self):
        res = self.run_cli("--help", derived=False)
        self.assertEqual(res.returncode, 0)
        self.assertIn("usage", res.stdout.lower())
        self.assertIn("--write-key-map", res.stdout)


class BaselineDefectTests(ZeroLossCase):
    """A Baseline translation whose format codes take an argument as the wrong type (de: "%@ in %d Läden"
    for "%d shops in %@") formats undefined text on a phone. It cannot be compared, so it is a
    baseline defect: printed, left out of both columns, not a finding (owner decision 2026-11-19)."""
    OVERLAY = "overlay_crash"

    def defects(self, res):
        return [l for l in res.stdout.splitlines() if l.startswith("DEFECT ")]

    def test_wrong_type_baseline_translation_is_a_defect_not_a_finding(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(self.findings(res), [])
        self.assertIn("RESULT: PASS (0 findings)", res.stdout)
        self.assertEqual(self.row(res, "de"), (4, 4))
        self.assertEqual(self.row(res, "en"), (5, 5))
        self.assertEqual(self.defects(res), [
            'DEFECT DashWallet/Sources/Send.swift:5 locale=de baseline_key="Sample %d items" '
            'translation="%@ in %d Läden"'])
        self.assertIn("baseline defects: 1 left out", res.stdout.splitlines())

    def test_translation_fixed_to_numbered_codes_after_the_move_still_passes(self):
        self.cat["strings"][ITEMS_NEW]["localizations"]["de"]["stringUnit"]["value"] = "%2$@ in %1$lld Läden"
        self.install_catalog()
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(len(self.defects(res)), 1)

    def test_sample_args_read_codes_as_format_swift_does(self):
        import zero_loss_check as z
        # no space flag: "50% since" is prose, as in format.swift's inferArgs
        self.assertEqual(z.sample_args("Prices moved more than 50% since the update."), [])
        self.assertEqual(z.sample_args("%d shops in %@"), [1001, "‹a2›"])
        self.assertEqual(z.sample_args("%2$@ at %1$.1f"), [1001.5, "‹a2›"])

    def test_sample_args_match_format_swift_on_every_code(self):
        # LL3: the crash path judges baseline defects with the Python copy, so it must infer what format.swift does.
        import foundation_format
        import zero_loss_check as z
        texts = [
            "%d shops in %@", "%2$@ at %1$.1f", "%1$ld of %2$lld", "%3$@ then %1$@",
            "%u %hd %hhd %qd %zd %td %jd %Lf", "%x %X %o %O %D %U %i %c %p",
            "%f %F %e %E %g %G", "%'d %+d %-5d %05d %#x %.2f %10.3e",
            "Prices moved more than 50% since the update.", "50%% off %d", "%#@places@ and %d",
        ]
        got = foundation_format.format_texts(os.path.join(LOCALIZATION_DIR, "fixtures", "format"),
                                             [("en", t, None) for t in texts])
        for text, res in zip(texts, got):
            self.assertEqual(res["args"], z.sample_args(text), text)

    def test_sample_args_pattern_is_format_swift_s_pattern(self):
        # Codes the behavioural test cannot format (%s and %S crash with an object argument) read the same pattern.
        import zero_loss_check as z
        with open(os.path.join(LOCALIZATION_DIR, "format.swift"), encoding="utf-8") as f:
            swift = re.search(r'let pattern = "(.*)"', f.read()).group(1).replace("\\\\", "\\")
        self.assertEqual(swift.replace("(hh|h|ll|l|q|z|t|j|L)?", "(?:hh|h|ll|l|q|z|t|j|L)?"), z._SWIFT_CODE.pattern)

    def test_wrong_type_rule(self):
        import zero_loss_check as z
        args = [1001, "‹a2›"]
        self.assertTrue(z.takes_wrong_type("%@ in %d Läden", args))
        self.assertTrue(z.takes_wrong_type("%@ içinde %d satıcılar", args))
        self.assertFalse(z.takes_wrong_type("%d shops in %@", args))
        self.assertFalse(z.takes_wrong_type("%2$@ in %1$d Läden", args))
        self.assertFalse(z.takes_wrong_type("%d Läden", args))
        self.assertFalse(z.takes_wrong_type("100%% sicher", []))
        self.assertTrue(z.takes_wrong_type("%d", ["‹a1›"]))
        self.assertTrue(z.takes_wrong_type("%f", [1001]))
        self.assertFalse(z.takes_wrong_type("%.1f km", [1001.5]))
        self.assertFalse(z.takes_wrong_type("%#@items@", [5]))


class KeyMapTests(ZeroLossCase):
    def test_pass_with_write_key_map_writes_the_map(self):
        res = self.run_cli("--write-key-map")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        with open(os.path.join(self.repo, KEY_MAP), "rb") as f:
            raw = f.read()
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"), "no BOM")
        got = json.loads(raw.decode("utf-8"))
        want = json.loads(fixture("golden", "key_map.json").replace("{BASELINE40}", self.baseline))
        self.assertEqual(got, want)
        self.assertEqual(list(got["keys"]), sorted(got["keys"]))
        self.assertTrue(all(v == sorted(v) and v for v in got["keys"].values()))

    def test_key_map_is_byte_identical_for_the_same_input(self):
        res = self.run_cli("--write-key-map")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        path = os.path.join(self.repo, KEY_MAP)
        with open(path, "rb") as f:
            first = f.read()
        os.remove(path)
        res = self.run_cli("--write-key-map")
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        with open(path, "rb") as f:
            self.assertEqual(f.read(), first)

    def test_failing_run_writes_no_key_map(self):
        del self.cat["strings"]["Unused thing"]
        self.install_catalog()
        res = self.run_cli("--write-key-map")
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.repo, KEY_MAP)))

    def test_failing_run_leaves_an_existing_key_map_untouched(self):
        path = os.path.join(self.repo, KEY_MAP)
        with open(path, "w") as f:
            f.write("sentinel")
        del self.cat["strings"]["Unused thing"]
        self.install_catalog()
        self.run_cli("--write-key-map")
        with open(path) as f:
            self.assertEqual(f.read(), "sentinel")

    def test_cannot_run_writes_no_key_map(self):
        res = self.run_cli("--write-key-map", "--baseline", "0" * 40)
        self.assertEqual(res.returncode, 2, res.stdout + res.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.repo, KEY_MAP)))


class FindingTests(ZeroLossCase):
    def test_ac09_derived_key_changed_but_entry_did_not_move(self):
        # The code asks for "Sample %lld items"; the Catalog still holds "Sample %d items" only.
        base = baseline_lists.build_catalog(self.repo, self.baseline)
        del self.cat["strings"][ITEMS_NEW]
        self.cat["strings"][ITEMS_OLD] = base["strings"][ITEMS_OLD]
        self.install_catalog()
        res = self.run_cli()
        # en: the key is its own English text, so the same text; de and uk differ.
        self.assert_fails_with(res, 2)
        by_locale = {}
        for line in self.findings(res):
            kind, where, f = finding_fields(line)
            self.assertEqual(kind, "place")
            self.assertEqual(where, SEND + ":5")
            self.assertEqual((f["current_key"], f["baseline_key"]), (ITEMS_NEW, ITEMS_OLD))
            by_locale[f["locale"]] = f
        self.assertEqual(sorted(by_locale), ["de", "uk"])
        for loc, f in by_locale.items():
            self.assertEqual(f["expected"], self.fmt(loc, ITEMS_OLD))
            # no entry for the current key: actual is the key itself, formatted
            self.assertEqual(f["actual"], self.fmt(loc, ITEMS_NEW))
            self.assertNotEqual(f["expected"], f["actual"])
        self.assertEqual(self.row(res, "de"), (5, 4))
        self.assertEqual(self.row(res, "uk"), (4, 3))
        self.assertEqual(self.row(res, "en"), (5, 5))

    def test_moved_key_whose_translation_lost_a_locale(self):
        del self.cat["strings"][ITEMS_NEW]["localizations"]["uk"]
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        kind, where, f = finding_fields(self.findings(res)[0])
        self.assertEqual((kind, where), ("place", SEND + ":5"))
        self.assertEqual((f["locale"], f["current_key"], f["baseline_key"]), ("uk", ITEMS_NEW, ITEMS_OLD))
        self.assertEqual(f["expected"], self.fmt("uk", ITEMS_OLD))
        self.assertEqual(f["actual"], self.fmt("uk", ITEMS_NEW))
        self.assertEqual(self.row(res, "uk"), (4, 3))

    def test_counted_phrase_differing_at_one_count_shows_that_count(self):
        # uk: 0,5 -> many, 1,21,101 -> one, 2 -> few; change only `few`, so only count 2 differs.
        forms = self.cat["strings"][COINS_NEW]["localizations"]["uk"]["variations"]["plural"]
        forms["few"]["stringUnit"]["value"] = "%lld монетки"
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        kind, where, f = finding_fields(self.findings(res)[0])
        self.assertEqual((kind, where), ("place", SEND + ":4"))
        self.assertEqual((f["locale"], f["current_key"], f["baseline_key"]), ("uk", COINS_NEW, COINS_OLD))
        self.assertEqual(f["expected"], "2 монети")
        self.assertEqual(f["actual"], "2 монетки")

    def test_current_key_with_no_entry_in_the_catalog_reports_the_key_as_actual(self):
        del self.cat["strings"]["Hello"]
        self.install_catalog()
        res = self.run_cli()
        placed = [finding_fields(l) for l in self.findings(res)]
        self.assertEqual(res.returncode, 1, res.stdout)
        places = [f for k, w, f in placed if k == "place"]
        self.assertEqual([f["locale"] for f in places], ["de"])  # en: the key is its own text; uk had no "Hello"
        for f in places:
            self.assertEqual((f["current_key"], f["baseline_key"], f["actual"]), ("Hello", "Hello", "Hello"))
        self.assertEqual([k for k, w, f in placed if k == "missing-key"], ["missing-key"])

    def test_file_places_when_a_file_has_another_number_of_places(self):
        self.set_places("Greeting.stringsdata", GREETING, [("Hello", 3, 40), ("Hello", 4, 40)])
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], "FAIL file-places %s baseline=1 current=2" % GREETING)

    def test_missing_key_for_a_baseline_key_with_translations(self):
        del self.cat["strings"]["Unused thing"]
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], 'FAIL missing-key baseline_key="Unused thing"')
        self.assertIn("unused entries: 1 checked, 0 with lost translations", res.stdout)

    def test_missing_key_for_a_baseline_key_with_no_translation_either(self):
        del self.cat["strings"]["English only"]
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], 'FAIL missing-key baseline_key="English only"')

    def test_moved_key_in_place_of_its_baseline_key_is_not_missing(self):
        # AC-06: "%d coins" and "Sample %d items" have no entry; their Moved keys stand in for them.
        self.assertNotIn(COINS_OLD, self.cat["strings"])
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout)
        self.assertNotIn("missing-key", res.stdout)

    def test_unused_entry_that_lost_a_baseline_translation(self):
        del self.cat["strings"]["Unused thing"]["localizations"]["de"]
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], 'FAIL unused key="Unused thing" locale=de')
        self.assertIn("unused entries: 2 checked, 1 with lost translations", res.stdout)

    def test_a_manual_entry_no_place_looks_up_that_lost_a_translation_is_found(self):
        # PP4: e.g. a key only another target looks up, marked manual so the build keeps it
        self.cat["strings"]["Unused thing"]["extractionState"] = "manual"
        del self.cat["strings"]["Unused thing"]["localizations"]["de"]
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res), ['FAIL unmapped key="Unused thing" locale=de'])
        self.assertIn("unmapped entries: 1 checked, 1 with lost translations", res.stdout)

    def test_unused_entry_that_lost_every_translation_names_each_locale(self):
        self.cat["strings"]["Unused thing"]["localizations"] = {}
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 3)
        self.assertEqual(self.findings(res), ['FAIL unused key="Unused thing" locale=%s' % l
                                              for l in ("de", "en", "uk")])

    def test_watch_file_differing_from_the_baseline(self):
        self.write("WatchApp/de.lproj/Interface.strings", '"title" = "Uhr 2";\n')
        res = self.run_cli()
        self.assert_fails_with(res, 1)
        self.assertEqual(self.findings(res)[0], "FAIL watch WatchApp/de.lproj/Interface.strings")
        self.assertIn("watch files: 1 identical, 1 differ", res.stdout)

    def test_findings_are_sorted_by_kind_then_file_or_key_then_locale(self):
        del self.cat["strings"]["Unused thing"]["localizations"]["uk"]
        del self.cat["strings"][ITEMS_NEW]["localizations"]["uk"]
        del self.cat["strings"][ITEMS_NEW]["localizations"]["de"]
        self.write("WatchApp/en.lproj/Interface.strings", '"title" = "Watch 2";\n')
        self.install_catalog()
        res = self.run_cli()
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        kinds = [finding_fields(l)[0] for l in self.findings(res)]
        self.assertEqual(kinds, ["place", "place", "unused", "watch"])
        self.assertEqual([finding_fields(l)[2]["locale"] for l in self.findings(res)[:2]], ["de", "uk"])

    def test_all_findings_are_printed_and_counted(self):
        del self.cat["strings"]["English only"]
        del self.cat["strings"]["Unused thing"]["localizations"]["de"]
        self.write("WatchApp/de.lproj/Interface.strings", "")
        self.install_catalog()
        res = self.run_cli()
        self.assert_fails_with(res, 3)


class KeySetTwoWayTests(ZeroLossCase):
    """In pre-merge mode the Catalog's keys are exactly
    (Baseline keys - moved-from keys) | moved-to keys, in both directions (ZERO_LOSS_CHECK.md check 4)."""

    def key_findings(self, res, key):
        return [l for l in self.findings(res) if json.dumps(key) in l]

    def test_catalog_key_outside_baseline_and_moved_keys_is_a_finding(self):
        self.cat["strings"]["Brand new text"] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": "Brand new text"}}}}
        self.install_catalog()
        res = self.run_cli()
        self.assertEqual(res.returncode, 1, res.stdout)
        self.assertEqual(len(self.key_findings(res, "Brand new text")), 1, res.stdout)

    def test_leftover_old_copy_of_a_moved_key_is_a_finding(self):
        self.cat["strings"][COINS_OLD] = json.loads(json.dumps(self.cat["strings"][COINS_NEW]))
        self.install_catalog()
        res = self.run_cli()
        self.assertEqual(res.returncode, 1, res.stdout)
        self.assertEqual(len(self.key_findings(res, COINS_OLD)), 1, res.stdout)

    def test_exactly_matching_key_set_has_no_key_set_finding(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout)
        self.assertEqual(self.findings(res), [])


class Ac18Tests(ZeroLossCase):
    def advance_develop(self):
        """develop gains a text in the old lists after the move started; the move is rebased onto it."""
        git(self.repo, "checkout", "-q", "-B", "work-old", "work")
        git(self.repo, "checkout", "-q", "develop")
        for loc, text in (("en", "Late text"), ("de", "Späte Nachricht"), ("uk", "Пізній текст")):
            rel = "DashWallet/%s.lproj/Localizable.strings" % loc
            with open(os.path.join(self.repo, rel), encoding="utf-8") as f:
                self.write(rel, f.read() + '"Late" = "%s";\n' % text)
        late = self.commit("develop: new text")
        git(self.repo, "update-ref", "refs/remotes/origin/develop", late)
        git(self.repo, "checkout", "-q", "-B", "work", "develop")
        self.move_the_code()
        self.write_baseline_record(late)  # the Baseline build is redone for the new merge-base
        return late

    def test_default_baseline_is_the_merge_base_with_origin_develop(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(res.stdout.splitlines()[1],
                         "baseline: %s (merge-base of HEAD and origin/develop)" % self.baseline[:12])

    def test_after_a_rebase_the_new_merge_base_is_measured_and_its_new_texts_must_be_in_the_catalog(self):
        late = self.advance_develop()
        self.assertEqual(git(self.repo, "merge-base", "HEAD", "origin/develop"), late)
        self.assertNotEqual(late, self.baseline)
        # The Catalog still comes from the old Baseline: the text develop gained is missing and named.
        self.install_catalog()
        res = self.run_cli()
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertEqual(res.stdout.splitlines()[1],
                         "baseline: %s (merge-base of HEAD and origin/develop)" % late[:12])
        self.assertIn('FAIL missing-key baseline_key="Late"', res.stdout)
        self.assertEqual(res.returncode, 1)

    def test_after_a_rebase_a_catalog_regenerated_from_the_new_merge_base_passes(self):
        late = self.advance_develop()
        self.cat = self.moved_catalog(late)
        self.cat["strings"]["Late"]["extractionState"] = "stale"
        self.install_catalog()
        self.install_stringsdata()
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertEqual(res.stdout.splitlines()[1],
                         "baseline: %s (merge-base of HEAD and origin/develop)" % late[:12])
        self.assertIn("unused entries: 3 checked, 0 with lost translations", res.stdout)


class CannotRunTests(ZeroLossCase):
    def test_bad_flag(self):
        res = self.run_cli("--no-such-flag")
        self.assertEqual(res.returncode, 2)
        self.assertEqual(res.stdout, "")

    def test_not_a_git_repository(self):
        plain = os.path.join(self.tmp, "plain")
        os.makedirs(plain)
        self.assert_cannot_run(self.run_cli(cwd=plain), "git")

    def test_baseline_revision_not_found(self):
        self.assert_cannot_run(self.run_cli("--baseline", "no-such-rev"), "baseline", "no-such-rev")

    def test_no_default_baseline_without_origin_develop(self):
        git(self.repo, "update-ref", "-d", "refs/remotes/origin/develop")
        self.assert_cannot_run(self.run_cli(), "baseline", "develop")

    def tool_free_path(self, *keep):
        """A PATH folder holding only the named tools (symlinks)."""
        bin_dir = os.path.join(self.tmp, "bin-" + "-".join(keep))
        os.makedirs(bin_dir)
        for name in keep:
            found = shutil.which(name)
            self.assertIsNotNone(found, name)
            os.symlink(found, os.path.join(bin_dir, name))
        return bin_dir

    def test_xcstringstool_missing(self):
        path = self.tool_free_path("git", "tar", "plutil")  # no xcrun, no swift
        res = self.run_cli(extra_env={"PATH": path})
        self.assert_cannot_run(res, "xcstringstool", "xcrun")

    def test_swift_missing(self):
        path = self.tool_free_path("git", "tar", "plutil", "xcrun")  # no swift
        res = self.run_cli(extra_env={"PATH": path})
        self.assert_cannot_run(res, "swift")

    def test_no_stringsdata(self):
        empty = os.path.join(self.tmp, "empty-derived")
        os.makedirs(empty)
        res = self.run_cli("--derived-data", empty, "--write-key-map")
        self.assert_cannot_run(res, "stringsdata")
        self.assertFalse(os.path.exists(os.path.join(self.repo, KEY_MAP)))

    def test_build_older_than_the_working_tree(self):
        past = time.time() - 3600
        for fn in os.listdir(self.derived):
            os.utime(os.path.join(self.derived, fn), (past, past))
        res = self.run_cli()
        self.assert_cannot_run(res, "older", "stringsdata")

    def test_a_build_that_stopped_before_one_file_refuses_and_names_it(self):
        # PP2: Greeting's data is fresh, Send's is older than its source; the newest record must not cover it.
        past = time.time() - 3600
        os.utime(os.path.join(self.derived, "Send.stringsdata"), (past, past))
        res = self.run_cli("--write-key-map")
        self.assert_cannot_run(res, "older", "DashWallet/Sources/Send.swift")
        self.assertFalse(os.path.exists(os.path.join(self.repo, KEY_MAP)))

    def test_formatter_self_test_failed(self):
        res = self.run_cli(extra_env={"FORMATTER_FORCE_ROUTE": "localizedStringWithFormat"})
        self.assert_cannot_run(res, "self-test", "plural")

    def test_release_refuses_baseline(self):
        res = self.run_cli("--release", "--baseline", self.baseline)
        self.assert_cannot_run(res, "baseline", "release")

    def test_release_refuses_derived_data_and_write_key_map(self):
        for flags in (["--derived-data", self.derived], ["--write-key-map"]):
            with self.subTest(flags=flags):
                res = self.run_cli("--release", *flags)
                self.assertEqual(res.returncode, 2, res.stdout + res.stderr)
                self.assertEqual(res.stdout, "")


class BaselineDerivedDataFlagTests(ZeroLossCase):
    def test_pre_merge_without_the_flag_cannot_run_and_names_flag_and_script(self):
        res = self.run_cli("--write-key-map", "--derived-data", self.derived, derived=False)
        self.assert_cannot_run(res, "--baseline-derived-data")
        self.assertIn("build_baseline.sh", res.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.repo, KEY_MAP)))

    def test_release_refuses_the_flag(self):
        res = self.run_cli("--release", "--baseline-derived-data", self.baseline_derived)
        self.assert_cannot_run(res, "--baseline-derived-data", "release")

    def test_baseline_swiftui_places_come_from_the_given_dir_not_from_lightweight_extraction(self):
        # a dir with compiler data of Greeting.swift only: Baseline Send.swift keeps its two
        # NSLocalizedString places but has no SwiftUI place, against three current places
        only = os.path.join(self.tmp, "baseline-no-send")
        os.makedirs(only)
        with open(os.path.join(only, "Greeting.stringsdata"), "w", encoding="utf-8") as f:
            json.dump({"source": "/Users/ci/baseline-checkout/" + GREETING, "version": 1,
                       "tables": {"Localizable": []}}, f)
        self.write_baseline_record(self.baseline, only)
        res = self.run_cli("--baseline-derived-data", only)
        self.assertEqual(res.returncode, 1, res.stdout + res.stderr)
        self.assertIn("FAIL file-places %s baseline=2 current=3" % SEND, res.stdout)


class BaselineInputsTests(ZeroLossCase):
    """The Baseline and derived-data inputs are validated; exit 2 = cannot run."""

    # A missing or empty Baseline build folder
    def test_missing_baseline_derived_data_folder_cannot_run(self):
        res = self.run_cli("--baseline-derived-data", os.path.join(self.tmp, "nope"))
        self.assert_cannot_run(res, "baseline")
        self.assertNotIn("Traceback", res.stderr)

    def test_baseline_derived_data_without_stringsdata_cannot_run(self):
        empty = os.path.join(self.tmp, "baseline-empty")
        os.makedirs(empty)
        self.write_baseline_record(self.baseline, empty)
        res = self.run_cli("--baseline-derived-data", empty)
        self.assert_cannot_run(res, "stringsdata")
        self.assertNotIn("Traceback", res.stderr)

    # The build must be of the Baseline commit; a record that is missing counts as a mismatch (the build cannot be shown to be the Baseline's)
    def test_baseline_build_of_another_commit_cannot_run(self):
        self.write_baseline_record("0" * 40)
        res = self.run_cli()
        self.assert_cannot_run(res, "build_baseline.sh")

    def test_baseline_build_without_a_commit_record_cannot_run_and_hints_to_rebuild(self):
        os.remove(os.path.join(self.baseline_derived, BASELINE_COMMIT_FILE))
        res = self.run_cli()
        self.assert_cannot_run(res, "build_baseline.sh")

    def test_baseline_build_of_the_used_commit_runs(self):
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_the_record_is_compared_with_an_explicit_baseline_too(self):
        self.write_baseline_record(self.baseline)
        other = self.commit("later")
        res = self.run_cli("--baseline", other)
        self.assert_cannot_run(res, "build_baseline.sh")

    def test_build_baseline_script_records_the_built_commit(self):
        with open(os.path.join(LOCALIZATION_DIR, "build_baseline.sh"), encoding="utf-8") as f:
            script = f.read()
        build_at = script.index("xcodebuild")
        tail = script[build_at:]
        self.assertRegex(tail, r'\$BASE"?\s*>\s*"?\$DERIVED/' + BASELINE_COMMIT_FILE,
                         "the commit is recorded after the build succeeded")

    def test_build_baseline_script_forgets_the_old_record_before_it_builds(self):
        # PP2: a failed or partial rebuild must not keep a record that vouches for its new .stringsdata,
        # and a folder built for another commit must not lend its records of files the Baseline keeps.
        with open(os.path.join(LOCALIZATION_DIR, "build_baseline.sh"), encoding="utf-8") as f:
            script = f.read()
        head = script[:script.index("xcodebuild")]
        self.assertRegex(head, r'rm -rf "\$DERIVED"', "a folder recorded for another commit is removed")
        self.assertRegex(head, r'rm -f "\$DERIVED/' + BASELINE_COMMIT_FILE + r'" "\$DERIVED/' + BASELINE_ROOT_FILE + '"',
                         "the records are removed before the build")

    # Baseline sources map to repository files through the recorded worktree root
    def test_baseline_sources_map_through_the_recorded_worktree_root(self):
        root = "/work/DashWallet/baseline-checkout"  # contains /DashWallet/ above the repo root
        path = os.path.join(self.baseline_derived, "Send.stringsdata")
        with open(path, encoding="utf-8") as f:
            text = f.read().replace("/Users/ci/baseline-checkout", root)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        with open(os.path.join(self.baseline_derived, BASELINE_ROOT_FILE), "w") as f:
            f.write(root + "\n")
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    # The default derived data is this checkout's newest simulator Debug build
    def make_build(self, name, source_root, mtime, platform="Debug-iphonesimulator"):
        """A fake Xcode DerivedData build under the temp HOME whose sources lie under source_root."""
        build = os.path.join(self.home, "Library", "Developer", "Xcode", "DerivedData", name, "Build",
                             "Intermediates.noindex", "DashWallet.build", platform, "dashpay.build")
        os.makedirs(build)
        for fn in ("Send.stringsdata", "Greeting.stringsdata"):
            path = os.path.join(build, fn)
            with open(path, "w", encoding="utf-8") as f:
                f.write(fixture("stringsdata", "ok", fn).replace("__REPO__", source_root))
            os.utime(path, (mtime, mtime))
        os.utime(build, (mtime, mtime))

    def run_default_derived(self):
        return self.run_cli("--baseline-derived-data", self.baseline_derived, derived=False,
                            extra_env={"HOME": self.home})

    def setUp(self):
        super().setUp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)

    def test_default_derived_data_skips_a_newer_build_of_another_checkout(self):
        future = time.time() + 600
        self.make_build("mine-aaa", self.repo, future)
        self.make_build("other-bbb", "/Users/ci/other-checkout", future + 100)
        res = self.run_default_derived()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_default_derived_data_skips_a_newer_device_build_of_this_checkout(self):
        # The Baseline is a simulator Debug build; a device build compiles other files
        # (simulator-only fixtures), so its places cannot pair with the Baseline's.
        future = time.time() + 600
        self.make_build("mine-aaa", self.repo, future)
        build = os.path.join(self.home, "Library", "Developer", "Xcode", "DerivedData", "mine-aaa", "Build",
                             "Intermediates.noindex", "DashWallet.build", "Debug-iphoneos", "dashpay.build")
        os.makedirs(build)
        # the device build lacks one of Send.swift's places (as a simulator-only file would)
        device = json.loads(fixture("stringsdata", "ok", "Send.stringsdata").replace("__REPO__", self.repo))
        device["tables"]["Localizable"].pop()
        path = os.path.join(build, "Send.stringsdata")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(device, f)
        os.utime(path, (future + 100, future + 100))
        os.utime(build, (future + 100, future + 100))
        res = self.run_default_derived()
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_default_derived_data_with_only_another_checkouts_build_cannot_run(self):
        self.make_build("other-bbb", "/Users/ci/other-checkout", time.time() + 600)
        res = self.run_default_derived()
        self.assert_cannot_run(res, "dashpay build")


class OfflineTests(unittest.TestCase):
    """AC-10, AC-14: the check never uses the network and never calls the translation service."""

    def test_source_imports_no_network_module(self):
        self.assertTrue(os.path.exists(CLI))
        with open(CLI, encoding="utf-8") as f:
            tree = ast.parse(f.read())
        banned = {"urllib", "urllib2", "urllib3", "http", "httplib", "socket", "ssl", "ftplib",
                  "smtplib", "requests", "asyncio", "xmlrpc", "telnetlib"}
        imported = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imported.update(a.name.split(".")[0] for a in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split(".")[0])
        self.assertEqual(imported & banned, set())

    def test_source_does_not_mention_the_translation_service(self):
        with open(CLI, encoding="utf-8") as f:
            source = f.read().lower()
        self.assertNotIn("transifex", source)
        self.assertNotRegex(source, r"\btx (push|pull)\b")


if __name__ == "__main__":
    unittest.main()

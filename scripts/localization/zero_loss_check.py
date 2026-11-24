#!/usr/bin/env python3
"""Zero-loss check: proves the String Catalog keeps every Baseline translation.

    python3 scripts/localization/zero_loss_check.py [--baseline <rev>] --baseline-derived-data <path>
                                                    [--derived-data <path>] [--write-key-map]
    python3 scripts/localization/zero_loss_check.py --release

Pre-merge mode pairs each lookup place in the code with the key the same place used at the
Baseline commit (ADR-0067) and proves the Catalog resolves it to the Baseline wording in every
locale. Release mode re-checks the keys recorded in zero_loss_key_map.json (ADR-0070).
Exit 0 pass, 1 findings, 2 cannot run. It reads the Baseline from git alone and uses no network.
"""
import argparse
import glob
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import catalog_io  # noqa: E402
import foundation_format  # noqa: E402
import baseline_lists  # noqa: E402
import places  # noqa: E402

CATALOG = "DashWallet/Localizable.xcstrings"
KEY_MAP = "scripts/localization/zero_loss_key_map.json"
COUNTS = (0, 1, 2, 5, 21, 101)
# compare_wording marks a Baseline translation that takes an argument as the wrong type with this.
DEFECT = object()
WATCH_DIR = "WatchApp"
WATCH_FILE = re.compile(r"^WatchApp/[^/]+\.lproj/Interface\.strings$")
BASELINE_COMMIT_FILE = "baseline-commit"  # written by build_baseline.sh
BASELINE_ROOT_FILE = "baseline-root"  # written by build_baseline.sh
DERIVED_DATA_HOME = os.path.join("~", "Library", "Developer", "Xcode", "DerivedData")
# A simulator Debug build, as build_baseline.sh makes the Baseline: a device or Release build compiles
# other files (simulator-only fixtures, debug code), so its places would not pair with the Baseline's.
DERIVED_GLOB = os.path.join("*", "Build", "Intermediates.noindex", "*", "Debug-iphonesimulator", "dashpay.build")


class CannotRun(Exception):
    """Exit 2: nothing is compared."""


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def git(repo, *args):
    return run(["git", "-C", repo] + list(args))


# --- exit-2 preconditions ---------------------------------------------------------------

def repo_root():
    if shutil.which("git") is None:
        raise CannotRun("git is not on PATH")
    res = run(["git", "rev-parse", "--show-toplevel"], text=True)
    if res.returncode != 0:
        raise CannotRun("not a git repository: run from the repository root")
    return os.path.realpath(res.stdout.strip())


def check_tools():
    if shutil.which("xcrun") is None or run(["xcrun", "--find", "xcstringstool"]).returncode != 0:
        raise CannotRun("xcrun xcstringstool is not available on PATH")
    if shutil.which("swift") is None:
        raise CannotRun("swift is not on PATH")


def resolve_baseline(repo, given):
    """(full 40-hex commit, description for the report header)."""
    if given is not None:
        res = None if given.startswith("-") else git(repo, "rev-parse", "--verify", "--quiet", given + "^{commit}")
        if res is None or res.returncode != 0:
            raise CannotRun("baseline revision not found: %s" % given)
        return res.stdout.decode().strip(), "--baseline %s" % given
    res = git(repo, "merge-base", "HEAD", "origin/develop")
    if res.returncode != 0:
        raise CannotRun("no default baseline: cannot take the merge-base of HEAD and origin/develop; "
                        "fetch origin/develop or pass --baseline <rev>")
    return res.stdout.decode().strip(), "merge-base of HEAD and origin/develop"


def _build_is_of(build, repo):
    """True when some .stringsdata of the build has a source under this checkout."""
    roots = {os.path.realpath(repo) + os.sep, os.path.abspath(repo) + os.sep}
    for dirpath, _, names in os.walk(build):
        for n in names:
            if not n.endswith(".stringsdata"):
                continue
            try:
                with open(os.path.join(dirpath, n), encoding="utf-8") as f:
                    source = json.load(f).get("source", "")
            except (OSError, ValueError):
                continue
            if isinstance(source, str) and source.startswith(tuple(roots)):
                return True
    return False


def default_derived_data(repo):
    """The newest simulator Debug dashpay build in DerivedData whose sources lie under this checkout."""
    builds = glob.glob(os.path.join(os.path.expanduser(DERIVED_DATA_HOME), DERIVED_GLOB))
    for build in sorted(builds, key=os.path.getmtime, reverse=True):
        if _build_is_of(build, repo):
            return build
    raise CannotRun("no dashpay build of this checkout found in %s; build the dashpay target or pass --derived-data"
                    % DERIVED_DATA_HOME)


def read_record(folder, name):
    try:
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def check_baseline_build(folder, baseline):
    """Validate the Baseline build folder; returns the recorded worktree root (or None)."""
    if not os.path.isdir(folder):
        raise CannotRun("the baseline derived data %s does not exist; build it with "
                        "scripts/localization/build_baseline.sh" % folder)
    try:
        places._stringsdata_files(folder)
    except places.NoStringsdataError:
        raise CannotRun("no .stringsdata files under the baseline derived data %s; build it with "
                        "scripts/localization/build_baseline.sh" % folder)
    built = read_record(folder, BASELINE_COMMIT_FILE)
    if built != baseline:
        raise CannotRun("the baseline derived data %s was not built from baseline commit %s (record: %s); "
                        "rebuild it with scripts/localization/build_baseline.sh %s"
                        % (folder, baseline, built or "missing", baseline))
    return read_record(folder, BASELINE_ROOT_FILE) or None


def check_build(repo, derived):
    try:
        stale = places.build_is_stale(repo, derived)
    except places.NoStringsdataError:
        raise CannotRun("no .stringsdata files under %s; build the dashpay target first" % derived)
    if stale:
        raise CannotRun("the dashpay build's .stringsdata is older than the working tree; "
                        "build the dashpay target first")


def check_formatter():
    try:
        problem = foundation_format.self_test()
    except foundation_format.FormatError as e:
        problem = "self-test could not run: %s" % e
    if problem:
        raise CannotRun(problem)


# --- Baseline side ------------------------------------------------------------------------

def counted_specs(repo, rev, locales):
    """{key: .stringsdict spec} of the counted phrases at the Baseline (English spec preferred)."""
    specs = {}
    for locale in sorted(locales, key=lambda l: (l != "en", l)):
        path = "%s/%s.lproj/Localizable.stringsdict" % (baseline_lists.LISTS_DIR, locale)
        res = git(repo, "show", "%s:%s" % (rev, path))
        if res.returncode != 0:
            continue
        for key, spec in plistlib.loads(res.stdout).items():
            specs.setdefault(key, spec)
    return specs


_CODE = re.compile(r"%(?:(\d+)\$)?(?:#@(\w+)@|[-+ 0#']*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDiuUfFeEgGxXoOcCsSp]))")


def counted_samples(spec):
    """One argument list per count of COUNTS, in order, for a counted phrase.

    Plural position j (0-based, in argument order) of sample i carries COUNTS[(i + j) % len(COUNTS)], so
    every position meets every count and the positions of one sample differ; the other positions keep a
    distinct value."""
    fmt_key = "NSStringLocalizedFormatKey"
    plural_at, types = {}, {}
    sequential = 0
    for m in _CODE.finditer(spec[fmt_key].replace("%%", "")):
        sequential += 1
        position = int(m.group(1)) if m.group(1) else sequential
        if m.group(2):
            plural_at[m.group(2)] = position
        else:
            types[position] = m.group(3)
    for name, body in spec.items():
        if name == fmt_key or name not in plural_at:
            continue
        for form, text in body.items():
            if form.startswith("NSStringFormat"):
                continue
            seq = 0
            for m in _CODE.finditer(text.replace("%%", "")):
                seq += 1
                position = int(m.group(1)) if m.group(1) else plural_at[name] + seq - 1
                if not m.group(2):
                    types.setdefault(position, m.group(3))
    last = max(list(plural_at.values()) + list(types), default=1)
    plural_positions = sorted(plural_at.values())
    samples = []
    for i in range(len(COUNTS)):
        samples.append(_sample(last, types, plural_positions, i))
    return samples


def _sample(last, types, plural_positions, i):
    args = []
    for position in range(1, last + 1):
        code = types.get(position)
        if position in plural_positions:
            args.append(COUNTS[(i + plural_positions.index(position)) % len(COUNTS)])
        elif code in ("@", "s", "S", None):
            args.append("‹a%d›" % position)
        elif code in "fFeEgG":
            args.append(1000 + position + 0.5)
        else:
            args.append(1000 + position)
    return args


def _kind(value):
    return "float" if isinstance(value, float) else "int" if isinstance(value, int) else "object"


def takes_wrong_type(text, args):
    """True when a format code of `text` takes its sample argument as another type (an object code
    for a number, an integer code for an object, ...): Foundation then formats undefined text.
    A text with a plural variable (%#@name@) is not judged."""
    sequential = 0
    for m in _CODE.finditer(text.replace("%%", "")):
        if m.group(2):
            return False
        sequential += 1
        position = int(m.group(1)) if m.group(1) else sequential
        if position > len(args):
            continue
        code = m.group(3)
        want = "object" if code in "@sS" else "float" if code in "fFeEgG" else "int"
        if want != _kind(args[position - 1]):
            return True
    return False


# format.swift's inferArgs pattern: no space flag ("100% sure" is prose), no %#@name@.
_SWIFT_CODE = re.compile(r"%(?:(\d+)\$)?[-+0#']*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDiuUfFeEgGxXoOcCsSp])")


def sample_args(text):
    """The sample arguments format.swift infers from an English text: one distinct value per position."""
    by_position, sequential = {}, 0
    for m in _SWIFT_CODE.finditer(text):
        sequential += 1
        position = int(m.group(1)) if m.group(1) else sequential
        code = m.group(2)
        by_position[position] = ("‹a%d›" % position if code in "@sS"
                                 else 1000 + position + 0.5 if code in "fFeEgG" else 1000 + position)
    return [by_position.get(p, "‹a%d›" % p) for p in range(1, max(by_position, default=0) + 1)]


def defective_translation(localization, args):
    """The first Baseline text of one locale that takes an argument as the wrong type, else None.
    Texts under substitutions are not judged: their codes count from the plural variable's position."""
    if "substitutions" in localization:
        return None
    return next((t for t in leaf_values(localization) if takes_wrong_type(t, args)), None)


def leaf_values(node):
    if isinstance(node, dict):
        out = []
        for k, v in sorted(node.items()):
            out += [v] if k == "value" and isinstance(v, str) else leaf_values(v)
        return out
    return []


# --- the checks -----------------------------------------------------------------------------

def compile_catalog(catalog_path, out_dir):
    res = run(["xcrun", "xcstringstool", "compile", catalog_path, "-o", out_dir], text=True)
    if res.returncode != 0:
        raise CannotRun("xcstringstool compile failed: %s" % res.stderr.strip())


def compare_wording(repo, rev, pairs, base_catalog, locales):
    """Format both sides of each (baseline key, current key, tag) pair in each locale the Baseline key
    translated: [(tag, baseline key, current key, locale, None if equal else (expected, actual))].
    A Baseline translation that takes an argument as the wrong type gives (DEFECT, its text) instead."""
    specs = counted_specs(repo, rev, locales)
    base_strings = base_catalog["strings"]
    # one entry per (pair, locale): what to format and with which counts
    jobs = []
    for b, c, tag in pairs:
        have = base_strings.get(b, {}).get("localizations", {})
        for locale in sorted(locales):
            if locale in have:
                jobs.append((b, c, tag, locale, specs.get(b)))
    with tempfile.TemporaryDirectory(prefix="zero-loss-") as tmp:
        base_root = os.path.join(tmp, "baseline")
        os.makedirs(base_root)
        tar = git(repo, "archive", rev, baseline_lists.LISTS_DIR).stdout
        subprocess.run(["tar", "-x", "-C", base_root], input=tar, check=True)
        cur_root = os.path.join(tmp, "current")
        os.makedirs(cur_root)
        compile_catalog(os.path.join(repo, CATALOG), cur_root)

        base_reqs, cur_keys = [], []
        for b, c, tag, locale, spec in jobs:
            for a in (counted_samples(spec) if spec is not None else (None,)):
                base_reqs.append((locale, b, a))
                cur_keys.append(c)
        base_out = foundation_format.format_texts(os.path.join(base_root, baseline_lists.LISTS_DIR), base_reqs)
        # the current side is formatted with the arguments the Baseline side used; after a Baseline
        # crash those are unknown (None) and the formatter infers them from the current key's English
        cur_out = foundation_format.format_texts(
            cur_root, [(r[0], key, o["args"]) for r, key, o in zip(base_reqs, cur_keys, base_out)])

    results = []
    at = 0
    for b, c, tag, locale, spec in jobs:
        n = len(COUNTS) if spec is not None else 1
        args = base_out[at]["args"]
        if args is None:  # the formatter crashed before it could report the arguments it inferred
            english = leaf_values(base_strings[b]["localizations"].get("en", {}))
            args = sample_args(english[0] if english else b)
        defect = defective_translation(base_strings[b]["localizations"][locale], args)
        diff = next((i for i in range(n) if base_out[at + i]["text"] != cur_out[at + i]["text"]), None)
        if defect is not None:
            results.append((tag, b, c, locale, (DEFECT, defect)))
        else:
            results.append((tag, b, c, locale,
                            None if diff is None else (base_out[at + diff]["text"], cur_out[at + diff]["text"])))
        at += n
    return results


def wording_check(repo, rev, pairs, base_catalog, locales):
    """Check 3: (rows {locale: [places, same]}, place findings, sorted baseline-defect lines)."""
    rows = {locale: [0, 0] for locale in locales}
    findings, defects = [], []
    for (b, c), _, _, locale, diff in compare_wording(repo, rev, [(b.key, c.key, (b, c)) for b, c in pairs],
                                                     base_catalog, locales):
        if diff is not None and diff[0] is DEFECT:
            defects.append(((c.file, c.line, locale, b.key), "DEFECT %s:%d locale=%s baseline_key=%s translation=%s" % (
                c.file, c.line, locale, dump(b.key), dump(diff[1]))))
            continue
        rows[locale][0] += 1
        if diff is None:
            rows[locale][1] += 1
        else:
            findings.append(("place", (c.file, c.line, locale, c.key),
                             "FAIL place %s:%d locale=%s current_key=%s baseline_key=%s expected=%s actual=%s" % (
                                 c.file, c.line, locale, dump(c.key), dump(b.key), dump(diff[0]), dump(diff[1]))))
    return rows, findings, [text for _, text in sorted(defects)]


def release_wording_check(repo, rev, key_map, base_catalog, locales):
    """Release key check: (rows {locale: [keys, same]}, key findings, sorted baseline-defect lines);
    a Baseline key counts once per locale."""
    rows = {locale: [0, 0] for locale in locales}
    findings, defects = [], set()
    differs = set()
    results = compare_wording(repo, rev, [(b, c, None) for b, cs in sorted(key_map.items()) for c in cs],
                              base_catalog, locales)
    for _, b, c, locale, diff in results:
        if diff is not None and diff[0] is DEFECT:
            defects.add((b, locale, diff[1]))
        elif diff is not None:
            differs.add((b, locale))
            findings.append(("key", (b, c, locale),
                             "FAIL key baseline_key=%s current_key=%s locale=%s expected=%s actual=%s" % (
                                 dump(b), dump(c), locale, dump(diff[0]), dump(diff[1]))))
    left_out = {(b, locale) for b, locale, _ in defects}
    for b, locale in {(b, locale) for _, b, _, locale, _ in results} - left_out:
        rows[locale][0] += 1
        rows[locale][1] += (b, locale) not in differs
    return rows, findings, ["DEFECT baseline_key=%s locale=%s translation=%s" % (dump(b), locale, dump(t))
                            for b, locale, t in sorted(defects)]


def dump(value):
    return json.dumps(value, ensure_ascii=False)


def key_set_check(base_strings, cur_strings, used, asked=None):
    """Check 4 and the key map: (key-set findings, {baseline key: sorted current keys}).
    `used` maps each Baseline key to the current keys that replaced it; `asked` holds the keys the
    current lookup places ask for; None in release mode, which has no places and so cannot tell a new
    text from a stray key (no extra-key there). The Catalog's keys must be (Baseline keys - moved-from
    keys) | moved-to keys, plus any key a current place asks for. A moved-from key is an old-copy only
    while a key that replaced it is in the Catalog too."""
    findings = []
    for key in sorted(base_strings):
        if key in cur_strings or any(k in cur_strings for k in used.get(key, ())):
            continue
        findings.append(("missing-key", (key,), "FAIL missing-key baseline_key=%s" % dump(key)))
    moved_from = {b for b, cs in used.items() if b not in cs}
    moved_to = {c for cs in used.values() for c in cs}
    allowed = (set(base_strings) - moved_from) | moved_to | set(asked or ())
    for key in sorted(set(cur_strings) - allowed):
        if key in moved_from:
            kind = "old-copy" if any(c in cur_strings for c in used[key]) else None
        else:
            kind = "extra-key" if asked is not None else None
        if kind:
            findings.append((kind, (key,), "FAIL %s key=%s" % (kind, dump(key))))
    return findings, {k: sorted(v) for k, v in sorted(used.items())}


def unused_check(base_strings, cur_strings):
    """Check 5: (entries checked, entries with lost translations, unused findings)."""
    checked = lost_entries = 0
    findings = []
    for key in sorted(cur_strings):
        entry = cur_strings[key]
        if entry.get("extractionState") != "stale" or key not in base_strings:
            continue
        checked += 1
        held = entry.get("localizations", {})
        lost = [loc for loc, want in sorted(base_strings[key]["localizations"].items())
                if loc not in held or leaf_values(held[loc]) != leaf_values(want)]
        lost_entries += bool(lost)
        findings += [("unused", (key, loc), "FAIL unused key=%s locale=%s" % (dump(key), loc)) for loc in lost]
    return checked, lost_entries, findings


def watch_check(repo, rev):
    """Check 6: (identical, differing files, watch findings)."""
    listed = git(repo, "ls-tree", "-r", "--name-only", rev, "--", WATCH_DIR + "/").stdout.decode("utf-8")
    identical, findings = 0, []
    for path in sorted(p for p in listed.splitlines() if WATCH_FILE.match(p)):
        want = git(repo, "show", "%s:%s" % (rev, path)).stdout
        try:
            with open(os.path.join(repo, path), "rb") as f:
                same = f.read() == want
        except OSError:
            same = False
        if same:
            identical += 1
        else:
            findings.append(("watch", (path,), "FAIL watch %s" % path))
    return identical, len(findings), findings


# --- report -------------------------------------------------------------------------------------

def render(baseline, how, rows, unused, watch, findings, mode="pre-merge", defects=()):
    lines = ["zero-loss check — mode: %s" % mode,
             "baseline: %s (%s)" % (baseline[:12], how),
             "%-13s%-9s%s" % ("locale", "keys" if mode == "release" else "places", "same")]
    lines += ["%-13s%-9s%s" % (loc, rows[loc][0], rows[loc][1]) for loc in sorted(rows)]
    if defects:
        lines.append("baseline defects: %d left out" % len(defects))
        lines += list(defects)
    lines.append("unused entries: %d checked, %d with lost translations" % unused)
    lines.append("watch files: %d identical, %d differ" % watch)
    lines += [text for _, _, text in findings]
    lines.append("RESULT: %s (%d findings)" % ("FAIL" if findings else "PASS", len(findings)))
    return "\n".join(lines) + "\n"


def write_key_map(repo, baseline, keys, expect):
    """Write the key map; `expect` ({path: bytes read}) holds the Catalog and key map as the run read
    them, so a map derived from an older read never replaces a newer save (catalog_io.publish_text)."""
    text = json.dumps({"baseline": baseline, "keys": keys}, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    catalog_io.publish_text(os.path.join(repo, KEY_MAP), text, expect)


def read_key_map(repo):
    """The committed key map's (Baseline commit, {Baseline key: [current keys]}); CannotRun when unusable."""
    baseline, keys, _ = load_key_map(repo)
    return baseline, keys


def load_key_map(repo):
    """read_key_map plus the bytes it parsed, for a writer that derives a file from them."""
    path = os.path.join(repo, KEY_MAP)
    try:
        with open(path, "rb") as f:
            raw = f.read()
        data = json.loads(raw.decode("utf-8"))
    except (OSError, ValueError) as e:
        raise CannotRun("key map %s is missing or unreadable (%s); run the pre-merge check with --write-key-map"
                        % (KEY_MAP, e))
    keys = data.get("keys") if isinstance(data, dict) else None
    if (not isinstance(data.get("baseline"), str) or not re.fullmatch(r"[0-9a-f]{40}", data["baseline"])
            or not isinstance(keys, dict)
            or not all(isinstance(cs, list) and cs and all(isinstance(c, str) for c in cs) for cs in keys.values())):
        raise CannotRun("key map %s has the wrong schema" % KEY_MAP)
    return data["baseline"], keys, raw


def check_release(args):
    repo = repo_root()
    check_tools()
    baseline, key_map = read_key_map(repo)
    if git(repo, "rev-parse", "--verify", "--quiet", baseline + "^{commit}").returncode != 0:
        raise CannotRun("the key map's baseline commit %s is not in this repository" % baseline)
    check_formatter()
    catalog_path = os.path.join(repo, CATALOG)
    if not os.path.isfile(catalog_path):
        raise CannotRun("no Catalog at %s" % CATALOG)
    cur_strings = catalog_io.read_catalog(catalog_path)["strings"]
    base_catalog = baseline_lists.build_catalog(repo, baseline)
    locales = sorted(baseline_lists.locale_files(repo, baseline))

    rows, wording, defects = release_wording_check(repo, baseline, key_map, base_catalog, locales)
    missing, _ = key_set_check(base_catalog["strings"], cur_strings, {k: set(v) for k, v in key_map.items()})
    checked, lost, unused = unused_check(base_catalog["strings"], cur_strings)
    identical, differ, watch = watch_check(repo, baseline)
    findings = wording + missing + unused + watch
    findings.sort(key=lambda f: (f[0],) + tuple((0, x) if isinstance(x, int) else (1, x) for x in f[1]))
    sys.stdout.write(render(baseline, "key map", rows, (checked, lost), (identical, differ), findings, "release", defects))
    return 1 if findings else 0


def check(args):
    if args.release:
        return check_release(args)
    repo = repo_root()
    check_tools()
    baseline, how = resolve_baseline(repo, args.baseline)
    baseline_root = check_baseline_build(args.baseline_derived_data, baseline)
    derived = args.derived_data or default_derived_data(repo)
    check_build(repo, derived)
    check_formatter()
    catalog_path = os.path.join(repo, CATALOG)
    if not os.path.isfile(catalog_path):
        raise CannotRun("no Catalog at %s" % CATALOG)
    # Read once: the key map is derived from these bytes and is written only while they are on disk.
    read_before = {catalog_path: catalog_io.read_bytes(catalog_path),
                   os.path.join(repo, KEY_MAP): catalog_io.read_bytes(os.path.join(repo, KEY_MAP))}
    cur_strings = json.loads(read_before[catalog_path].decode("utf-8"))["strings"]
    base_catalog = baseline_lists.build_catalog(repo, baseline)
    locales = sorted(baseline_lists.locale_files(repo, baseline))

    current = places.current_places(repo, derived)
    pairs, mismatched = places.pair(places.baseline_places(repo, baseline, args.baseline_derived_data, baseline_root), current)
    findings = [("file-places", (f,), "FAIL file-places %s baseline=%d current=%d" % (f, b, c))
                for f, b, c in mismatched]
    rows, wording, defects = wording_check(repo, baseline, pairs, base_catalog, locales)
    used = {}
    for b, c in pairs:
        used.setdefault(b.key, set()).add(c.key)
    missing, key_map = key_set_check(base_catalog["strings"], cur_strings, used, {c.key for c in current})
    checked, lost, unused = unused_check(base_catalog["strings"], cur_strings)
    identical, differ, watch = watch_check(repo, baseline)
    findings += wording + missing + unused + watch
    findings.sort(key=lambda f: (f[0],) + tuple((0, x) if isinstance(x, int) else (1, x) for x in f[1]))

    sys.stdout.write(render(baseline, how, rows, (checked, lost), (identical, differ), findings, defects=defects))
    if findings:
        return 1
    if args.write_key_map:
        write_key_map(repo, baseline, key_map, read_before)
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Prove that every lookup key the main app uses still resolves to its Baseline wording.")
    parser.add_argument("--baseline", metavar="<rev>",
                        help="Baseline commit (default: merge-base of HEAD and origin/develop)")
    parser.add_argument("--derived-data", metavar="<path>",
                        help="where the dashpay build's .stringsdata files are read from "
                             "(default: the newest simulator Debug dashpay build of this checkout)")
    parser.add_argument("--baseline-derived-data", metavar="<path>",
                        help="DerivedData of a build of the Baseline commit (scripts/localization/build_baseline.sh); required unless --release")
    parser.add_argument("--write-key-map", action="store_true",
                        help="on a pass, write %s" % KEY_MAP)
    parser.add_argument("--release", action="store_true", help="release mode: check the Catalog through the committed key map")
    args = parser.parse_args(argv)
    if args.release:
        refused = [f for f, on in (("--baseline", args.baseline), ("--derived-data", args.derived_data), ("--baseline-derived-data", args.baseline_derived_data),
                                   ("--write-key-map", args.write_key_map)) if on]
        if refused:
            raise CannotRun("--release refuses %s" % ", ".join(refused))
    elif not args.baseline_derived_data:
        raise CannotRun("pre-merge needs --baseline-derived-data <dir>, the DerivedData of a Baseline build "
                        "(make one with scripts/localization/build_baseline.sh)")
    return args


def main(argv):
    try:
        return check(parse_args(argv))
    except CannotRun as e:
        message = str(e)
    except (baseline_lists.GenerateError, catalog_io.CatalogIOError, foundation_format.FormatError,
            subprocess.CalledProcessError, OSError, ValueError, KeyError) as e:
        message = "%s: %s" % (type(e).__name__, e)
    sys.stderr.write("error: %s\n" % " ".join(message.split()))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Zero-loss check, pre-merge mode (contract: docs/features/string-catalogs-migration/contracts/cli.md).

    python3 scripts/localization/zero_loss_check.py [--baseline <rev>] [--derived-data <path>] [--write-key-map]

Pairs each lookup place in the code with the key the same place used at the Baseline commit
(ADR-0004) and proves the Catalog resolves it to the Baseline wording in every locale.
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
import generate_catalog  # noqa: E402
import places  # noqa: E402

CATALOG = "DashWallet/Localizable.xcstrings"
KEY_MAP = "scripts/localization/zero_loss_key_map.json"
COUNTS = (0, 1, 2, 5, 21, 101)
WATCH_DIR = "WatchApp"
WATCH_FILE = re.compile(r"^WatchApp/[^/]+\.lproj/Interface\.strings$")
DERIVED_DATA_HOME = os.path.join("~", "Library", "Developer", "Xcode", "DerivedData")
DERIVED_GLOB = os.path.join("*", "Build", "Intermediates.noindex", "*", "*", "dashpay.build")


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


def default_derived_data():
    builds = glob.glob(os.path.join(os.path.expanduser(DERIVED_DATA_HOME), DERIVED_GLOB))
    if not builds:
        raise CannotRun("no dashpay build found in %s; build the dashpay target or pass --derived-data"
                        % DERIVED_DATA_HOME)
    return max(builds, key=os.path.getmtime)


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
        path = "%s/%s.lproj/Localizable.stringsdict" % (generate_catalog.LISTS_DIR, locale)
        res = git(repo, "show", "%s:%s" % (rev, path))
        if res.returncode != 0:
            continue
        for key, spec in plistlib.loads(res.stdout).items():
            specs.setdefault(key, spec)
    return specs


_CODE = re.compile(r"%(?:(\d+)\$)?(?:#@(\w+)@|[-+ 0#']*(?:\d+|\*)?(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDiuUfFeEgGxXoOcCsSp]))")


def counted_args(spec, count):
    """Sample arguments of a counted phrase: the count at every plural position, a distinct value elsewhere."""
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
    args = []
    for position in range(1, last + 1):
        code = types.get(position)
        if position in plural_at.values():
            args.append(count)
        elif code in ("@", "s", "S", None):
            args.append("‹a%d›" % position)
        elif code in "fFeEgG":
            args.append(1000 + position + 0.5)
        else:
            args.append(1000 + position)
    return args


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


def wording_check(repo, rev, pairs, base_catalog, locales):
    """Check 3: (rows {locale: [places, same]}, place findings)."""
    specs = counted_specs(repo, rev, locales)
    base_strings = base_catalog["strings"]
    # one entry per (pair, locale): what to format and with which counts
    jobs = []
    for b, c in pairs:
        have = base_strings.get(b.key, {}).get("localizations", {})
        for locale in sorted(locales):
            if locale in have:
                jobs.append((b, c, locale, specs.get(b.key)))
    with tempfile.TemporaryDirectory(prefix="zero-loss-") as tmp:
        base_root = os.path.join(tmp, "baseline")
        os.makedirs(base_root)
        tar = git(repo, "archive", rev, generate_catalog.LISTS_DIR).stdout
        subprocess.run(["tar", "-x", "-C", base_root], input=tar, check=True)
        cur_root = os.path.join(tmp, "current")
        os.makedirs(cur_root)
        compile_catalog(os.path.join(repo, CATALOG), cur_root)

        base_reqs, cur_keys = [], []
        for b, c, locale, spec in jobs:
            for n in (COUNTS if spec is not None else (None,)):
                base_reqs.append((locale, b.key, None if n is None else counted_args(spec, n)))
                cur_keys.append(c.key)
        base_out = foundation_format.format_texts(os.path.join(base_root, generate_catalog.LISTS_DIR), base_reqs)
        # the current side is formatted with the very arguments the Baseline side used
        cur_out = foundation_format.format_texts(
            cur_root, [(r[0], key, o["args"]) for r, key, o in zip(base_reqs, cur_keys, base_out)])

    rows = {locale: [0, 0] for locale in locales}
    findings = []
    at = 0
    for b, c, locale, spec in jobs:
        n = len(COUNTS) if spec is not None else 1
        rows[locale][0] += 1
        diff = next((i for i in range(n) if base_out[at + i]["text"] != cur_out[at + i]["text"]), None)
        if diff is None:
            rows[locale][1] += 1
        else:
            findings.append(("place", (c.file, c.line, locale, c.key),
                             "FAIL place %s:%d locale=%s current_key=%s baseline_key=%s expected=%s actual=%s" % (
                                 c.file, c.line, locale, dump(c.key), dump(b.key),
                                 dump(base_out[at + diff]["text"]), dump(cur_out[at + diff]["text"]))))
        at += n
    return rows, findings


def dump(value):
    return json.dumps(value, ensure_ascii=False)


def key_set_check(base_strings, cur_strings, pairs):
    """Check 4 and the key map: (missing-key findings, {baseline key: sorted current keys})."""
    used = {}
    for b, c in pairs:
        used.setdefault(b.key, set()).add(c.key)
    findings = []
    for key in sorted(base_strings):
        if key in cur_strings or any(k in cur_strings for k in used.get(key, ())):
            continue
        findings.append(("missing-key", (key,), "FAIL missing-key baseline_key=%s" % dump(key)))
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

def render(baseline, how, rows, unused, watch, findings):
    lines = ["zero-loss check — mode: pre-merge",
             "baseline: %s (%s)" % (baseline[:12], how),
             "%-13s%-9s%s" % ("locale", "places", "same")]
    lines += ["%-13s%-9s%s" % (loc, rows[loc][0], rows[loc][1]) for loc in sorted(rows)]
    lines.append("unused entries: %d checked, %d with lost translations" % unused)
    lines.append("watch files: %d identical, %d differ" % watch)
    lines += [text for _, _, text in findings]
    lines.append("RESULT: %s (%d findings)" % ("FAIL" if findings else "PASS", len(findings)))
    return "\n".join(lines) + "\n"


def write_key_map(repo, baseline, keys):
    path = os.path.join(repo, KEY_MAP)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = json.dumps({"baseline": baseline, "keys": keys}, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=os.path.dirname(path), prefix=".key-map-",
                                     delete=False) as f:
        f.write(text)
    os.replace(f.name, path)


def check(args):
    repo = repo_root()
    check_tools()
    baseline, how = resolve_baseline(repo, args.baseline)
    derived = args.derived_data or default_derived_data()
    check_build(repo, derived)
    check_formatter()
    catalog_path = os.path.join(repo, CATALOG)
    if not os.path.isfile(catalog_path):
        raise CannotRun("no Catalog at %s" % CATALOG)
    cur_strings = catalog_io.read_catalog(catalog_path)["strings"]
    base_catalog = generate_catalog.build_catalog(repo, baseline)
    locales = sorted(generate_catalog.locale_files(repo, baseline))

    pairs, mismatched = places.pair(places.baseline_places(repo, baseline), places.current_places(repo, derived))
    findings = [("file-places", (f,), "FAIL file-places %s baseline=%d current=%d" % (f, b, c))
                for f, b, c in mismatched]
    rows, wording = wording_check(repo, baseline, pairs, base_catalog, locales)
    missing, key_map = key_set_check(base_catalog["strings"], cur_strings, pairs)
    checked, lost, unused = unused_check(base_catalog["strings"], cur_strings)
    identical, differ, watch = watch_check(repo, baseline)
    findings += wording + missing + unused + watch
    findings.sort(key=lambda f: (f[0],) + tuple((0, x) if isinstance(x, int) else (1, x) for x in f[1]))

    sys.stdout.write(render(baseline, how, rows, (checked, lost), (identical, differ), findings))
    if findings:
        return 1
    if args.write_key_map:
        write_key_map(repo, baseline, key_map)
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Prove that every lookup key the main app uses still resolves to its Baseline wording.")
    parser.add_argument("--baseline", metavar="<rev>",
                        help="Baseline commit (default: merge-base of HEAD and origin/develop)")
    parser.add_argument("--derived-data", metavar="<path>",
                        help="where the dashpay build's .stringsdata files are read from (default: the latest build)")
    parser.add_argument("--write-key-map", action="store_true",
                        help="on a pass, write %s" % KEY_MAP)
    parser.add_argument("--release", action="store_true", help="release mode (not available yet)")
    args = parser.parse_args(argv)
    if args.release:
        refused = [f for f, on in (("--baseline", args.baseline), ("--derived-data", args.derived_data),
                                   ("--write-key-map", args.write_key_map)) if on]
        if refused:
            raise CannotRun("--release refuses %s" % ", ".join(refused))
        raise CannotRun("--release is not available yet")
    return args


def main(argv):
    try:
        return check(parse_args(argv))
    except CannotRun as e:
        message = str(e)
    except (generate_catalog.GenerateError, catalog_io.CatalogIOError, foundation_format.FormatError,
            subprocess.CalledProcessError, OSError, ValueError, KeyError) as e:
        message = "%s: %s" % (type(e).__name__, e)
    sys.stderr.write("error: %s\n" % " ".join(message.split()))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

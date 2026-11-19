#!/usr/bin/env python3
"""Write the Baseline forms fixture of the plural-fidelity test (string-catalogs-migration T16, AC-02, AC-07).

For every counted phrase of the Baseline (the keys of en.lproj/Localizable.stringsdict), every locale
the app compiles (XCSTRINGS_LANGUAGES_TO_COMPILE) and the counts 0, 1, 2, 5, 21, 101, it formats the
Baseline lists with the zero-loss check's formatter and records the text, the key the code looks the
phrase up by now (from the key map) and the arguments it used. A Baseline translation that takes an
argument as the wrong type formats undefined text; like the zero-loss check, the fixture leaves it out
(its forms are null and `defects` names it). Per locale it also records the keys
whose Baseline entry has plural variants there. The other 21 locales of the Catalog are covered by
the zero-loss check, which formats the same counts.

The Baseline is the key map's, so run this after the zero-loss check rewrote the key map (after every
rebase, AC-18):
    python3 scripts/localization/baseline_plural_forms.py
"""
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import foundation_format  # noqa: E402
import baseline_lists  # noqa: E402
import zero_loss_check as zl  # noqa: E402

OUT = "DashWalletTests/Localization/BaselinePluralForms.json"
PROJECT = "DashWallet.xcodeproj/project.pbxproj"
# The code interpolates these types; the compiler writes their codes into the key.
INTERPOLATION_TYPES = {"lld": "int", "llu": "uint", "@": "string", "lf": "double", "f": "double"}
DERIVED_CODE = re.compile(r"%(lld|llu|@|lf|f)")


def compiled_locales(repo):
    """The locales of XCSTRINGS_LANGUAGES_TO_COMPILE; every build configuration must list the same."""
    with open(os.path.join(repo, PROJECT), encoding="utf-8") as f:
        blocks = re.findall(r"XCSTRINGS_LANGUAGES_TO_COMPILE = \(([^)]*)\);", f.read())
    sets = {tuple(sorted(x.strip().strip('"') for x in b.split(",") if x.strip())) for b in blocks}
    if len(sets) != 1:
        sys.exit("error: XCSTRINGS_LANGUAGES_TO_COMPILE differs between build configurations")
    return list(sets.pop())


def stringsdict(repo, rev, locale):
    res = zl.git(repo, "show", "%s:%s/%s.lproj/Localizable.stringsdict" % (rev, baseline_lists.LISTS_DIR, locale))
    return plistlib.loads(res.stdout) if res.returncode == 0 else {}


def arg_types(baseline_key, key, args):
    """Types the test passes: for an interpolated key (moved) the codes of its key, in order; for a key
    the code still formats itself, the kind of each sample argument."""
    if key == baseline_key:
        return ["double" if isinstance(a, float) else "int" if isinstance(a, int) else "string" for a in args]
    positions = [int(p) for p in re.findall(r"%(\d+)\$", baseline_key)]
    if positions != sorted(positions):
        sys.exit("error: %r reorders its arguments; the interpolated key %r cannot be checked" % (baseline_key, key))
    types = [INTERPOLATION_TYPES[c] for c in DERIVED_CODE.findall(key.replace("%%", ""))]
    if len(types) != len(args):
        sys.exit("error: %r has %d interpolations but %d sample arguments" % (key, len(types), len(args)))
    return types


def main():
    repo = zl.repo_root()
    rev, key_map = zl.read_key_map(repo)
    locales = compiled_locales(repo)
    english = stringsdict(repo, rev, "en")
    specs = zl.counted_specs(repo, rev, locales)
    base_strings = baseline_lists.build_catalog(repo, rev)["strings"]

    phrases, requests, defects = [], [], []
    for b in sorted(english):
        args = [zl.counted_args(specs[b], n) for n in zl.COUNTS]
        have = base_strings[b]["localizations"]
        broken = {l for l in locales if l in have and zl.defective_translation(have[l], args[0]) is not None}
        defects += [{"baseline_key": b, "locale": l} for l in sorted(broken)]
        for key in key_map.get(b, [b]):
            phrases.append({"baseline_key": b, "key": key, "interpolated": key != b,
                            "types": arg_types(b, key, args[0]), "args": args, "forms": {}})
            requests += [(locale, b, a) for locale in locales if locale not in broken for a in args]

    with tempfile.TemporaryDirectory(prefix="plural-forms-") as tmp:
        tar = zl.git(repo, "archive", rev, baseline_lists.LISTS_DIR).stdout
        subprocess.run(["tar", "-x", "-C", tmp], input=tar, check=True)
        out = foundation_format.format_texts(os.path.join(tmp, baseline_lists.LISTS_DIR), requests)

    texts = iter(out)
    for phrase in phrases:
        for locale in locales:
            if {"baseline_key": phrase["baseline_key"], "locale": locale} in defects:
                phrase["forms"][locale] = None
                continue
            forms = [next(texts)["text"] for _ in zl.COUNTS]
            if foundation_format.CRASH_SENTINEL in forms:
                sys.exit("error: the formatter crashed on %r in %s" % (phrase["baseline_key"], locale))
            phrase["forms"][locale] = forms

    variants = {}
    for locale in locales:
        keys = set()
        for b in stringsdict(repo, rev, locale):
            keys.add(b)
            keys.update(key_map.get(b, []))
        variants[locale] = sorted(keys)

    fixture = {"baseline": rev, "counts": list(zl.COUNTS), "defects": defects, "locales": locales,
               "phrases": phrases, "variant_keys": variants}
    with open(os.path.join(repo, OUT), "w", encoding="utf-8") as f:
        json.dump(fixture, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")
    print("%s: %d phrases x %d locales x %d counts, Baseline %s"
          % (OUT, len(phrases), len(locales), len(zl.COUNTS), rev[:12]))


if __name__ == "__main__":
    main()

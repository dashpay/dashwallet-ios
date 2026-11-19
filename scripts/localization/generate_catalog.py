#!/usr/bin/env python3
"""Generate DashWallet/Localizable.xcstrings from the Baseline per-locale lists.

    python3 scripts/localization/generate_catalog.py --rev <rev> --repo <path> --out <file>

Reads DashWallet/<lang>.lproj/Localizable.strings and .stringsdict of every locale
folder with `git show <rev>:<path>` (never the working tree). Exits non-zero naming
file and key on any failure, and writes nothing.
"""
import argparse
import plistlib
import re
import subprocess
import sys

import catalog_io

LISTS_DIR = "DashWallet"
FORMAT_KEY = "NSStringLocalizedFormatKey"
SPEC_TYPE_KEY = "NSStringFormatSpecTypeKey"
VALUE_TYPE_KEY = "NSStringFormatValueTypeKey"
PLURAL_RULE = "NSStringPluralRuleType"

WHOLE_VARIABLE = re.compile(r"%(?:\d+\$)?#@(\w+)@")
NUMERIC_SPEC = re.compile(r"%(?:\d+\$)?l{0,2}[du]")


class GenerateError(Exception):
    pass


# --- .strings parser ---------------------------------------------------------

SIMPLE_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
                  '"': '"', "\\": "\\", "'": "'"}
HEX = "0123456789abcdefABCDEF"


def parse_strings(text, where):
    """Return [(key, value)] of a .strings list; GenerateError names `where` and the line."""
    pos, length = 0, len(text)

    def fail(message):
        raise GenerateError("%s:%d: %s" % (where, text.count("\n", 0, pos) + 1, message))

    def skip_space():
        nonlocal pos
        while pos < length:
            if text[pos].isspace():
                pos += 1
            elif text.startswith("/*", pos):
                end = text.find("*/", pos + 2)
                if end < 0:
                    fail("unterminated comment")
                pos = end + 2
            elif text.startswith("//", pos):
                end = text.find("\n", pos)
                pos = length if end < 0 else end + 1
            else:
                break

    def read_string():
        nonlocal pos
        if pos >= length or text[pos] != '"':
            fail("expected a quoted string")
        pos += 1
        out = []
        while True:
            if pos >= length:
                fail("unterminated string")
            ch = text[pos]
            if ch == '"':
                pos += 1
                return "".join(out)
            if ch != "\\":
                out.append(ch)
                pos += 1
                continue
            pos += 1
            if pos >= length:
                fail("unterminated string")
            esc = text[pos]
            if esc in "uU":
                digits = text[pos + 1:pos + 5]
                if len(digits) != 4 or any(c not in HEX for c in digits):
                    fail("bad \\%s escape" % esc)
                out.append(chr(int(digits, 16)))
                pos += 5
            elif esc in SIMPLE_ESCAPES:
                out.append(SIMPLE_ESCAPES[esc])
                pos += 1
            elif esc in "01234567":
                end = pos
                while end < length and end < pos + 3 and text[end] in "01234567":
                    end += 1
                out.append(chr(int(text[pos:end], 8)))
                pos = end
            else:
                fail("unknown escape \\%s" % esc)

    entries = []
    while True:
        skip_space()
        if pos >= length:
            return merge_surrogates(entries)
        key = read_string()
        skip_space()
        if pos >= length or text[pos] != "=":
            fail('expected "=" after key "%s"' % key)
        pos += 1
        skip_space()
        value = read_string()
        skip_space()
        if pos >= length or text[pos] != ";":
            fail('expected ";" after key "%s"' % key)
        pos += 1
        entries.append((key, value))


def merge_surrogates(entries):
    """\\UD83D\\UDE00 decodes to two surrogate halves; join them into one character."""
    def merge(s):
        return s.encode("utf-16", "surrogatepass").decode("utf-16") if re.search("[\ud800-\udfff]", s) else s
    return [(merge(k), merge(v)) for k, v in entries]


# --- Baseline access ------------------------------------------------------------

def git(repo, *args, check=True):
    res = subprocess.run(["git", "-C", repo] + list(args), capture_output=True)
    if check and res.returncode != 0:
        raise GenerateError("git %s failed: %s" % (" ".join(args), res.stderr.decode("utf-8", "replace").strip()))
    return res


def locale_files(repo, rev):
    """{locale: set of file names} for every DashWallet/<locale>.lproj at `rev`."""
    out = git(repo, "ls-tree", "-r", "--name-only", rev, "--", LISTS_DIR + "/").stdout.decode("utf-8")
    found = {}
    for path in out.splitlines():
        parts = path.split("/")
        if len(parts) == 3 and parts[1].endswith(".lproj") and parts[2] in ("Localizable.strings", "Localizable.stringsdict"):
            found.setdefault(parts[1][:-len(".lproj")], set()).add(parts[2])
    return found


def show(repo, rev, path):
    return git(repo, "show", "%s:%s" % (rev, path)).stdout


def decode(raw, where):
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    try:
        if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
            return raw.decode("utf-16")
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise GenerateError("%s: not valid text: %s" % (where, exc))


# --- .stringsdict -> localization ---------------------------------------------------

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural_localization(key, spec, where):
    def bad(why):
        raise GenerateError('%s: key "%s": %s' % (where, key, why))

    if not isinstance(spec, dict) or not isinstance(spec.get(FORMAT_KEY), str):
        bad("unknown .stringsdict shape (no %s)" % FORMAT_KEY)
    fmt = spec[FORMAT_KEY]
    variables = {}
    for name, body in spec.items():
        if name == FORMAT_KEY:
            continue
        if not isinstance(body, dict) or body.get(SPEC_TYPE_KEY) != PLURAL_RULE \
                or not isinstance(body.get(VALUE_TYPE_KEY), str):
            bad('unknown .stringsdict shape (variable "%s" is not a plural rule)' % name)
        forms = {c: v for c, v in body.items() if c not in (SPEC_TYPE_KEY, VALUE_TYPE_KEY)}
        if not forms or not all(isinstance(v, str) for v in forms.values()):
            bad('unknown .stringsdict shape (variable "%s" has no string forms)' % name)
        variables[name] = (body[VALUE_TYPE_KEY], forms)
    if not variables:
        bad("unknown .stringsdict shape (no plural variable)")

    whole = WHOLE_VARIABLE.fullmatch(fmt)
    if whole and len(variables) == 1:
        _, forms = next(iter(variables.values()))
        if list(forms) == ["other"]:
            return unit(forms["other"])
        if all(NUMERIC_SPEC.search(v) for v in forms.values()):
            return {"variations": {"plural": {c: unit(v) for c, v in forms.items()}}}

    substitutions = {}
    for ordinal, (name, (specifier, forms)) in enumerate(variables.items(), start=1):
        found = re.search(r"%(\d+)\$#@" + re.escape(name) + "@", fmt)
        substitutions[name] = {
            "argNum": int(found.group(1)) if found else ordinal,
            "formatSpecifier": specifier,
            "variations": {"plural": {c: unit(NUMERIC_SPEC.sub("%arg", v, count=1))
                                      for c, v in forms.items()}}}
    return {"stringUnit": {"state": "translated", "value": fmt}, "substitutions": substitutions}


# --- generation ------------------------------------------------------------------------

def build_catalog(repo, rev):
    strings = {}
    for locale, files in sorted(locale_files(repo, rev).items()):
        base = "%s/%s.lproj/" % (LISTS_DIR, locale)
        localized = {}
        if "Localizable.strings" in files:
            where = base + "Localizable.strings"
            for key, value in parse_strings(decode(show(repo, rev, where), where), where):
                if key in localized:
                    raise GenerateError('%s: duplicate key "%s"' % (where, key))
                localized[key] = unit(value)
        if "Localizable.stringsdict" in files:
            where = base + "Localizable.stringsdict"
            try:
                plist = plistlib.loads(show(repo, rev, where))
            except Exception as exc:
                raise GenerateError("%s: cannot parse: %s" % (where, exc))
            if not isinstance(plist, dict):
                raise GenerateError("%s: root is not a dictionary" % where)
            for key, spec in plist.items():
                localized[key] = plural_localization(key, spec, where)  # .stringsdict wins over .strings
        for key, localization in localized.items():
            strings.setdefault(key, {"localizations": {}})["localizations"][locale] = localization
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rev", required=True, help="Baseline revision to read the lists from")
    parser.add_argument("--repo", default=".", help="repository path (default: current directory)")
    parser.add_argument("--out", required=True, help="Catalog file to write")
    args = parser.parse_args(argv)
    try:
        catalog = build_catalog(args.repo, args.rev)
        catalog_io.write_catalog(args.out, catalog)
    except (GenerateError, catalog_io.CatalogIOError) as exc:
        print("generate_catalog: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

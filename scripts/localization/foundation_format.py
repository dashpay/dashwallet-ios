"""Python wrapper over the Foundation formatter (format.swift).

API
---
format_texts(lproj_root, requests) -> list[FormatResult]

  lproj_root  directory holding <locale>.lproj/Localizable.strings (+ .stringsdict):
              the Baseline lists or `xcstringstool compile` output.
  requests    iterable of (locale, key, args); `args` is a list of sample
              arguments or None. With None the samples are inferred from the
              English (`en`) format codes of `key`, one distinct value per
              position n (1-based; positional `%2$@` counts as position 2):
                  %@                  -> "‹a<n>›"
                  %d %i %ld %lld %u   -> 1000 + n
                  %f                  -> 1000 + n + 0.5
              Inference covers `.strings` keys; a counted phrase (stringsdict)
              must be given explicit args (the count, plus any other arguments).
  returns     one FormatResult per request, in order: a dict
              {"locale", "key", "args", "text"}; `args` are the samples used.
              A key absent in the locale's table gives text == key.

Every request is formatted with String(format:locale:arguments:) under its own
locale in one process; the process locale never decides plural rules.

CLI
---
python3 foundation_format.py --self-test
    Formats a built-in `uk` counted phrase for 2 and 5; exit 0 when the plural forms
    differ, exit 2 (message on stderr) when they are the same. The environment
    variable FORMATTER_FORCE_ROUTE=localizedStringWithFormat forces the wrong
    route (Locale.current decides), so a test can prove the self-test fails.
"""
import hashlib
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FORMAT_SOURCE = os.path.join(HERE, "format.swift")
FORCE_ROUTE_ENV = "FORMATTER_FORCE_ROUTE"
WRONG_ROUTE = "localizedStringWithFormat"


class FormatError(Exception):
    pass


def _binary():
    """Compile format.swift once into a cache outside the repository (FORMATTER_CACHE overrides)."""
    with open(FORMAT_SOURCE, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()[:16]
    cache = os.environ.get("FORMATTER_CACHE") or os.path.join(
        os.path.expanduser("~"), "Library", "Caches", "dashwallet-foundation-format")
    binary = os.path.join(cache, "format-" + digest)
    if not os.path.exists(binary):
        os.makedirs(cache, exist_ok=True)
        partial = "%s.%d.tmp" % (binary, os.getpid())
        res = subprocess.run(["xcrun", "swiftc", "-O", "-o", partial, FORMAT_SOURCE],
                             capture_output=True, text=True)
        if res.returncode != 0:
            raise FormatError("cannot compile %s:\n%s" % (FORMAT_SOURCE, res.stderr))
        os.replace(partial, binary)
    return binary


def format_texts(lproj_root, requests):
    lines = [json.dumps({"locale": loc, "key": key, "args": args}, ensure_ascii=False)
             for loc, key, args in requests]
    if not lines:
        return []
    res = subprocess.run([_binary(), lproj_root], input="\n".join(lines) + "\n",
                         capture_output=True, text=True, encoding="utf-8")
    if res.returncode != 0:
        raise FormatError("format failed (%d): %s" % (res.returncode, res.stderr.strip()))
    results = [json.loads(line) for line in res.stdout.splitlines() if line]
    if len(results) != len(lines):
        raise FormatError("format returned %d results for %d requests" % (len(results), len(lines)))
    return results


_SELF_TEST_KEY = "%d parcels"
_SELF_TEST_DICT = """<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>%s</key><dict>
<key>NSStringLocalizedFormatKey</key><string>%%#@count@</string>
<key>count</key><dict>
<key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
<key>NSStringFormatValueTypeKey</key><string>d</string>
<key>one</key><string>%%d %s</string>
<key>few</key><string>%%d %s</string>
<key>many</key><string>%%d %s</string>
<key>other</key><string>%%d %s</string>
</dict></dict></dict></plist>
"""


def self_test():
    """Return None when `uk` forms differ for 2 and 5, else a message."""
    with tempfile.TemporaryDirectory(prefix="format-selftest-") as root:
        for loc, forms in (("uk", ("посилка", "посилки", "посилок", "посилки")),
                           ("en", ("parcel", "parcels", "parcels", "parcels"))):
            lproj = os.path.join(root, loc + ".lproj")
            os.makedirs(lproj)
            with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
                f.write("")
            with open(os.path.join(lproj, "Localizable.stringsdict"), "w", encoding="utf-8") as f:
                f.write(_SELF_TEST_DICT % ((_SELF_TEST_KEY,) + forms))
        two, five = (r["text"] for r in format_texts(
            root, [("uk", _SELF_TEST_KEY, [2]), ("uk", _SELF_TEST_KEY, [5])]))
    # Compare the word forms, not the digits: 2 and 5 always differ as numbers.
    if two.replace("2", "").strip() == five.replace("5", "").strip():
        return ("self-test failed: uk formats 2 and 5 with the same plural form (%r, %r); the "
                "formatter is not applying the locale's plural rules" % (two, five))
    return None


def main(argv):
    if argv != ["--self-test"]:
        sys.stderr.write("usage: foundation_format.py --self-test\n")
        return 64
    try:
        problem = self_test()
    except FormatError as e:
        problem = "self-test could not run: %s" % e
    if problem:
        sys.stderr.write(problem + "\n")
        return 2
    print("self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Fail when Swift code in the app or its unit tests still calls NSLocalizedString.

Swift looks texts up with String(localized:) since the String Catalog move
(docs/features/string-catalogs-migration, AC-08, AC-17). Objective-C keeps
NSLocalizedString and is not scanned; neither is the Watch app.

Prints `<file>:<line>: NSLocalizedString in Swift` per call and exits 1 on any.
"""
import argparse
import os
import sys

SCANNED_DIRS = ("DashWallet", "DashWalletTests")
CALL = "NSLocalizedString("


def code_lines(text):
    """Yield (line number, code) with comments and string literals blanked out."""
    out, i, n, line = [], 0, len(text), 1
    depth = 0          # nesting depth of /* */ comments
    in_string = None   # '"' or '"""' while inside a string literal
    while i < n:
        c = text[i]
        if c == "\n":
            yield line, "".join(out)
            out, line = [], line + 1
            i += 1
            continue
        if depth:
            if text.startswith("/*", i):
                depth += 1
                i += 2
            elif text.startswith("*/", i):
                depth -= 1
                i += 2
            else:
                i += 1
            continue
        if in_string:
            if c == "\\":
                i += 2
            elif text.startswith(in_string, i):
                i += len(in_string)
                in_string = None
            else:
                i += 1
            continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith("/*", i):
            depth = 1
            i += 2
            continue
        if text.startswith('"""', i):
            in_string = '"""'
            i += 3
            continue
        if c == '"':
            in_string = '"'
            i += 1
            continue
        out.append(c)
        i += 1
    yield line, "".join(out)


def swift_files(root):
    for top in SCANNED_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, top)):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("WatchApp"))
            for name in sorted(filenames):
                if name.endswith(".swift"):
                    yield os.path.join(dirpath, name)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    args = parser.parse_args(argv)
    hits = []
    for path in swift_files(args.root):
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        if CALL not in text:
            continue
        rel = os.path.relpath(path, args.root)
        hits += ["%s:%d: NSLocalizedString in Swift" % (rel, ln) for ln, code in code_lines(text) if CALL in code]
    for hit in hits:
        print(hit)
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())

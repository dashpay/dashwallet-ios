#!/usr/bin/env python3
"""Fail when Swift code in the app or its unit tests still calls NSLocalizedString.

Swift looks texts up with String(localized:) since the String Catalog move
(docs/features/string-catalogs-migration/README.md). Objective-C keeps
NSLocalizedString and is not scanned; neither is the Watch app.

Prints `<file>:<line>: NSLocalizedString in Swift` per call and exits 1 on any.
"""
import argparse
import os
import re
import sys

SCANNED_DIRS = ("DashWallet", "DashWalletTests")
CALL = re.compile(r"NSLocalizedString\s*\(")
OPENING = re.compile(r'(#*)("""|")')


def code_lines(text):
    """Yield (line number, code) with comments and string literals blanked out.

    Handles nested comments, plain, raw (#"..."#) and multi-line literals, and
    `\\(...)` interpolations, whose content is code again (nesting included).
    """
    out, i, n, line = [], 0, len(text), 1
    depth = 0   # nesting depth of /* */ comments
    stack = []  # open literals ("str", closer, escape) and interpolations ["code", open parens]
    while i < n:
        c = text[i]
        top = stack[-1] if stack else None
        if c == "\n":
            yield line, "".join(out)
            out, line = [], line + 1
            i += 1
        elif depth:
            step = 2 if text.startswith(("/*", "*/"), i) else 1
            depth += {"/*": 1, "*/": -1}.get(text[i:i + 2], 0)
            i += step
        elif top and top[0] == "str":
            _, closer, esc = top
            if text.startswith(esc + "(", i):
                stack.append(["code", 0])
                i += len(esc) + 1
            elif text.startswith(esc, i):
                i += len(esc) + (text[i + len(esc):i + len(esc) + 1] not in ("\n", ""))
            elif text.startswith(closer, i):
                stack.pop()
                i += len(closer)
            else:
                i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            depth = 1
            i += 2
        elif opening := OPENING.match(text, i):
            hashes, quotes = opening.groups()
            stack.append(("str", quotes + hashes, "\\" + hashes))
            i = opening.end()
        else:
            if top and c in "()":
                if c == "(":
                    top[1] += 1
                elif top[1]:
                    top[1] -= 1
                else:
                    stack.pop()
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
        if "NSLocalizedString" not in text:
            continue
        rel = os.path.relpath(path, args.root)
        hits += ["%s:%d: NSLocalizedString in Swift" % (rel, ln) for ln, code in code_lines(text) if CALL.search(code)]
    for hit in hits:
        print(hit)
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())

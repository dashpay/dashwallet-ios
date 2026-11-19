#!/usr/bin/env python3
"""Make DashWallet.xcodeproj reference DashWallet/Localizable.xcstrings instead of the
43 Localizable.strings and 43 Localizable.stringsdict lists (string-catalogs-migration T12).

The `Localizable.strings` variant group becomes a plain file reference to the Catalog
(same object id, so every target's build file keeps pointing at it); the
`Localizable.stringsdict` variant group, its build files and every per-locale child
reference of both groups are removed. Idempotent.

Usage: catalog_project.py <project.pbxproj>   (rewrites the file in place)
"""
import re
import sys

STRINGS_GROUP = "757E09971ADB8EEB006FD352"
STRINGSDICT_GROUP = "2ADC722723B5547000D9DD37"

CATALOG_REF = ("\t\t%s /* Localizable.xcstrings */ = {isa = PBXFileReference; "
               "lastKnownFileType = text.json.xcstrings; path = Localizable.xcstrings; "
               'sourceTree = "<group>"; };\n' % STRINGS_GROUP)


def _object_block(text, oid):
    return re.search(r"\t\t" + oid + r" /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXVariantGroup;\n.*?\n\t\t\};\n", text, re.S)


def _children(block):
    inner = block.split("children = (", 1)[1].split(");", 1)[0]
    return re.findall(r"([0-9A-F]{24}) /\*", inner)


def _insert_sorted(text, section, line, oid):
    begin = "/* Begin %s section */\n" % section
    start = text.index(begin) + len(begin)
    end = text.index("/* End %s section */" % section)
    pos = end
    for m in re.finditer(r"^\t\t([0-9A-F]{24}) ", text[start:end], re.M):
        if m.group(1) > oid:
            pos = start + m.start()
            break
    return text[:pos] + line + text[pos:]


def reference_catalog(text):
    if CATALOG_REF in text:
        return text
    for gid in (STRINGS_GROUP, STRINGSDICT_GROUP):
        block = _object_block(text, gid)
        if block is None:
            raise ValueError("variant group %s not found" % gid)
        for child in _children(block.group(0)):
            text = re.sub(r"\t\t" + child + r" /\* [^\n]*\*/ = \{isa = PBXFileReference;[^\n]*\n", "", text)
        text = text.replace(_object_block(text, gid).group(0), "")
    # stringsdict: its build files and every list entry that names it
    for bf in re.findall(r"\t\t([0-9A-F]{24}) /\* Localizable\.stringsdict in Resources \*/ = \{isa = PBXBuildFile;", text):
        text = re.sub(r"\t+" + bf + r" /\*[^\n]*\n", "", text)
    text = re.sub(r"\t+" + STRINGSDICT_GROUP + r" /\* Localizable\.stringsdict \*/,\n", "", text)
    # strings: the same object id now names the Catalog file
    text = text.replace(STRINGS_GROUP + " /* Localizable.strings */", STRINGS_GROUP + " /* Localizable.xcstrings */")
    text = text.replace("/* Localizable.strings in Resources */", "/* Localizable.xcstrings in Resources */")
    return _insert_sorted(text, "PBXFileReference", CATALOG_REF, STRINGS_GROUP)


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        text = f.read()
    new = reference_catalog(text)
    if new != text:
        with open(argv[1], "w", encoding="utf-8") as f:
            f.write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

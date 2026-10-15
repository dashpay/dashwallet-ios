#!/usr/bin/env python3
"""Fail when a DashWalletTests source file is not compiled by the test target.

The project lists most files explicitly in project.pbxproj; a test dropped
into DashWalletTests/ without the four pbxproj entries silently never runs.
Folders attached to the target as file-system synchronized groups (today
DashWalletTests/Notifications) are picked up by Xcode automatically, so files
under them are exempt. Also fails on a listed file that no longer exists.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PBXPROJ = ROOT / "DashWallet.xcodeproj/project.pbxproj"
TESTS_DIR = ROOT / "DashWalletTests"
TEST_TARGET_ID = "75D5F3E4191EC270004AB296"
SOURCES_PHASE_ID = "75D5F3E1191EC270004AB296"
SOURCE_SUFFIXES = {".swift", ".m", ".mm"}


def block(text, object_id):
    match = re.search(rf"^\t\t{object_id} /\* [^*]* \*/ = \{{\n(.*?)^\t\t\}};", text, re.S | re.M)
    if not match:
        raise SystemExit(f"{PBXPROJ}: object {object_id} not found")
    return match[1]


def main():
    text = PBXPROJ.read_text()

    listed = set(re.findall(r"/\* ([^*/]+) in Sources \*/", block(text, SOURCES_PHASE_ID)))

    synced_paths = []
    target = block(text, TEST_TARGET_ID)
    groups = re.search(r"fileSystemSynchronizedGroups = \((.*?)\);", target, re.S)
    for group_id in re.findall(r"([0-9A-F]{24}) /\*", groups[1] if groups else ""):
        path = re.search(r"path = ([^;]+);", block(text, group_id))
        if path:
            synced_paths.append((ROOT / path[1].strip('"')).resolve())

    on_disk = sorted(p for p in TESTS_DIR.rglob("*") if p.suffix in SOURCE_SUFFIXES)
    problems = []

    # The Sources phase only names basenames, so membership is matched by basename.
    # That is sound only while basenames are unique: a second `X.swift` in another
    # folder would hide behind the registered one (and Xcode could not compile two
    # X.o into one target anyway), so duplicates are an error in their own right.
    by_name = {}
    for path in on_disk:
        by_name.setdefault(path.name, []).append(path)
    for name, paths in sorted(by_name.items()):
        if len(paths) > 1:
            listing = ", ".join(str(p.relative_to(ROOT)) for p in paths)
            problems.append(f"duplicate test source basename {name}: {listing} (rename one)")

    for path in on_disk:
        if any(path.is_relative_to(synced) for synced in synced_paths):
            continue
        if path.name not in listed:
            problems.append(f"not in target: {path.relative_to(ROOT)} "
                            "(add PBXBuildFile, PBXFileReference, group child and Sources entries)")
    names_on_disk = {p.name for p in on_disk}
    for name in sorted(listed):
        if Path(name).suffix in SOURCE_SUFFIXES and name not in names_on_disk:
            problems.append(f"listed but missing on disk: {name}")

    if problems:
        print("\n".join(problems))
        return 1
    print(f"ok: {len(on_disk)} test sources, {len(listed)} explicit, "
          f"{len(synced_paths)} synchronized folder(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

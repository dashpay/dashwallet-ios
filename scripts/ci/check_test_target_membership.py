#!/usr/bin/env python3
"""Fail when a DashWalletTests source file is not compiled by the test target.

The project lists most files explicitly in project.pbxproj; a test dropped
into DashWalletTests/ without the four pbxproj entries silently never runs.
Folders attached to the target as file-system synchronized groups (today
DashWalletTests/Notifications) are picked up by Xcode automatically, so files
under them are compiled unless a membership exception for this target excludes
them. Also fails on a listed file that no longer exists, and on two test
sources sharing a basename (the Sources phase only names basenames, and Xcode
could not compile two X.o into one target anyway).
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

# Xcode writes an object either on one line (`ID /* n */ = {isa = …; path = …; };`)
# or over several, closed by `};` on its own two-tab line. Nested dictionaries in
# the multi-line form close on a deeper-indented line, so `\n\t\t};` is unambiguous.
OBJECT = re.compile(
    r"^\t\t(?P<id>[0-9A-F]{24}) (?:/\* .*? \*/ )?= \{"
    r"(?:(?P<single>[^\n]*?)\};[ \t]*$|\n(?P<multi>.*?)\n\t\t\};)",
    re.S | re.M,
)
IDS = re.compile(r"([0-9A-F]{24}) /\*")


def parse_objects(text):
    objects = {}
    for match in OBJECT.finditer(text):
        body = match.group("single")
        if body is None:
            body = match.group("multi")
        objects[match.group("id")] = body
    return objects


def attr(body, key):
    """Scalar `key = value;` (quoted or bare), or None."""
    match = re.search(rf"(?<![A-Za-z]){re.escape(key)} = (\"(?:[^\"\\\\]|\\\\.)*\"|[^;]+);", body)
    if not match:
        return None
    value = match[1].strip()
    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1].replace('\\"', '"')
    return value


def listed_ids(body, key):
    match = re.search(rf"(?<![A-Za-z]){re.escape(key)} = \((.*?)\);", body, re.S)
    return IDS.findall(match[1]) if match else []


def listed_paths(body, key):
    match = re.search(rf"(?<![A-Za-z]){re.escape(key)} = \((.*?)\);", body, re.S)
    if not match:
        return []
    paths = []
    for item in match[1].split(","):
        item = item.strip()
        if item.startswith('"') and item.endswith('"'):
            item = item[1:-1]
        if item:
            paths.append(item)
    return paths


def parent_map(objects):
    parents = {}
    for object_id, body in objects.items():
        for child in listed_ids(body, "children"):
            parents[child] = object_id
    return parents


def resolve_path(object_id, objects, parents):
    """Absolute folder of a group, walking parent-relative paths up to the root."""
    parts = []
    current = object_id
    while current is not None:
        body = objects[current]
        source_tree = attr(body, "sourceTree") or "<group>"
        path = attr(body, "path")
        if path:
            parts.append(path)
        if source_tree != "<group>":
            if source_tree != "SOURCE_ROOT":
                raise SystemExit(f"{PBXPROJ}: object {current} uses sourceTree {source_tree}, "
                                 "which this check does not resolve")
            break
        current = parents.get(current)
    return ROOT.joinpath(*reversed(parts)).resolve()


def main():
    objects = parse_objects(PBXPROJ.read_text())
    for required in (TEST_TARGET_ID, SOURCES_PHASE_ID):
        if required not in objects:
            raise SystemExit(f"{PBXPROJ}: object {required} not found")
    parents = parent_map(objects)

    listed = set(re.findall(r"/\* ([^*/]+) in Sources \*/", objects[SOURCES_PHASE_ID]))

    synced = []  # (folder, excluded file paths for this target)
    for group_id in listed_ids(objects[TEST_TARGET_ID], "fileSystemSynchronizedGroups"):
        if group_id not in objects:
            raise SystemExit(f"{PBXPROJ}: synchronized group {group_id} not found")
        folder = resolve_path(group_id, objects, parents)
        excluded = set()
        for exception_id in listed_ids(objects[group_id], "exceptions"):
            exception = objects.get(exception_id, "")
            target = listed_ids(exception, "target") or IDS.findall(attr(exception, "target") or "")
            if TEST_TARGET_ID in target:
                excluded.update((folder / p).resolve() for p in listed_paths(exception, "membershipExceptions"))
        synced.append((folder, excluded))

    on_disk = sorted(p for p in TESTS_DIR.rglob("*") if p.suffix in SOURCE_SUFFIXES)
    problems = []

    by_name = {}
    for path in on_disk:
        by_name.setdefault(path.name, []).append(path)
    for name, paths in sorted(by_name.items()):
        if len(paths) > 1:
            listing = ", ".join(str(p.relative_to(ROOT)) for p in paths)
            problems.append(f"duplicate test source basename {name}: {listing} (rename one)")

    for path in on_disk:
        relative = path.relative_to(ROOT)
        owner = next(((folder, excluded) for folder, excluded in synced if path.is_relative_to(folder)), None)
        if owner is not None:
            if path in owner[1]:
                problems.append(f"excluded from the target by a membership exception: {relative}")
            continue
        if path.name not in listed:
            problems.append(f"not in target: {relative} "
                            "(add PBXBuildFile, PBXFileReference, group child and Sources entries)")
    names_on_disk = {p.name for p in on_disk}
    for name in sorted(listed):
        if Path(name).suffix in SOURCE_SUFFIXES and name not in names_on_disk:
            problems.append(f"listed but missing on disk: {name}")

    if problems:
        print("\n".join(problems))
        return 1
    folders = ", ".join(str(folder.relative_to(ROOT)) for folder, _ in synced) or "none"
    print(f"ok: {len(on_disk)} test sources, {len(listed)} explicit, "
          f"synchronized folder(s): {folders}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

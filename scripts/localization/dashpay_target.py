"""The source files the dashpay target compiles, read from the project file of a checkout.

One list for every localization tool that needs the app's sources: the zero-loss check's places
(`places.py`) and the Catalog test (`tests/test_preview_only_keys.py`).
"""
import json
import os
import subprocess

PROJECT = os.path.join("DashWallet.xcodeproj", "project.pbxproj")
SOURCE_SUFFIXES = (".swift", ".m", ".mm")


def files_under(root):
    return [os.path.join(d, n) for d, _, names in os.walk(root) for n in names if n.endswith(SOURCE_SUFFIXES)]


def sources(root, target_name="dashpay"):
    """Every `.swift` / `.m` / `.mm` file the target compiles, as absolute paths under root: the files of its
    Sources build phase and of its synchronized folders, less the folders' membership exceptions for it. A
    synchronized folder missing on disk compiles nothing."""
    objects = json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", os.path.join(root, PROJECT)],
                                        capture_output=True, check=True).stdout)["objects"]
    parent = {child: key for key, value in objects.items() for child in value.get("children", [])}

    def path(key):
        parts = []
        while key in objects:
            parts.append(objects[key].get("path", ""))
            if objects[key].get("sourceTree") != "<group>":
                break
            key = parent.get(key)
        return os.path.normpath(os.path.join(root, *reversed(parts)))

    target_key, target = next((k, v) for k, v in objects.items()
                              if v.get("isa") == "PBXNativeTarget" and v.get("name") == target_name)
    files = set()
    for phase in target["buildPhases"]:
        if objects[phase]["isa"] == "PBXSourcesBuildPhase":
            files |= {path(objects[f]["fileRef"]) for f in objects[phase]["files"] if "fileRef" in objects[f]}
    for group in target.get("fileSystemSynchronizedGroups", []):
        group_root = path(group)
        excluded = {os.path.join(group_root, name) for exception in objects[group].get("exceptions", [])
                    if objects[exception].get("target") == target_key
                    for name in objects[exception].get("membershipExceptions", [])}
        files |= set(files_under(group_root)) - excluded
    return sorted(f for f in files if f.endswith(SOURCE_SUFFIXES))

"""Lookup places at the Baseline and now, paired by file and ordinal (ADR-0067).

A place is Place(file, line, column, key); `file` is relative to the repo root.
The sources covered are every file under DashWallet/ and every file the dashpay target compiles
(`dashpay_target.sources`, e.g. the Objective-C under DashPay/), each side read from its own project
file. The Today extension's sources are not covered.
"""
import json
import os
import plistlib
import subprocess
import tempfile
from collections import defaultdict, namedtuple

import dashpay_target

Place = namedtuple("Place", "file line column key")

APP_DIR = "DashWallet"
CHUNK = 400  # source files per xcstringstool call, keeps the command line short


class NoStringsdataError(Exception):
    """No .stringsdata files found; the CLI maps this to exit 2."""


def _run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, **kw).stdout


def _extract(root, rel_files, flags):
    """Run xcstringstool over rel_files (relative to root); return Places."""
    root = os.path.realpath(root)
    found = []
    with tempfile.TemporaryDirectory(prefix="places-extract-") as out:
        for i in range(0, len(rel_files), CHUNK):
            chunk_out = os.path.join(out, str(i))
            os.makedirs(chunk_out)
            paths = [os.path.join(root, f) for f in rel_files[i:i + CHUNK]]
            _run(["xcrun", "xcstringstool", "extract"] + flags + ["-o", chunk_out] + paths)
            for fn in sorted(os.listdir(chunk_out)):
                found += _read_stringsdata(os.path.join(chunk_out, fn), [root])
    return found


def _read_stringsdata(path, roots):
    """Places of one .stringsdata file with `source` mapped under any of roots;
    sources outside every root yield nothing."""
    with open(path) as f:
        doc = json.load(f)
    source = doc.get("source", "")
    rel = None
    for root in roots:
        prefix = root.rstrip(os.sep) + os.sep
        if source.startswith(prefix):
            rel = source[len(prefix):]
            break
    if rel is None:
        return []
    out = []
    for entries in doc.get("tables", {}).values():
        for e in entries:
            loc = e["location"]
            out.append(Place(rel, loc["startingLine"], loc["startingColumn"], e["key"]))
    return out


def _app_files(root, suffixes):
    """Files with suffixes under APP_DIR or compiled by the dashpay target, relative to root."""
    root = os.path.realpath(root)
    found = set()
    for dirpath, _, names in os.walk(os.path.join(root, APP_DIR)):
        for n in names:
            if n.endswith(suffixes):
                found.add(os.path.relpath(os.path.join(dirpath, n), root))
    found |= {os.path.relpath(f, root) for f in dashpay_target.sources(root)
              if f.endswith(suffixes) and os.path.isfile(f)}
    return sorted(found)


def _baseline_keys(root):
    """Keys of every en.lproj .strings / .stringsdict under DashWallet/ in root."""
    keys = set()
    for rel in _app_files(root, (".strings", ".stringsdict")):
        if os.path.basename(os.path.dirname(rel)) != "en.lproj":
            continue
        data = _run(["plutil", "-convert", "xml1", "-o", "-", os.path.join(root, rel)])
        keys.update(plistlib.loads(data))
    return keys


def _baseline_compiler_places(stringsdata_dir, baseline_root, present):
    """Places of the Baseline build's .stringsdata, sources mapped to repo-relative files; without
    baseline_root a source maps to the file of `present` it ends with."""
    out = []
    for path in _stringsdata_files(stringsdata_dir):
        with open(path) as f:
            doc = json.load(f)
        source = doc.get("source", "")
        if baseline_root:
            prefix = baseline_root.rstrip(os.sep) + os.sep
            if not source.startswith(prefix):
                continue
            rel = source[len(prefix):]
        else:
            rel = next((f for f in present if source.endswith("/" + f)), None)
            if rel is None:
                continue
        for entries in doc.get("tables", {}).values():
            for e in entries:
                loc = e["location"]
                out.append(Place(rel, loc["startingLine"], loc["startingColumn"], e["key"]))
    return out


def _dedupe(found):
    return list(dict.fromkeys(found))


def baseline_places(repo, rev, baseline_stringsdata=None, baseline_root=None):
    with tempfile.TemporaryDirectory(prefix="places-baseline-") as tmp:
        _archive(repo, rev, [APP_DIR, dashpay_target.PROJECT], tmp)
        # The target's files outside APP_DIR, from the Baseline's own project file.
        outside = [d for d in dashpay_target.top_folders(tmp) if d != APP_DIR]
        _archive(repo, rev, [d for d in outside if _in_rev(repo, rev, d)], tmp)
        keys = _baseline_keys(tmp)
        swift_files = _app_files(tmp, (".swift",))
        if baseline_stringsdata:
            present = set(swift_files)
            swift = [p for p in _baseline_compiler_places(baseline_stringsdata, baseline_root, present)
                     if p.file in present]
            swift += _extract(tmp, swift_files, ["--legacy-localizable-strings"])
            swift = _dedupe(swift)
        else:
            swift = _extract(tmp, swift_files, ["--legacy-localizable-strings", "--SwiftUI"])
        objc = _extract(tmp, _app_files(tmp, (".m", ".mm", ".h")),
                        ["--legacy-localizable-strings"])
    return [p for p in swift if p.key in keys] + objc


def _archive(repo, rev, paths, dest):
    if paths:
        tar = _run(["git", "-C", repo, "archive", rev] + paths)
        subprocess.run(["tar", "-x", "-C", dest], input=tar, check=True)


def _in_rev(repo, rev, path):
    return bool(_run(["git", "-C", repo, "ls-tree", "--name-only", rev, path]).strip())


def _stringsdata_files(stringsdata_dir):
    found = []
    for dirpath, _, names in os.walk(stringsdata_dir):
        found += [os.path.join(dirpath, n) for n in names if n.endswith(".stringsdata")]
    if not found:
        raise NoStringsdataError("no .stringsdata files under %s" % stringsdata_dir)
    return sorted(found)


def current_places(repo, stringsdata_dir):
    files = _stringsdata_files(stringsdata_dir)
    roots = sorted({os.path.realpath(repo), os.path.abspath(repo)})
    swift_files = _app_files(repo, (".swift",))
    # Swift: compiler places of the working tree's Swift files only, since an incremental
    # build keeps the data of a deleted or renamed file (deduped on file/line/column/key
    # across targets; a #Preview reports all its places at one position, so the key is
    # part of the identity), then NSLocalizedString calls the compiler does not report:
    # a legacy place is dropped when the compiler has a place at its position.
    present = set(swift_files)
    compiled = {}
    sourced = set()
    for path in files:
        with open(path) as f:
            src = json.load(f).get("source", "")
        for root in roots:
            if src.startswith(root.rstrip(os.sep) + os.sep):
                sourced.add(src[len(root.rstrip(os.sep)) + 1:])
        for p in _read_stringsdata(path, roots):
            if p.file in present:
                compiled.setdefault(p, p)
    compiled_at = {(p.file, p.line, p.column) for p in compiled}
    legacy = {}
    for p in _extract(repo, swift_files, ["--legacy-localizable-strings"]):
        if (p.file, p.line, p.column) not in compiled_at:
            legacy.setdefault(p, p)
    # Swift files the compiler data has no source entry for (e.g. not built by the
    # dashpay scheme): modern extraction.
    uncovered = [f for f in swift_files if f not in sourced]
    modern = _extract(repo, uncovered, ["--modern-localizable-strings"])
    swift = _dedupe(list(compiled) + list(legacy) + modern)
    objc = _extract(repo, _app_files(repo, (".m", ".mm", ".h")), ["--legacy-localizable-strings"])
    return swift + objc


def pair(baseline, current):
    by_file = defaultdict(lambda: ([], []))
    for p in baseline:
        by_file[p.file][0].append(p)
    for p in current:
        by_file[p.file][1].append(p)
    pairs, mismatched = [], []
    for file in sorted(by_file):
        b, c = (sorted(side, key=lambda p: (p.line, p.column)) for side in by_file[file])
        if len(b) != len(c):
            mismatched.append((file, len(b), len(c)))
        else:
            pairs += zip(b, c)
    return pairs, mismatched


def build_is_stale(repo, stringsdata_dir):
    newest_data = max(os.path.getmtime(p) for p in _stringsdata_files(stringsdata_dir))
    newest_swift = max((os.path.getmtime(os.path.join(repo, f))
                        for f in _app_files(repo, (".swift",))), default=0)
    return newest_data < newest_swift

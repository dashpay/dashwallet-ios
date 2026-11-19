"""Lookup places at the Baseline and now, paired by file and ordinal (T5, ADR-0004).

A place is Place(file, line, column, key); `file` is relative to the repo root.
Only app sources under DashWallet/ are covered.
"""
import json
import os
import plistlib
import subprocess
import tempfile
from collections import defaultdict, namedtuple

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
    root = os.path.realpath(root)
    found = []
    for dirpath, _, names in os.walk(os.path.join(root, APP_DIR)):
        for n in names:
            if n.endswith(suffixes):
                found.append(os.path.relpath(os.path.join(dirpath, n), root))
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


def baseline_places(repo, rev):
    with tempfile.TemporaryDirectory(prefix="places-baseline-") as tmp:
        tar = _run(["git", "-C", repo, "archive", rev, APP_DIR])
        subprocess.run(["tar", "-x", "-C", tmp], input=tar, check=True)
        keys = _baseline_keys(tmp)
        swift = _extract(tmp, _app_files(tmp, (".swift",)),
                         ["--legacy-localizable-strings", "--SwiftUI"])
        objc = _extract(tmp, _app_files(tmp, (".m", ".mm", ".h")),
                        ["--legacy-localizable-strings"])
    return [p for p in swift if p.key in keys] + objc


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
    app_prefix = APP_DIR + os.sep
    # Swift: compiler places (deduped on file/line/column/key across targets;
    # a #Preview reports all its places at one position, so the key is part of
    # the identity), then NSLocalizedString calls the compiler does not report:
    # a legacy place is dropped when the compiler has a place at its position.
    compiled = {}
    for path in files:
        for p in _read_stringsdata(path, roots):
            if p.file.startswith(app_prefix) and p.file.endswith(".swift"):
                compiled.setdefault(p, p)
    compiled_at = {(p.file, p.line, p.column) for p in compiled}
    legacy = {}
    for p in _extract(repo, _app_files(repo, (".swift",)), ["--legacy-localizable-strings"]):
        if (p.file, p.line, p.column) not in compiled_at:
            legacy.setdefault(p, p)
    swift = list(compiled) + list(legacy)
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

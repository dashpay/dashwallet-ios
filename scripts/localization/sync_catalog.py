#!/usr/bin/env python3
"""Sync DashWallet/Localizable.xcstrings with the build's strings (ADR-0071).

Run by the "Sync String Catalog" build phase after compilation, with the Xcode build
environment: SRCROOT, OBJECT_FILE_DIR_normal, TARGET_NAME, and ARCHS: only the <arch> directories of
the build's architectures are scanned, because Xcode keeps the directory of an architecture an earlier
build compiled (one x86_64 build would keep its keys counted as seen). Without ARCHS (the script run
by hand) every <arch> directory under OBJECT_FILE_DIR_normal is scanned.

It collects the compiler's *.stringsdata, runs a legacy (NSLocalizedString-style)
extraction over the target's Swift files (<arch>/<TARGET_NAME>.SwiftFileList) and the
Objective-C .m/.mm files under SRCROOT named in the <arch>/*.d dependency files, runs
`xcstringstool sync` on a snapshot of the Catalog, re-serializes it with catalog_io (the
format the Xcode app writes) and replaces the Catalog only when the bytes changed and the Catalog on
disk still holds the snapshot's bytes; otherwise (an edit saved during the build) it stops with an
error and leaves the edit. Builds of one checkout sync one at a time (a lock on the Catalog's folder).

Only a Debug build syncs: another configuration (Release, TestFlight, TestNet) does not compile
`#if DEBUG` code, so its sync would mark the texts only that code looks up as stale, and the
Catalog would depend on the configuration. Those builds compile the Catalog as committed.
Without CONFIGURATION (the script run by hand or by its tests) it syncs.

SYNC_CATALOG_PATH (optional) overrides the Catalog path; used to try the script on a copy.
Errors go to stderr as `error: ...` with a non-zero exit, so Xcode shows them.
"""
import fcntl
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import catalog_io  # noqa: E402

CHUNK = 500


class SyncError(Exception):
    pass


_CONTINUATION = re.compile(r"\\\r?\n")
_TOKEN = re.compile(r"(?:\\ |[^\s])+")


def split_escaped(text):
    """Split make-style text on unescaped whitespace; `\\ ` is a space, `\\`+newline a continuation."""
    text = _CONTINUATION.sub(" ", text)
    return [t.replace("\\ ", " ") for t in _TOKEN.findall(text)]


def read_file_list(path):
    with open(path, encoding="utf-8") as f:
        return [t for t in split_escaped(f.read())]


def read_dependencies(path):
    """Paths in a clang `.d` file; Swift's `.d` files (which start with an output path, not
    `dependencies:`) list only Swift sources and are skipped unread, as they are large."""
    with open(path, encoding="utf-8", errors="replace") as f:
        if not f.read(len("dependencies:")) == "dependencies:":
            return []
        return [t for t in split_escaped(f.read()) if not t.endswith(":")]


def collect(srcroot, object_dir, target, archs=None):
    stringsdata, swift_files, objc_files = [], [], []
    try:
        arch_dirs = sorted(e.path for e in os.scandir(object_dir) if e.is_dir())
    except OSError as e:
        raise SyncError("cannot read OBJECT_FILE_DIR_normal %s: %s" % (object_dir, e))
    if archs:
        missing = [a for a in archs if os.path.join(object_dir, a) not in arch_dirs]
        if missing:
            raise SyncError("ARCHS names %s, but %s has no folder for it" % (", ".join(missing), object_dir))
        arch_dirs = sorted(os.path.join(object_dir, a) for a in archs)
    src_prefix = os.path.join(os.path.realpath(srcroot), "")
    for arch in arch_dirs:
        # Xcode leaves the .stringsdata/.d of a deleted source behind; only a file whose object
        # is still in the link list belongs to the target. Xcode writes the list before compiling.
        link_list = os.path.join(arch, target + ".LinkFileList")
        if not os.path.isfile(link_list):
            raise SyncError("%s not found; cannot tell current compiler outputs from leftovers "
                            "of deleted sources" % link_list)
        objects = set(read_file_list(link_list))
        for e in sorted(os.scandir(arch), key=lambda x: x.name):
            if e.name.endswith((".stringsdata", ".d")) and \
                    os.path.join(arch, os.path.splitext(e.name)[0] + ".o") not in objects:
                continue
            if e.name.endswith(".stringsdata"):
                stringsdata.append(e.path)
            elif e.name == target + ".SwiftFileList":
                swift_files.extend(read_file_list(e.path))
            elif e.name.endswith(".d"):
                for dep in read_dependencies(e.path):
                    if dep.endswith((".m", ".mm")) and (
                            dep.startswith(os.path.join(srcroot, "")) or dep.startswith(src_prefix)):
                        objc_files.append(dep)
    dedupe = lambda items: list(dict.fromkeys(items))
    stringsdata, swift_files, objc_files = dedupe(stringsdata), dedupe(swift_files), dedupe(objc_files)
    if swift_files and not stringsdata:
        raise SyncError("the target has %d Swift file(s) but no compiler .stringsdata survives in "
                        "%s; syncing would mark every Swift key stale" % (len(swift_files), object_dir))
    missing = [p for p in stringsdata + swift_files + objc_files if not os.path.exists(p)]
    if missing:
        raise SyncError("%d collected file(s) do not exist (a missing input would silently "
                        "disable stale marking), first: %s" % (len(missing), missing[0]))
    return stringsdata, swift_files, objc_files


def run(cmd):
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise SyncError("%s failed (%d): %s" % (" ".join(cmd[:3]), res.returncode,
                                                (res.stderr or res.stdout).strip()))


def extract(sources, out_dir, *modes):
    """The .stringsdata `xcstringstool extract` writes for `sources` in the given extraction modes."""
    found = []
    for n, start in enumerate(range(0, len(sources), CHUNK)):
        chunk_dir = os.path.join(out_dir, "extract-%d" % n)
        os.makedirs(chunk_dir)
        run(["xcrun", "xcstringstool", "extract", *modes,
             "-o", chunk_dir] + sources[start:start + CHUNK])
        for dirpath, _, names in os.walk(chunk_dir):
            found.extend(os.path.join(dirpath, x) for x in sorted(names) if x.endswith(".stringsdata"))
    return found


def sync(catalog_path, stringsdata, tmp):
    work = os.path.join(tmp, "sync")
    os.makedirs(work)
    copy = os.path.join(work, "Localizable.xcstrings")  # the table name comes from the file name
    shutil.copy(catalog_path, copy)
    cmd = ["xcrun", "xcstringstool", "sync", copy]
    for p in stringsdata:
        cmd += ["--stringsdata", p]
    run(cmd)
    catalog_io.write_catalog(copy, catalog_io.read_catalog(copy))
    return copy


def same_bytes(a, b):
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


def count_stale(path):
    return sum(1 for v in catalog_io.read_catalog(path).get("strings", {}).values()
               if v.get("extractionState") == "stale")


STAMP_NAME = ".catalog-sync-stamp"


def input_states(inputs):
    """Every input file's path, size and mtime, read once so the stamp describes what was synced."""
    states = []
    for path in sorted(inputs):
        st = os.stat(path)
        states.append("\0%s\0%d\0%d" % (path, st.st_size, st.st_mtime_ns))
    return "".join(states)


def fingerprint(catalog, states):
    """Digest of the Catalog's bytes and the inputs' states from input_states()."""
    h = hashlib.sha256()
    with open(catalog, "rb") as f:
        h.update(f.read())
    h.update(states.encode("utf-8"))
    return h.hexdigest()


def read_stamp(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def main(argv=None):
    started = time.time()
    try:
        env = os.environ
        if env.get("CONFIGURATION", "Debug") != "Debug":
            print("note: Catalog sync skipped in the %s configuration; only Debug builds sync" % env["CONFIGURATION"])
            return 0
        for name in ("SRCROOT", "OBJECT_FILE_DIR_normal", "TARGET_NAME"):
            if not env.get(name):
                raise SyncError("environment variable %s is not set" % name)
        srcroot = env["SRCROOT"]
        catalog = env.get("SYNC_CATALOG_PATH") or os.path.join(srcroot, "DashWallet", "Localizable.xcstrings")
        if not os.path.isfile(catalog):
            print("note: %s not found; Catalog sync skipped" % catalog)
            return 0
        stringsdata, swift_files, objc_files = collect(
            srcroot, env["OBJECT_FILE_DIR_normal"], env["TARGET_NAME"], env.get("ARCHS", "").split())
        # Read before the sync: an input changed while it runs is newer than the stamp and syncs next build.
        states = input_states(stringsdata + swift_files + objc_files)
        stamp = os.path.join(env["OBJECT_FILE_DIR_normal"], STAMP_NAME)
        if read_stamp(stamp) == fingerprint(catalog, states):
            print("Catalog sync: skipped, inputs unchanged since the last sync (%.1fs)" % (time.time() - started))
            return 0
        catalog_dir = os.path.dirname(os.path.abspath(catalog))
        # Two builds of one checkout sync one at a time: the lock is on the Catalog's folder, so
        # it adds no file to the checkout.
        lock = os.open(catalog_dir, os.O_RDONLY)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX)
            with tempfile.TemporaryDirectory(prefix="sync-catalog-") as tmp:
                # The sync works on a snapshot. A change is judged against the snapshot, and the
                # result is published only while the Catalog on disk still holds those bytes, so an
                # edit saved during the build (e.g. a translation in the Xcode editor) is never replaced.
                snapshot = os.path.join(tmp, "snapshot.xcstrings")
                shutil.copyfile(catalog, snapshot)
                legacy = extract(swift_files + objc_files, tmp, "--legacy-localizable-strings")
                synced = sync(snapshot, stringsdata + legacy, tmp)
                changed = not same_bytes(synced, snapshot)
                if changed:
                    if not same_bytes(catalog, snapshot):
                        raise SyncError("%s changed on disk while the sync ran (an edit saved during the "
                                        "build); it was left as saved, build again" % catalog)
                    # Its own staging file in the Catalog's folder: the replace stays atomic.
                    fd, staging = tempfile.mkstemp(prefix=".Localizable.xcstrings.", suffix=".sync",
                                                   dir=catalog_dir)
                    os.close(fd)
                    try:
                        shutil.copyfile(synced, staging)
                        shutil.copymode(catalog, staging)
                        os.replace(staging, catalog)
                    finally:
                        if os.path.exists(staging):
                            os.remove(staging)
                # The stamp records what this sync processed: the published result, or the snapshot
                # when nothing changed (a newer Catalog on disk then differs and syncs next build).
                processed = synced if changed else snapshot
                stale = count_stale(processed)
                done = fingerprint(processed, states)
        finally:
            os.close(lock)
        with open(stamp, "w", encoding="utf-8") as f:
            f.write(done + "\n")
        print("Catalog sync: %d compiler + %d legacy .stringsdata (%d Swift, %d ObjC files), "
              "%d stale, %s, %.1fs" % (len(stringsdata), len(legacy), len(swift_files),
                                       len(objc_files), stale, "updated" if changed else "unchanged",
                                       time.time() - started))
        return 0
    except (SyncError, catalog_io.CatalogIOError, OSError, ValueError) as e:
        print("error: Catalog sync failed: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

"""Read and write a String Catalog deterministically, in the format the Xcode app writes.

The byte layout (key order by localizedStandardCompare, spacing, escaping, no trailing
newline) is produced by catalog_writer.swift, compiled once for the macOS host
into a cache directory outside the repository (override with CATALOG_WRITER_CACHE).
"""
import json
import os
import shutil
import subprocess
import tempfile
import time

import swift_helper

HERE = os.path.dirname(os.path.abspath(__file__))
WRITER_SOURCE = os.path.join(HERE, "catalog_writer.swift")


class CatalogIOError(Exception):
    pass


def _writer_binary():
    try:
        return swift_helper.host_binary(WRITER_SOURCE, "CATALOG_WRITER_CACHE",
                                        "dashwallet-catalog-writer", "catalog_writer-")
    except swift_helper.SwiftHelperError as e:
        raise CatalogIOError(str(e))


def read_catalog(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_bytes(path):
    """The file's bytes, or None when it does not exist."""
    try:
        with open(path, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return None


def publish_text(path, text, expect):
    """Write `text` to `path` through publish_file, over the bytes expect[path] (the caller must have read
    the target too), only while every other file in `expect` ({path: the bytes the caller read, or None
    for a file that did not exist}) still holds them; otherwise raise CatalogIOError."""
    want = expect[path]
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=directory,
                                     prefix="." + os.path.basename(path) + ".", delete=False) as f:
        f.write(text)
    publish_file(path, f.name, want, {p: b for p, b in expect.items() if p != path})


def _changed(path, what):
    return CatalogIOError("%s %s; it was left as it is and the result was not written, run again" % (path, what))


def publish_file(path, staged, want, watched=None):
    """Put the finished file `staged` (in the folder of `path`; always removed) at `path`, only over the
    bytes `want` (None: `path` must not exist) and only while every file in `watched` ({path: bytes})
    still holds the bytes the caller read; otherwise raise CatalogIOError.

    It never replaces bytes it did not verify. The live file is moved aside first and verified there, and
    the result is put in place with link(), which fails when another program (an editor's atomic save)
    created the path again in the meantime: that save stays. Bytes written into the moved-aside file
    after it was verified (by a program holding it open) are kept in a conflict file the error names."""
    directory = os.path.dirname(os.path.abspath(path))
    try:
        for other, held in (watched or {}).items():
            if read_bytes(other) != held:
                raise _changed(other, "changed on disk since it was read, so %s was not written" % path)
        if want is None:
            try:
                os.link(staged, path)
            except FileExistsError:
                raise _changed(path, "was created since it was read as absent")
            return
        shutil.copymode(path, staged)
        fd, aside = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", suffix=".aside", dir=directory)
        os.close(fd)
        try:
            os.rename(path, aside)
        except FileNotFoundError:
            os.remove(aside)
            raise _changed(path, "was removed since it was read")
        if read_bytes(aside) != want:
            _put_back(path, aside)
            raise _changed(path, "changed on disk since it was read")
        try:
            os.link(staged, path)
        except FileExistsError:
            os.remove(aside)  # it holds the verified old bytes; the newer save at `path` stays
            raise _changed(path, "was saved while it was published")
        if read_bytes(aside) != want:
            conflict = _conflict_name(path)
            os.rename(aside, conflict)
            raise CatalogIOError("%s was written while it was published; that write is kept in %s and %s holds "
                                 "the tool's result: merge the two, then run again" % (path, conflict, path))
        os.remove(aside)
    finally:
        if os.path.exists(staged):
            os.remove(staged)


def _put_back(path, aside):
    """Return the moved-aside file to `path`, unless a newer file is there: then keep it as a conflict file."""
    try:
        os.link(aside, path)
    except FileExistsError:
        conflict = _conflict_name(path)
        os.rename(aside, conflict)
        raise CatalogIOError("%s was saved twice while it was published; the newer save stays and the "
                             "earlier one is kept in %s; run again" % (path, conflict))
    os.remove(aside)


def _conflict_name(path):
    return "%s.conflict-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))


def write_catalog(path, catalog):
    """Write `catalog` to `path` atomically; an existing file stays untouched on failure."""
    directory = os.path.dirname(os.path.abspath(path))
    binary = _writer_binary()
    with tempfile.TemporaryDirectory(dir=directory, prefix=".catalog-") as tmp:
        source = os.path.join(tmp, "in.json")
        result = os.path.join(tmp, "out.xcstrings")
        with open(source, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False)
        res = subprocess.run([binary, source, result], capture_output=True, text=True)
        if res.returncode != 0:
            raise CatalogIOError("catalog_writer failed: " + res.stderr.strip())
        os.replace(result, path)

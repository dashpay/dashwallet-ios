"""Read and write a String Catalog deterministically, in the format the Xcode app writes.

The byte layout (key order by localizedStandardCompare, spacing, escaping, no trailing
newline) is produced by catalog_writer.swift, compiled once for the macOS host
into a cache directory outside the repository (override with CATALOG_WRITER_CACHE).
"""
import contextlib
import json
import os
import signal
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

    It never replaces bytes it did not verify. The live file is compared first (a mismatch never moves
    it), then moved aside and verified there, and the result is put in place with link(), which fails
    when another program (an editor's atomic save) created the path again in the meantime: that save
    stays. SIGINT, SIGTERM and SIGHUP are held from the move to the end and delivered after it. Every
    error leaves `path` holding the old bytes, a newer save or the result, with any other bytes in a
    conflict file the error names; when even the old file cannot be put back or kept, the error names the
    moved-aside file that holds it. Bytes written into the moved-aside file through a handle opened
    earlier are kept in a conflict file when they land before the final comparison; a write through such
    a handle after it goes to the unlinked old file. While the moved-aside file is verified the path does
    not exist. A process killed (SIGKILL, a crash) while the file is moved aside leaves it only in the
    moved-aside file; the next publication refuses and names it. A filesystem without hard links is
    refused before anything moves."""
    directory = os.path.dirname(os.path.abspath(path))
    prefix = "." + os.path.basename(path) + "."
    try:
        for other, held in (watched or {}).items():
            if read_bytes(other) != held:
                raise _changed(other, "changed on disk since it was read, so %s was not written" % path)
        for name in sorted(n for n in os.listdir(directory) if n.startswith(prefix) and n.endswith(".aside")):
            leftover = os.path.join(directory, name)
            if os.path.getsize(leftover) == 0:  # an interrupted run made it but moved nothing into it
                os.remove(leftover)
                continue
            raise CatalogIOError("%s was left by an interrupted publication of %s and may hold its only copy; "
                                 "compare it with %s, keep what is needed, delete it, then run again"
                                 % (leftover, path, path))
        if want is None:
            try:
                os.link(staged, path)
            except FileExistsError:
                raise _changed(path, "was created since it was read as absent")
            return
        if read_bytes(path) != want:
            raise _changed(path, "changed on disk since it was read" if os.path.exists(path) else
                           "was removed since it was read")
        try:
            shutil.copymode(path, staged)
        except FileNotFoundError:
            raise _changed(path, "was removed since it was read")
        with _interrupts_held():
            _move_aside_and_link(path, staged, want, prefix, directory)
    finally:
        if os.path.exists(staged):
            os.remove(staged)


@contextlib.contextmanager
def _interrupts_held():
    """Hold SIGINT, SIGTERM and SIGHUP for the block; a signal sent meanwhile is delivered when it ends."""
    held = {signal.SIGINT, signal.SIGTERM, signal.SIGHUP}
    before = signal.pthread_sigmask(signal.SIG_BLOCK, held)
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, before)


def _move_aside_and_link(path, staged, want, prefix, directory):
    probe = staged + ".link"
    try:
        os.link(staged, probe)
    except OSError as e:
        raise CatalogIOError("the folder of %s cannot hold a hard link (%s), which publishing needs to keep a "
                             "save made meanwhile; nothing was written" % (path, e))
    finally:
        if os.path.lexists(probe):
            os.remove(probe)
    fd, aside = tempfile.mkstemp(prefix=prefix, suffix=".aside", dir=directory)
    os.close(fd)
    empty = os.stat(aside).st_ino
    linked = False
    try:
        try:
            os.rename(path, aside)
        except FileNotFoundError:
            raise _changed(path, "was removed since it was read")
        if read_bytes(aside) != want:
            raise _changed(path, "changed on disk since it was read")
        try:
            os.link(staged, path)
        except FileExistsError:
            raise _changed(path, "was saved while it was published")
        linked = True
    except BaseException:
        if not linked:
            if os.stat(aside).st_ino != empty:  # the old file was moved aside
                _put_back(path, aside, want)
            else:
                os.remove(aside)
        raise
    if read_bytes(aside) != want:
        conflict = _keep_as_conflict(path, aside)
        raise CatalogIOError("%s was written while it was published; that write is kept in %s and %s holds "
                             "the tool's result: merge the two, then run again" % (path, conflict, path))
    os.remove(aside)


def _put_back(path, aside, want):
    """Return the moved-aside file to `path`. When a newer file is there, it stays, and the moved-aside file
    is dropped only if it still holds the verified bytes `want`; otherwise it is kept as a conflict file."""
    try:
        os.link(aside, path)
    except FileExistsError:
        if read_bytes(aside) == want:
            os.remove(aside)
            return
        conflict = _keep_as_conflict(path, aside)
        raise CatalogIOError("%s holds a newer file (a save made while it was published, or the result) and "
                             "a write into the old file is kept in %s: merge the two, then run again" % (path, conflict))
    except OSError as e:
        raise CatalogIOError("%s could not be put back (%s); its old bytes are in %s: move that file back to %s"
                             % (path, e, aside, path))
    os.remove(aside)


def _keep_as_conflict(path, aside):
    conflict = _conflict_name(path)
    try:
        os.rename(aside, conflict)
    except OSError as e:
        raise CatalogIOError("a write into %s made while it was published is in %s and could not be renamed (%s); "
                             "merge it into %s, then delete it" % (path, aside, e, path))
    return conflict


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

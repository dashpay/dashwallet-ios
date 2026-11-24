"""Read and write a String Catalog deterministically, in the format the Xcode app writes.

The byte layout (key order by localizedStandardCompare, spacing, escaping, no trailing
newline) is produced by catalog_writer.swift, compiled once for the macOS host
into a cache directory outside the repository (override with CATALOG_WRITER_CACHE).
"""
import json
import os
import subprocess
import tempfile

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
    """Write `text` to `path` atomically, only while every file in `expect` ({path: the bytes the
    caller read, or None for a file that did not exist}) still holds them, so a result derived from
    an older read never replaces a newer save; otherwise raise CatalogIOError and write nothing."""
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=directory,
                                     prefix="." + os.path.basename(path) + ".", delete=False) as f:
        f.write(text)
    try:
        for watched, want in expect.items():
            if read_bytes(watched) != want:
                raise CatalogIOError("%s changed on disk since it was read; %s was not written, run again"
                                     % (watched, path))
        os.replace(f.name, path)
    finally:
        if os.path.exists(f.name):
            os.remove(f.name)


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

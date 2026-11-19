#!/usr/bin/env python3
"""Generate DashWallet/Localizable.xcstrings from the Baseline per-locale lists.

    python3 scripts/localization/generate_catalog.py --rev <rev> --repo <path> --out <file>

Reads DashWallet/<lang>.lproj/Localizable.strings and .stringsdict of every locale
folder with `git show <rev>:<path>` (never the working tree). Exits non-zero naming
file and key on any failure, and writes nothing.
"""
import argparse
import sys

import catalog_io
from baseline_lists import GenerateError, build_catalog


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rev", required=True, help="Baseline revision to read the lists from")
    parser.add_argument("--repo", default=".", help="repository path (default: current directory)")
    parser.add_argument("--out", required=True, help="Catalog file to write")
    args = parser.parse_args(argv)
    try:
        catalog = build_catalog(args.repo, args.rev)
        catalog_io.write_catalog(args.out, catalog)
    except (GenerateError, catalog_io.CatalogIOError) as exc:
        print("generate_catalog: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

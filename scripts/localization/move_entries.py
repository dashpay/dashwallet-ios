"""Move Catalog entries whose lookup key changed and rewrite their format codes (T9, ADR-0003).

API:
  plan_moves(pairs, objc_keys)           -> sorted list of distinct (old, new) key moves
                                            from (baseline_place, current_place) pairs;
                                            raises MoveError naming a key that is also
                                            looked up from Objective-C.
  apply_moves(catalog, moves, current_keys)
                                         -> new catalog dict (input untouched); the old key
                                            is removed unless it is in current_keys;
                                            raises MoveError, writing nothing.
  run_moves(catalog_path, pairs, objc_keys) -> moves; reads, plans, applies, writes the
                                            Catalog (file untouched on error).
  main(argv)                             CLI: --repo --baseline --derived-data --catalog [--dry-run]
"""
import argparse
import copy
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import catalog_io  # noqa: E402
import places  # noqa: E402

# %% and %arg (a plural variation's argument) are not arguments; %#@name@ is a substitution.
CODE = re.compile(
    r"%%|%arg|%(?:(?P<pos>\d+)\$)?(?:(?P<sub>#@[^@]*@)|"
    r"(?P<flags>[-+ 0#']*\d*(?:\.\d+)?)(?P<spec>(?:hh|h|ll|l|q|z|t|j|L)?[diouxXfFeEgGcCsSpaA@]))")


class MoveError(Exception):
    pass


def _positions(text):
    """(match, position) for every argument code of `text`; unindexed codes count in order."""
    out, nxt = [], 1
    for m in CODE.finditer(text):
        if not (m.group("sub") or m.group("spec")):
            continue
        if m.group("pos"):
            out.append((m, int(m.group("pos"))))
        else:
            out.append((m, nxt))
            nxt += 1
    return out


def _derived_specs(key):
    return {pos: m.group("spec") for m, pos in _positions(key) if m.group("spec")}


def _rewrite(text, specs, positional):
    parts, last = [], 0
    for m, pos in _positions(text):
        parts.append(text[last:m.start()])
        spec = m.group("spec")
        if spec and pos in specs:
            spec = specs[pos]
        index = "%d$" % pos if (positional or m.group("pos")) else ""
        parts.append("%" + index + (m.group("sub") or m.group("flags") + spec))
        last = m.end()
    parts.append(text[last:])
    return "".join(parts)


def _walk(node, specs, positional):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "value" and isinstance(v, str):
                node[k] = _rewrite(v, specs, positional)
            elif k == "formatSpecifier" and isinstance(v, str):
                arg = node.get("argNum")
                if arg in specs:
                    node[k] = specs[arg]
            else:
                _walk(v, specs, positional)
    elif isinstance(node, list):
        for v in node:
            _walk(v, specs, positional)


def _moved_entry(entry, new_key, source_language):
    entry = copy.deepcopy(entry)
    specs = _derived_specs(new_key)
    positional = len(_positions(new_key)) > 1
    for locale, loc in entry.get("localizations", {}).items():
        _walk(loc, specs, positional and locale == source_language)
    return entry


def plan_moves(pairs, objc_keys):
    moves = {(b.key, c.key) for b, c in pairs if b.key != c.key}
    for old, _ in sorted(moves):
        if old in objc_keys:
            raise MoveError("key %r is also looked up from Objective-C and must stay literal" % old)
    return sorted(moves)


def _is_sync_placeholder(entry, source):
    locs = entry.get("localizations", {})
    if set(locs) - {source}:
        return False
    unit = locs.get(source, {}).get("stringUnit")
    return not locs or (unit is not None and unit.get("state") == "new" and len(locs[source]) == 1)


def apply_moves(catalog, moves, current_keys):
    result = copy.deepcopy(catalog)
    strings = result["strings"]
    source = catalog.get("sourceLanguage", "en")
    for old, new in moves:
        if old not in catalog["strings"]:
            if new in strings:
                continue  # already moved
            raise MoveError("key %r to move to %r is not in the Catalog" % (old, new))
        entry = _moved_entry(catalog["strings"][old], new, source)
        if new in strings and _is_sync_placeholder(strings[new], source):
            # The build's sync added the derived key as an English-only `new` entry before
            # this move; the moved entry replaces it and takes the comment the code gives.
            if "comment" in strings[new]:
                entry["comment"] = strings[new]["comment"]
            strings[new] = entry
        if new in strings and strings[new] != entry:
            raise MoveError("cannot move %r to %r: %r already exists with different wording" % (old, new, new))
        strings[new] = entry
    for old in {o for o, _ in moves}:
        if old not in current_keys:
            strings.pop(old, None)
    return result


def run_moves(catalog_path, pairs, objc_keys, current_keys=None):
    moves = plan_moves(pairs, objc_keys)
    if current_keys is None:
        current_keys = {c.key for _, c in pairs}
    catalog = catalog_io.read_catalog(catalog_path)
    result = apply_moves(catalog, moves, current_keys)
    if result != catalog:
        catalog_io.write_catalog(catalog_path, result)
    return moves


def _is_objc(place):
    return place.file.endswith((".m", ".mm", ".h"))


def _changed_files(baseline, current, mismatched):
    """Mismatched files where a Baseline key has no current place: a move that cannot be paired.

    Extra current places (texts that were never Catalog keys) are not a problem.
    """
    bad = []
    for file, nb, nc in mismatched:
        bk = {p.key for p in baseline if p.file == file}
        ck = {p.key for p in current if p.file == file}
        if bk - ck:
            bad.append((file, nb, nc))
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--derived-data", required=True)
    ap.add_argument("--baseline-derived-data", required=True)
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    try:
        baseline = places.baseline_places(args.repo, args.baseline, args.baseline_derived_data)
        current = places.current_places(args.repo, args.derived_data)
        pairs, mismatched = places.pair(baseline, current)
        blocking = _changed_files(baseline, current, mismatched)
        if blocking:
            raise MoveError("; ".join("%s: %d Baseline places, %d current places" % m for m in blocking))
        for file, nb, nc in mismatched:
            print("warning: %s: %d Baseline places, %d current places" % (file, nb, nc), file=sys.stderr)
        objc_keys = {p.key for p in current if _is_objc(p)}
        current_keys = {p.key for p in current}
        moves = plan_moves(pairs, objc_keys)
        for old, new in moves:
            print("%s -> %s" % (old, new))
        if not args.dry_run:
            run_moves(args.catalog, pairs, objc_keys, current_keys)
        else:
            apply_moves(catalog_io.read_catalog(args.catalog), moves, current_keys)
    except (MoveError, places.NoStringsdataError, catalog_io.CatalogIOError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

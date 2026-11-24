#!/bin/bash
# Prepare the DerivedData folder build_baseline.sh builds the Baseline into, so that no
# .stringsdata in it is taken for the Baseline's without a finished build of that commit.
#
# Usage: scripts/localization/prepare_baseline_folder.sh <derived data dir> <baseline commit>
#
# A folder is the script's own when it holds the mark .baseline-build-folder (written here, before
# every build) or a baseline-commit record (written by build_baseline.sh after a finished build).
# The decision reads only the folder's contents, never its path:
# - the script's own folder with a record of this commit keeps its build data (an incremental
#   rebuild) and loses both records, so a build that fails now leaves none;
# - the script's own folder of another commit or of a failed build, or an empty folder, is emptied;
# - any other non-empty folder (Xcode's DerivedData, a checkout, the cache root that holds the
#   builds) is left untouched and the script stops with an error.
set -euo pipefail

DERIVED="$1"
BASE="$2"
MARK=".baseline-build-folder"

if [ -d "$DERIVED" ]; then
    recorded="$(cat "$DERIVED/baseline-commit" 2> /dev/null || true)"
    if [ ! -e "$DERIVED/$MARK" ] && [ -z "$recorded" ] && [ -n "$(ls -A "$DERIVED")" ]; then
        echo "error: $DERIVED is not a Baseline build folder (no $MARK, no baseline-commit record) and is" \
             "not empty; pass an empty or new folder, or one build_baseline.sh made" >&2
        exit 1
    fi
    if [ "$recorded" != "$BASE" ]; then
        rm -rf "$DERIVED"
    fi
fi
rm -f "$DERIVED/baseline-commit" "$DERIVED/baseline-root"
mkdir -p "$DERIVED"
: > "$DERIVED/$MARK"

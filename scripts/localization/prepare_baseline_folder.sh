#!/bin/bash
# Prepare the DerivedData folder build_baseline.sh builds the Baseline into, so that no
# .stringsdata in it is taken for the Baseline's without a finished build of that commit.
# It deletes no folder and no build data, whatever the folder is.
#
# Usage: scripts/localization/prepare_baseline_folder.sh <derived data dir> <baseline commit>
#
# - A missing or empty folder is fine.
# - A folder whose baseline-commit record names this commit (a finished build of it) keeps its build
#   data for an incremental rebuild and loses its two records, so a build that fails now leaves none.
# - Any other non-empty folder (another commit's build, a failed build, Xcode's DerivedData, a
#   checkout) is refused with the command that deletes it; the person running the script decides.
set -euo pipefail

DERIVED="$1"
BASE="$2"

if [ -d "$DERIVED" ]; then
    entries="$(ls -A "$DERIVED")"  # a folder that cannot be listed stops the script here (set -e)
    recorded="$(cat "$DERIVED/baseline-commit" 2> /dev/null || true)"
    if [ -n "$entries" ] && [ "$recorded" != "$BASE" ]; then
        echo "error: $DERIVED is not empty and holds no finished build of $BASE" \
             "(record: ${recorded:-none}); delete it (rm -rf \"$DERIVED\") or pass a new folder" >&2
        exit 1
    fi
fi
rm -f "$DERIVED/baseline-commit" "$DERIVED/baseline-root"

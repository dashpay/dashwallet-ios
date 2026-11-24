#!/bin/bash
# Prepare the DerivedData folder build_baseline.sh builds the Baseline into, so that no
# .stringsdata in it is taken for the Baseline's without a finished build of that commit.
#
# Usage: scripts/localization/prepare_baseline_folder.sh <derived data dir> <baseline commit>
#
# - A folder that holds a baseline-commit record of this commit keeps its build data (an
#   incremental rebuild) and loses both records, so a build that fails now leaves none.
# - A folder this script made for another commit (it holds a baseline-commit record), an empty
#   folder, or one under the default cache root ~/Library/Caches/dashwallet-regenerate/ (a failed
#   build of the script's own folder) is emptied.
# - Any other existing folder was not made by the script (Xcode's DerivedData, a checkout): it is
#   left untouched and the script stops with an error.
set -euo pipefail

DERIVED="$1"
BASE="$2"
CACHE_ROOT="$HOME/Library/Caches/dashwallet-regenerate"

if [ -d "$DERIVED" ]; then
    recorded="$(cat "$DERIVED/baseline-commit" 2> /dev/null || true)"
    if [ "$recorded" != "$BASE" ]; then
        case "$(cd "$DERIVED" && pwd -P)/" in
            "$(mkdir -p "$CACHE_ROOT" && cd "$CACHE_ROOT" && pwd -P)"/*) ours=yes ;;
            *) ours=no ;;
        esac
        if [ -z "$recorded" ] && [ "$ours" = no ] && [ -n "$(ls -A "$DERIVED")" ]; then
            echo "error: $DERIVED is not a Baseline build folder (no baseline-commit record) and is not empty;" \
                 "pass an empty or new folder, or one build_baseline.sh made" >&2
            exit 1
        fi
        rm -rf "$DERIVED"
    fi
fi
rm -f "$DERIVED/baseline-commit" "$DERIVED/baseline-root"

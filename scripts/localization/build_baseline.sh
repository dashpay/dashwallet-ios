#!/bin/bash
# Build the dashpay target at the Baseline commit so the compiler lists the lookup keys
# the Baseline code used, SwiftUI interpolations included (a lightweight extraction cannot
# derive their keys). The zero-loss check reads the result through --baseline-derived-data.
#
# The Baseline is checked out as a temporary git worktree next to this checkout, so the
# project's ../platform package path resolves the same way; Pods and the gitignored
# *-Info.plist files are cloned from this checkout. The worktree is removed afterwards.
#
# Usage: scripts/localization/build_baseline.sh [<baseline rev>] [<derived data dir>]
#   default baseline: the merge-base of HEAD and origin/develop
#   default derived data: ~/Library/Caches/dashwallet-regenerate/baseline-<sha12>
# Prints the derived data directory on the last line.
set -euo pipefail

top="$(git rev-parse --show-toplevel)"
cd "$top"
BASE="$(git rev-parse --verify "${1:-$(git merge-base HEAD origin/develop)}^{commit}")"
DERIVED="${2:-$HOME/Library/Caches/dashwallet-regenerate/baseline-${BASE:0:12}}"
# xcodebuild runs inside the temporary worktree, so a relative folder is taken from the checkout root.
case "$DERIVED" in /*) ;; *) DERIVED="$top/$DERIVED" ;; esac
WT="$(dirname "$top")/.baseline-${BASE:0:12}"
LOG="$(dirname "$DERIVED")/baseline-${BASE:0:12}-build.log"
mkdir -p "$(dirname "$DERIVED")"
# The records vouch only for a finished build of $BASE; any other non-empty folder is refused, never deleted.
"$top/scripts/localization/prepare_baseline_folder.sh" "$DERIVED" "$BASE"

cleanup() { git worktree remove --force "$WT" > /dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
git worktree add --detach "$WT" "$BASE" > /dev/null
cp -cR Pods "$WT/Pods" 2> /dev/null || cp -R Pods "$WT/Pods"
# The cloned Pods were installed for this checkout's Podfile.lock; the Baseline's may
# differ only in the CocoaPods version line, which would fail the Manifest.lock check.
cp Pods/Manifest.lock "$WT/Podfile.lock"
for plist in DashWallet/*-Info.plist; do
    [ -e "$WT/$plist" ] || cp "$plist" "$WT/$plist"
done

echo "== build dashpay at $BASE (log: $LOG)" >&2
(cd "$WT" && xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' ARCHS=arm64 SWIFT_EMIT_LOC_STRINGS=YES \
    -derivedDataPath "$DERIVED" build) > "$LOG" 2>&1 \
    || { echo "error: the Baseline build failed; see $LOG" >&2; exit 1; }
# Record what was built so the check can tell this build is the Baseline's and map its sources.
echo "$BASE" > "$DERIVED/baseline-commit"
echo "$WT" > "$DERIVED/baseline-root"
echo "$DERIVED"

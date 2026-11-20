#!/bin/bash
# Rebuild the generated state of the String Catalog move on the current merge-base
# (ADR-0069 "How the pull request is built", steps 2-4; removed after the merge, T20):
#   1. generate DashWallet/Localizable.xcstrings from the Baseline lists
#   2. point the project at the Catalog and delete the 86 lists
#   3. rewrite Swift lookups with the codemod (keys looked up from Objective-C stay literal)
#   4. build dashpay, move the entries whose key changed, build again
# Step 0 builds the Baseline commit (build_baseline.sh) for the entry mover's pairing.
# Stops at the first error. Leftovers of the codemod are written to
# $REGEN_OUT/codemod-leftovers.txt for the hand fixes (T13).
#
# Usage: scripts/localization/regenerate.sh [<baseline rev>]
#   default baseline: the merge-base of HEAD and origin/develop
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
L=scripts/localization
BASE="$(git rev-parse --verify "${1:-$(git merge-base HEAD origin/develop)}^{commit}")"
DERIVED="${REGEN_DERIVED_DATA:-$HOME/Library/Caches/dashwallet-regenerate/DerivedData}"
OUT="${REGEN_OUT:-$HOME/Library/Caches/dashwallet-regenerate}"
mkdir -p "$OUT"

build() {
    echo "== build dashpay ($1)"
    xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' ARCHS=arm64 \
        -derivedDataPath "$DERIVED" build > "$OUT/build-$1.log" 2>&1 \
        || { echo "error: build $1 failed; see $OUT/build-$1.log" >&2; exit 1; }
}

echo "== baseline $BASE"
echo "== 0. build the Baseline"
BASE_DERIVED="$("$L/build_baseline.sh" "$BASE" | tail -1)"
echo "== 1. generate the Catalog"
python3 "$L/generate_catalog.py" --rev "$BASE" --repo . --out DashWallet/Localizable.xcstrings

echo "== 2. reference the Catalog, delete the lists"
python3 "$L/catalog_project.py" DashWallet.xcodeproj/project.pbxproj
find DashWallet -path '*.lproj/*' \( -name Localizable.strings -o -name Localizable.stringsdict \) -delete

echo "== 3. codemod"
objc_dir="$(mktemp -d)"
trap 'rm -rf "$objc_dir"' EXIT
find DashWallet \( -name '*.m' -o -name '*.mm' -o -name '*.h' \) -print0 \
    | xargs -0 xcrun xcstringstool extract --legacy-localizable-strings -o "$objc_dir" > /dev/null
python3 - "$objc_dir" > "$OUT/objc-keys.txt" <<'PY'
import glob, json, sys
keys = {e["key"] for f in glob.glob(sys.argv[1] + "/*.stringsdata")
        for t, es in json.load(open(f))["tables"].items() if t == "Localizable" for e in es}
print("\n".join(sorted(keys)))
PY
# Baseline keys that would derive the same interpolation key as another Baseline key
# (e.g. "%d used" and "%ld used" -> "%lld used") cannot both move; they stay literal.
git show "$BASE:DashWallet/en.lproj/Localizable.strings" | plutil -convert json -o "$OUT/baseline-en.json" -
git show "$BASE:DashWallet/en.lproj/Localizable.stringsdict" > "$OUT/baseline-en.stringsdict"
python3 - "$OUT/baseline-en.json" "$OUT/baseline-en.stringsdict" >> "$OUT/objc-keys.txt" <<'PY'
import collections, json, plistlib, re, sys
keys = set(json.load(open(sys.argv[1]))) | set(plistlib.load(open(sys.argv[2], "rb")))
def derived(k):
    k = re.sub(r"%(\d+)\$", "%", k)
    k = re.sub(r"%(?:l{0,2}|h|q|z|j|t)[di]", "%lld", k)
    return re.sub(r"%(?:l{0,2}|h|q|z)u", "%llu", k)
groups = collections.defaultdict(list)
for k in keys:
    groups[derived(k)].append(k)
print("\n".join(sorted(k for g in groups.values() if len(g) > 1 for k in g)))
PY
swift run -c release --package-path "$L/codemod" codemod \
    --keep-literal-keys "$OUT/objc-keys.txt" DashWallet DashWalletTests > "$OUT/codemod-leftovers.txt"
echo "   $(wc -l < "$OUT/codemod-leftovers.txt" | tr -d ' ') leftovers -> $OUT/codemod-leftovers.txt"

echo "== 4. build, move, build"
build 1
python3 "$L/move_entries.py" --repo . --baseline "$BASE" --baseline-derived-data "$BASE_DERIVED" \
    --derived-data "$DERIVED" \
    --catalog DashWallet/Localizable.xcstrings
build 2
echo "== done; derived data: $DERIVED; Baseline derived data: $BASE_DERIVED"

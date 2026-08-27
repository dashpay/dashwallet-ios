#!/usr/bin/env bash
#
#  Normalises the main-app localization catalogs to UTF-8 without a BOM after
#  pulling from Transifex, which sometimes returns UTF-16 or BOM-prefixed files.
#
#  Scope is deliberate and must stay narrow: ONLY DashWallet/*.lproj catalogs.
#    - WatchApp/*.lproj/Interface.strings are UTF-16LE by design (40 of 43
#      locales). Converting them here would silently change their encoding.
#    - A bare `find . -name '*.strings'` also descends into Pods/, rewriting
#      third-party resources.
#  See the "Localization file encoding" section of CLAUDE.md.
#
#  Idempotent: files already UTF-8 without a BOM are left byte-identical.
#
#  Usage: run from anywhere: ./scripts/convert_strings_to_utf8.sh

set -euo pipefail
cd "$(dirname "$0")/.."

shopt -s nullglob
converted=0
checked=0

strip_utf8_bom() {
  perl -i -pe 's/^\x{ef}\x{bb}\x{bf}// if $. == 1' "$1"
}

for f in DashWallet/*.lproj/Localizable.strings DashWallet/*.lproj/Localizable.stringsdict; do
  checked=$((checked + 1))
  case "$(head -c 3 "$f" | xxd -p)" in
    fffe*)
      tmp="$(mktemp)"
      iconv -f UTF-16LE -t UTF-8 "$f" >"$tmp"
      strip_utf8_bom "$tmp"
      mv "$tmp" "$f"
      echo "UTF-16LE -> UTF-8: $f"
      converted=$((converted + 1))
      ;;
    feff*)
      tmp="$(mktemp)"
      iconv -f UTF-16BE -t UTF-8 "$f" >"$tmp"
      strip_utf8_bom "$tmp"
      mv "$tmp" "$f"
      echo "UTF-16BE -> UTF-8: $f"
      converted=$((converted + 1))
      ;;
    efbbbf)
      strip_utf8_bom "$f"
      echo "stripped UTF-8 BOM: $f"
      converted=$((converted + 1))
      ;;
  esac
done

echo "checked $checked main-app catalog(s), normalised $converted."
echo "WatchApp/*.lproj/Interface.strings left alone on purpose (UTF-16LE by design)."

#!/usr/bin/env bash
#
#  Checks the main app's String Catalog, DashWallet/Localizable.xcstrings, which
#  must be UTF-8 JSON without a BOM: strips a UTF-8 BOM, refuses UTF-16.
#
#  Scope is deliberate and must stay narrow: ONLY the main app's Catalog.
#    - WatchApp/*.lproj/Interface.strings are UTF-16LE by design (40 of 43
#      locales). Converting them here would silently change their encoding.
#    - A bare `find . -name '*.strings'` also descends into Pods/, rewriting
#      third-party resources.
#  See the "Localization" section of AGENTS.md.
#
#  Idempotent: a Catalog already UTF-8 without a BOM is left byte-identical.
#
#  Usage: run from anywhere: ./scripts/convert_strings_to_utf8.sh

set -euo pipefail
cd "$(dirname "$0")/.."

catalog=DashWallet/Localizable.xcstrings

if [ ! -f "$catalog" ]; then
  echo "error: $catalog not found" >&2
  exit 1
fi

case "$(head -c 3 "$catalog" | xxd -p)" in
  fffe* | feff*)
    echo "error: $catalog is UTF-16; the String Catalog must be UTF-8 JSON. Restore it from git." >&2
    exit 1
    ;;
  efbbbf)
    perl -i -pe 's/^\x{ef}\x{bb}\x{bf}// if $. == 1' "$catalog"
    echo "stripped UTF-8 BOM: $catalog"
    ;;
esac

echo "$catalog: UTF-8 without BOM."
echo "WatchApp/*.lproj/Interface.strings left alone on purpose (UTF-16LE by design)."

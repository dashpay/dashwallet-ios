#!/usr/bin/env bash
#
# Writes placeholder copies of the gitignored *-Info.plist files the `dashpay`
# target lists as build inputs, so a checkout without the real secrets can
# still build and launch the app as a unit-test host.
#
# Never overwrites a file that already exists, so running it on a developer
# checkout with real plists is a no-op. Values are syntactically valid but
# inert: the Firebase app id has the shape FIRApp validates and the storage
# bucket is the (public, source-hardcoded) one ExploreDatabaseSyncManager
# references — FIRStorage throws at launch when the plist names a different
# bucket; the Coinbase and ZenLedger entries are plain strings because the app
# force-casts them, and the rest are empty dictionaries because their readers
# tolerate missing keys.
#
# Usage: scripts/ci/make-placeholder-plists.sh   (any working directory)

set -euo pipefail

cd "$(dirname "$0")/../.."
target_dir="DashWallet"
written=()

write_plist() {
    local name="$1" body="$2" path="$target_dir/$1"
    if [[ -e "$path" ]]; then
        echo "keep    $path (already present)"
        return
    fi
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0">' "$body" '</plist>' > "$path"
    written+=("$path")
    echo "wrote   $path (placeholder)"
}

write_plist GoogleService-Info.plist '<dict>
	<key>API_KEY</key>
	<string>placeholder-api-key</string>
	<key>BUNDLE_ID</key>
	<string>org.dashfoundation.dash</string>
	<key>GCM_SENDER_ID</key>
	<string>000000000000</string>
	<key>GOOGLE_APP_ID</key>
	<string>1:000000000000:ios:0000000000000000</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<false/>
	<key>IS_GCM_ENABLED</key>
	<false/>
	<key>IS_SIGNIN_ENABLED</key>
	<false/>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>PROJECT_ID</key>
	<string>dash-wallet-firebase</string>
	<key>STORAGE_BUCKET</key>
	<string>dash-wallet-firebase.appspot.com</string>
</dict>'

write_plist Coinbase-Info.plist '<dict>
	<key>CLIENT_ID</key>
	<string>placeholder</string>
	<key>CLIENT_SECRET</key>
	<string>placeholder</string>
</dict>'

write_plist ZenLedger-Info.plist '<dict>
	<key>CLIENT_ID</key>
	<string>placeholder</string>
	<key>CLIENT_SECRET</key>
	<string>placeholder</string>
</dict>'

write_plist Topper-Info.plist '<dict/>'
write_plist SwapKit-Info.plist '<dict/>'
write_plist Uphold-Info.plist '<dict/>'

if (( ${#written[@]} )); then
    plutil -lint "${written[@]}"
fi

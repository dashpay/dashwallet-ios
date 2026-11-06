#!/bin/bash
# Run the real preference and persistence implementation without an iOS host.
# Requires `pod install`; no SDK, keychain access or network requests are used.
set -euo pipefail
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -framework Foundation -include Foundation/Foundation.h \
  -DDASHPAY=1 -I scripts/advanced_mode_regression -I DashWallet/Sources/Models \
  -I Pods/DSDynamicOptions \
  Pods/DSDynamicOptions/DSDynamicOptions/DSDynamicOptions.m \
  DashWallet/Sources/Models/DWGlobalOptions.m \
  scripts/advanced_mode_regression/main.m -o "$test_dir/advanced-mode-tests"
"$test_dir/advanced-mode-tests"

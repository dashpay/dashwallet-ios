#!/bin/bash
# C7 auth goldens — compiles the PURE parts of the auth stack (PinCodec +
# LockoutPolicy in PinStore.swift) with swiftc and checks them against the
# byte fixtures frozen from a live DashSync keychain (goldens.txt) plus a
# table of the lockout formula. The keychain I/O half is covered by the
# DEBUG launch parity check + the C7.8 upgrade-in-place smoke.
set -euo pipefail
cd "$(dirname "$0")"

SRC="../../DashWallet/Sources/Infrastructure/Authentication/PinStore.swift"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

swiftc -o "$TMP/goldens" "$SRC" main.swift
"$TMP/goldens"

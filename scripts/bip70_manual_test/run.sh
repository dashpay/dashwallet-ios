#!/usr/bin/env bash
#
# Manual test for the app-side BIP70 protocol core (L1 codec + L2 verifier).
# Compiles the real source files from DashWallet/Sources/Models/PaymentProtocol/ together
# with main.swift (which carries an embedded, real signed-request fixture) and runs the
# assertions. No simulator, no Xcode test target, no network required.
#
# Usage:  scripts/bip70_manual_test/run.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
SRC="$ROOT/DashWallet/Sources/Models/PaymentProtocol"
OUT="$(mktemp -d)/bip70_manual_test"

swiftc \
  "$SRC/Codec/PaymentProtocolWireFormat.swift" \
  "$SRC/Codec/PaymentProtocolMessages.swift" \
  "$SRC/PaymentRequestVerifier.swift" \
  "$SRC/PaymentProtocolTransport.swift" \
  "$SRC/BIP70Error.swift" \
  "$SRC/ScriptAddressCodec.swift" \
  "$SRC/BIP70PaymentService.swift" \
  "$SRC/BIP70URI.swift" \
  "$DIR/main.swift" \
  -o "$OUT"

exec "$OUT"

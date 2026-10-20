# Reference wallet

Fixture ID: `testnet-restore-mixed`. Fixture data version: `1`.
Status: **READY** for `wallet-restore-sync v2` (2026-10-20).
First restore and relaunch: **PASSED** under v2 criteria.

This dedicated testnet wallet contains ordinary and shielded funds. Keep it
unchanged between restore runs. Running the test does not authorize funding or
new transactions. If additional activity or a testnet reset is observed, prepare
a new fixture data version separately; do not silently change expected values.

## Secret and simulator setup

The recovery phrase is stored locally in macOS Keychain, service
`org.dash.wallet.qa`, account `testnet-restore-mixed-v1`. These are public lookup
identifiers, not credentials. Other operators need this test wallet's phrase
provisioned securely outside Git before running the scenario.

Use operator-assisted import by default. The first restore used explicitly
authorized native Keychain copy/paste without emitting the phrase in tool output,
files, logs or screenshots, then replaced the clipboard with the public service
identifier. Never put the phrase in chat, command arguments, environment
variables, reports or this repository.

Use the fixed simulator PIN `1111` per [README.md](README.md). Enter it automatically
for existing-PIN authentication; new-PIN setup follows the tool's handoff policy.
Explicitly select testnet before import and on relaunch. The first run used
`-CURRENT_CHAIN_TYPE_KEY 1` and verified the `TESTNET` UI label.

## Expected balances and recoverable facts

Values are exact integers: 1 tDash = 100,000,000 duffs; 1 duff = 1,000 credits.
Rounded UI values alone do not establish equality.

| Field | Expected |
| --- | --- |
| Core total / confirmed unlocked | 69,786,469 duffs (0.69786469 tDash) |
| Core unconfirmed | 0 duffs |
| Shielded unspent notes | 29,822,232,000 credits (0.29822232 tDash) |
| Historical spent shielded note | 40,048,712,000 credits, excluded from balance |
| Account scope | Core BIP44 account 0; shielded account 0 |
| Scan start | Before first fixture activity; first fresh restore used birth height 0 |
| Last known Core transaction height | 1576055; persisted sync must cover it |
| Shielded scan coverage | Exclusive index at least 4983; SDK persists aligned_start + total_notes_scanned |
| Other balances | No additional nonzero category observed; no identity or username created |

Core receive/self-transfer address: `yebQWeLYDnjhjBwQfRe6FFE22GGpAR1aRH`.
Core withdrawal destination, selected by the app in the same wallet:
`yaahottcPc9Bs7P53o6CpZRWkgwsaRBiey`.

| Operation | Core transaction ID | Required restored facts |
| --- | --- | --- |
| Faucet receive | `b49ef78b6f378816d1f20eccce0c38bfff367ac012fe2e53a6507bf6ac934740` | +100,000,000 duffs, confirmed; observed height 1575931 |
| Core self-transfer | `759428909557fafd3ee8d8996885639222ce4cd6c2904ac45e2f936a2eb6b4c4` | 10,000,000-duff principal stays in wallet; net -226 duffs, confirmed; observed height 1575932 |
| Shielding asset lock | `9e873498aeb189d63942322fb69710a9aa14f288cc54d26547663567314b2d41` | Lock 40,212,852 duffs; wallet net -40,213,115 duffs; confirmed; note position 4980 with 40,048,712,000 credits, now spent |
| Partial withdrawal | `ca576477f4fb58c19fa565cbdee8a7be6b233c8e4e108b1c880ff96b5bb856ad` | +9,999,810 Core duffs, confirmed; observed height 1576055; unspent change note position 4982 with 29,822,232,000 credits |

Heights and commitment indexes support sync coverage. Block hashes, historical
chain continuity proofs, and independent explorer/RPC queries are not pass criteria.

Shielded restoration need not retain original dates, fee labels, row grouping
or operation classification. The first restore showed a residual “Shielded Spend”
of 0.69870944 tDash with unknown date: a sum of recovered notes, not a net
withdrawal amount. Restored note height fields reflected scan response height
636598 instead of creation heights 636563/636564. Check the known Core operations
and note positions, values and spent flags above; do not require those UI labels
or original Platform dates. Immediate spendability/cooldown is outside this test.

## Preparation and reconciliation

The wallet received 1 tDash and made a 0.1 tDash Core self-transfer (fee 226 duffs).
The initial shielding attempt created the asset lock (Core fee 263 duffs) but
used an SDK transition rejected by protocol 14. Updating to the build below and
resuming that existing lock succeeded; no duplicate funding or asset lock was made.

At 12:17:17 UTC on 2026-10-20, the SDK reported:
40,212,852,000 locked credits − 164,140,000 pool-fee credits =
40,048,712,000 shielded credits. At 12:19:09 UTC, a withdrawal of
10,000,000,000 credits with a 226,480,000-credit Platform fee left
29,822,232,000 shielded credits.

The Core withdrawal delivered 9,999,810 duffs. Its 190-duff difference from the
requested 10,000,000 duffs is recorded separately; independent attribution of that
difference is unavailable. Faucet-paid fee is also unavailable. Neither is
substituted with a guessed fee. The confirmed final Core balance reconciles as:
100,000,000 − 226 − 263 − 40,212,852 + 9,999,810 = 69,786,469 duffs.
Evidence comes from preparation SDK receipts/logs and selected persisted records.

To prepare a replacement fixture, create a dedicated testnet wallet, store its
phrase securely, fund it, perform the ordinary send, shield part, and withdraw
part to the same wallet. Wait for confirmations and record actual amounts,
fees, transaction IDs, final balances and sync coverage. Perform a fresh restore
and relaunch, then review and version the fixture. Preserve positive Core and
shielded balances. Do not repeat these preparation operations in routine tests.

## First successful restore metadata

Run: `20261020-v14-restore-run1`, 2026-10-20; operator: Bartosz; agent: Codex.
Fixture data v1. The existing execution was reassessed as **passed** under scenario
v2 at the operator's request. Its earlier v1 `inconclusive` verdict concerned only
the now-removed historical block-anchor requirement. No execution was repeated,
no expected balances were changed, and no additional spending was performed.

Both source checkouts were clean. The original working combination is:

| Component | Source / artifact |
| --- | --- |
| iOS app | [dashpay/dashwallet-ios, 7465095d2a0a0bef0888394d271a563502580951](https://github.com/dashpay/dashwallet-ios/commit/7465095d2a0a0bef0888394d271a563502580951) |
| Actual Platform / SwiftDashSDK | [dashpay/platform, d959e62c5591bae3a107956bffdd7b00e5fab819](https://github.com/dashpay/platform/commit/d959e62c5591bae3a107956bffdd7b00e5fab819); runtime 5.0.0-rc.5 |
| App platform pin | `5b41ca376b310a1792ddd9f3106e1224f9c275b6`; actual sibling checkout above selected explicitly; pin not edited |
| Package location | `../platform/packages/swift-sdk` relative to the tested app checkout |
| rust-dashcore | [dashpay/rust-dashcore, f22f7d6bd9f0cdd9f4cd6831b57b38610b9f0fdf](https://github.com/dashpay/rust-dashcore/commit/f22f7d6bd9f0cdd9f4cd6831b57b38610b9f0fdf); no patch/path override |
| Cargo.lock SHA-256 | `e3f04226fc5694e07c8d80007a663a4d4feffec6f6965a124f430b0eab4390c7` |
| Framework binary | `DashSDKFFI.xcframework/ios-arm64-simulator/librs_unified_sdk_ffi.a` |
| Framework SHA-256 | `0e42c28eae721e7ee1cb4d86eeea381717cee472d60500fa349b56880857eaed` |
| Framework build | From actual Platform source, `SKIP_EXAMPLE_APP_BUILD=1 CARGO_BUILD_JOBS=6 bash build_ios.sh --target sim --profile release`; previous QA Cargo target cache reused through CARGO_TARGET_DIR |
| App build | `xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath <run>/DerivedData -jobs 6 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` |
| App bundle / binary SHA-256 | `org.dashfoundation.dash` / `0e9a177e263b6ab53233683d97904301b99a50b746e5ce46fe2851e39d67aa0d` |
| Environment | arm64 Mac, macOS 26.6.2; Xcode 26.6 (17F113); Rust 1.98.1; CocoaPods 1.15.2; iPhone 17 / iOS 26.5 simulator; exact Mac model and agent/tool versions unavailable |

All twelve Cargo.lock crates resolved to the rust-dashcore revision above:
`dash-network`, `dash-network-seeds`, `dash-spv`, `dashcore`, `dashcore-private`,
`dashcore-rpc`, `dashcore-rpc-json`, `dashcore_hashes`, `git-state`, `key-wallet`,
`key-wallet-ffi`, and `key-wallet-manager`.

The fresh simulator's wallet ID matched preparation. Core reported `syncDone`
with durable coverage at 12:54:43.403 UTC; shielded sync recovered both notes and
completed at 12:54:44.820, about 53 seconds after import. Relaunch retained both
exact balances, all four Core transactions and both note states; Core and
shielded sync completed again. Timings are informational, not thresholds.

Full reports, selected evidence and detailed local paths remain under ignored
`qa-results/`. Only these non-secret fixture facts and compact provenance belong
in Git. Preserve this first successful build record when testing other revisions.

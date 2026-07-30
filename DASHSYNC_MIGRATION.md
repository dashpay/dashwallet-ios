# DashSync -> SwiftDashSDK migration status

Current-state ledger for the DashSync removal. Updated 2026-07-30 from the
working tree; historical stage-by-stage detail is available in Git history.

This file answers **what is migrated**. Use
[`DASHSYNC_TEARDOWN_PLAN.md`](./DASHSYNC_TEARDOWN_PLAN.md) for unlink
verification and [`DASHSYNC_KEY_MIGRATION.md`](./DASHSYNC_KEY_MIGRATION.md)
for the upgrade-time mnemonic handoff.

## Current state

The application is unlinked from DashSync. Neither app target declares the
pod, the Xcode project has no DashSync framework, bundle, header-path, linker,
or build-script reference, and app source has no direct DashSync import.

Wallet creation/recovery, active-wallet selection, SPV, balances, receive,
transaction list/detail, sends, fees, BIP70, authentication, profiles,
contacts, Coinbase, Uphold, CrowdNode signing, logging, and wipe are owned by
the app and SwiftDashSDK. The legacy `DWEnvironment`, DashSync wallet-registry
dual writes, startup bootstrap, Core Data wipe arm, and internal
`DSBlockchainIdentity` registration path are removed.

Apple Watch remains a supported target. Its phone bridge now builds payloads
from the active SwiftDashSDK wallet snapshot while preserving the existing
`NSCoding` keys, transaction-type raw values, amount/date formatting, recent
transaction limit, and latest-transaction notification contract. No DashSync
wallet or transaction object crosses that bridge.

`DSDynamicOptions` is an independently retained direct dependency; its `DS`
prefix does not make it part of DashSync. Historical `DS*` names may remain in
comments and the frozen keychain-migration specification, but there are no
live `DSChain`, `DSWallet`, `DSAccount`, `DSTransaction`,
`DSBlockchainIdentity`, or `DSBlockchainInvitation` consumers.

## Platform pin

The documented release pin remains **`v4.1-dev`** at `7f4aaa2a44`. The sibling
platform checkout observed during the 2026-07-29 audit was instead clean on
**`v4.2-dev`** at `e1fb9115d8`; this unlink does not change SDK/platform
versions. Reconcile the checkout with the release pin and rebuild both device
and simulator XCFramework slices before release:

```bash
cd ../platform/packages/swift-sdk
./build_ios.sh --target ios --target sim
```

A simulator-only rebuild removes the device slice and is not sufficient for
Archive. All app-required SwiftDashSDK surfaces are already upstream; no local
DashSync compatibility adapter is required.

## Functional migration map

| Capability | Status | Current owner |
|---|---|---|
| Address validation and receive | Done | SwiftDashSDK plus app-owned parsing/UI |
| Mnemonic generation, import, validation, backup | Done | SwiftDashSDK host/storage |
| Wallet creation, recovery, selection, removal | Done | `PlatformWalletManager` and `WalletEnvironment` |
| Balance and fee-aware maximum | Done | `SwiftDashSDKWalletState` |
| Transaction list, detail, direction, metadata | Done | SDK SwiftData snapshots and app-owned models |
| Standard send, fees and BIP70 | Done | `WalletSendService` / SDK transaction sender / app BIP70 stack |
| PIN, biometrics and wipe | Done | App-owned authentication/keychain/wiper |
| SPV sync and network switch | Done | SwiftDashSDK runtime and `WalletEnvironment` |
| Provider-key derivation and masternode data | Done | SwiftDashSDK key-wallet/platform APIs |
| DashPay registration and invitation claim | Done | SwiftDashSDK identity registration |
| Profile/avatar read-write | Done | `DWCurrentUserIdentityInfo`, `DWProfileUpdateBridge`, app HTTP client |
| Contacts and pay-to-contact | Done | SwiftDashSDK/SwiftData |
| DPNS lookup and contested-name warning | Done for retained scope | SwiftDashSDK |
| CoinJoin recovery/sweep | Done for retained scope | SwiftDashSDK |
| Reachability, fiat rates and logging | Done | App-owned infrastructure |
| Coinbase and Uphold | Done | App-owned HTTP/storage plus SDK wallet snapshots |
| CrowdNode transaction/signing/APY | Done | App/SwiftDashSDK |
| Apple Watch phone bridge | Done | SwiftDashSDK active-wallet snapshots; legacy wire format retained |

The unreachable outgoing invitation create/send/history/confirmation chain was
removed. Incoming universal/custom links, Home paste/scan, invitation-mode
username creation, optional post-claim contact request, and inviter preview
remain.

## Storage and upgrade compatibility

No DashSync Core Data to SwiftData copy is required:

| Data | Current handling |
|---|---|
| Addresses, history, sync height, masternode cache | Re-derived by SwiftDashSDK/SPV |
| DashPay contacts and profiles | Re-fetched/projected from Platform |
| Transaction metadata, tax categories, gift-card receipts | Existing app-owned SQLite stores |
| Mnemonics | Imported from the frozen read-only keychain contract; see `DASHSYNC_KEY_MIGRATION.md` |
| PIN/auth counters and integration tokens | Existing app-owned byte-compatible keychain access |

The frozen service `org.dashfoundation.dash` remains read-only so an upgraded
installation can import mnemonics and retain rollback recovery. Final unlink
does not authorize deleting those legacy entries.

## Non-blocking release actions

- Temporarily suspend/hide CrowdNode entry points for the migration release,
  then smoke its active-wallet scoping before re-enabling.
- Put the sibling platform checkout on the agreed release pin and rebuild both
  XCFramework slices.
- Install the watchOS simulator runtime matching the selected Xcode SDK, then
  run the full `dashwallet` build and Watch runtime smoke.

These are release checks, not reasons to restore DashSync.

## Verification on this working tree

- CocoaPods 1.15.2 install completed after removing DashSync and its unused
  transitive native/gRPC pods.
- `dashpay` Debug arm64 generic iOS Simulator build succeeds without signing.
- `dashwallet` reaches Xcode's Watch target selection and is blocked before
  source compilation with: “This scheme builds an embedded Apple Watch app.
  watchOS 26.5 must be installed.” The shared phone-side Watch bridge is
  compiled by the green `dashpay` build.
- Unit tests were intentionally not added or run for this final unlink, per
  task scope. Runtime smokes remain mandatory before release.

## Maintenance rule

Keep this document as a present-state ledger. Do not reintroduce live DashSync
fallbacks, fake `DS*` types, or a second wallet/network source of truth.

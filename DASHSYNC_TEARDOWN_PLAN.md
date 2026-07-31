# DashSync pod teardown verification

Audited against the working tree on 2026-07-31. Functional ownership lives in
[`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md); mnemonic upgrade behavior
lives in [`DASHSYNC_KEY_MIGRATION.md`](./DASHSYNC_KEY_MIGRATION.md).

## Implementation status

The dependency teardown is implemented in this working tree:

- `pod 'DashSync'` is removed from both app targets and CocoaPods 1.15.2 has
  regenerated the lockfile/project;
- DashSync and its no-longer-needed native/gRPC transitive pods are absent;
- framework, bundle, commit-hash resource, header path, linker flag, build
  script, bridging-header import, source membership, and project references
  are removed;
- AppDelegate no longer bootstraps DashSync or `DSOptionsManager`;
- `DWEnvironment`, its wallet-registry mirroring, create/recover dual writes,
  chain-wallet observer, and DashSync Core Data wipe arm are removed;
- the DashPay registration compatibility path no longer creates or reads
  `DSBlockchainIdentity`;
- CocoaLumberjack uses its normal `ddLogLevel`; production call sites use the
  app-owned logger;
- direct app dependencies on CocoaLumberjack 3.7.2, `DSDynamicOptions` 0.1.2,
  and `DWAlertController` 0.2.1 remain explicit. `DSDynamicOptions` is a
  separate library, not DashSync.

There are no direct DashSync imports and no functional `DSChain`, `DSWallet`,
`DSAccount`, `DSTransaction`, `DSBlockchainIdentity`, or
`DSBlockchainInvitation` uses. Remaining matches are historical comments or
the frozen upgrade contract and must be reviewed by ownership rather than
counted as a raw `DS[A-Z]` gate.

## Apple Watch resolution

The Watch app was ported, not removed.

`DWPhoneWCSessionManager` now obtains wallet existence, balance/address data,
recent transactions, and latest-transaction notifications from app/SDK-owned
state. `DWAppleWatchSnapshotProvider` maps the active SwiftDashSDK transaction
snapshot into the existing `BRAppleWatchTransactionData`.

Compatibility intentionally preserved:

- `NSCoding` field keys and serialized classes;
- `BRAWTransactionType` raw values;
- sent/received/moved/invalid mapping;
- Dash and fiat amount formatting;
- the legacy non-zero gross amount for ordinary internal moves;
- date formatting;
- newest-first ordering and 100-transaction limit;
- WatchConnectivity request/reply and notification keys.

The deleted `DSWatchTransactionData*` files were DashSync-only phone adapters.
Watch UI targets and resources remain unchanged.

## Upgrade and wipe compatibility

The app-owned key migrator remains the only reader of the frozen DashSync
keychain layout. It never mutates or deletes `org.dashfoundation.dash`.
Create/recover and wipe are SDK-only after migration:

- create/import persists and verifies the SDK mnemonic before exposing a live
  wallet;
- active wallet IDs remain independently scoped by network;
- wipe posts the app-owned `DWWillWipeWalletNotification`, classifies
  network-scoped wallet IDs, and deletes each through a manager bound to its
  own mainnet/testnet SwiftData container;
- success requires an empty global SDK mnemonic inventory; requested PIN,
  active-wallet registry, and app state are cleared only at that commit point;
- lock-screen, recovery, reinstall, Debug Reset, and screenshot replacement
  flows await the same FIFO result barrier before navigation or wallet create.

## Audit gates

Run before release:

```bash
rg -n "pod ['\"]DashSync|libDashSync|DashSync\\.framework|DashSync\\.bundle" \
  Podfile Podfile.lock DashWallet.xcodeproj/project.pbxproj

rg -n --glob '*.{h,m,mm,swift}' \
  '(#import[[:space:]]*[<\"][^\n]*DashSync|@import DashSync|^[[:space:]]*import DashSync)' \
  DashWallet DashPay TodayExtension WatchApp 'WatchApp Extension'

rg -n --glob '*.{h,m,mm,swift}' \
  '\b(DSChain|DSWallet|DSAccount|DSTransaction|DSBlockchainIdentity|DSBlockchainInvitation)\b' \
  DashWallet DashPay TodayExtension WatchApp 'WatchApp Extension'

git diff --check
plutil -lint DashWallet.xcodeproj/project.pbxproj
```

The first two commands must be empty. Classify every result from the third;
historical comments and frozen key-migration constants are allowed, live
objects are not.

Build both targets with the arm64 simulator slice:

```bash
xcodebuild -workspace DashWallet.xcworkspace -scheme dashwallet \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO INDEX_ENABLE_DATA_STORE=NO build

xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  COMPILER_INDEX_STORE_ENABLE=NO INDEX_ENABLE_DATA_STORE=NO build
```

On the current machine `dashpay` succeeds. `dashwallet` is blocked before app
source compilation with: “This scheme builds an embedded Apple Watch app.
watchOS 26.5 must be installed.” Repeat the identical build after installing
that runtime.

## Required runtime smoke

- upgrade one and multiple wallets from the frozen DashSync keychain layout;
- create, import, switch, rename/remove, and switch network without selecting
  another wallet;
- wipe from Settings, lock/reinstall, recovery, and backup paths;
- receive, standard send, BIP70, pay-to-contact, PIN lockout, and biometrics;
- incoming invitation link, Home paste/scan, inviter preview, and optional
  post-claim contact request;
- Coinbase/Uphold session continuity and transaction metadata;
- profile display/edit/avatar upload and retry/cancel;
- paired Watch compatibility with an existing installation: wallet status,
  balance, address/QR, recent sent/received/moved transactions, and latest
  transaction notification;
- local currency, About diagnostics, camera/push handoff, and termination
  alerts.

CrowdNode should be unavailable for the migration release as separately
decided. Before release, also reconcile the platform pin and perform Archive
with both XCFramework slices.

## Completion boundary

Code and dependency unlink are complete in this working tree. Release
acceptance remains open until the matching watchOS runtime build and the
runtime smokes above pass. A failed smoke must be fixed in the app/SDK owner;
do not restore a DashSync fallback.

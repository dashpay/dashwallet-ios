# DashSync pod teardown plan

Current unlink plan, audited against the working tree on 2026-07-11. This file
answers **what still prevents removing `pod 'DashSync'`**. Functional migration
status lives in [`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md).

## Exit criteria

Teardown is complete only when all of the following are true:

- neither app target declares or links DashSync;
- no app source file imports a DashSync header/module;
- no live app path creates or reads `DSChain`, `DSWallet`, `DSAccount`,
  `DSTransaction`, `DSBlockchainIdentity`, or `DSBlockchainInvitation`;
- DashSync bundle, commit-hash resource, build scripts, linker flags, header
  paths, and generated pod references are gone;
- upgrade-time mnemonic and PIN/token compatibility remains readable through
  app-owned code;
- both `dashwallet` and `dashpay` build and the affected upgrade/wipe/send flows
  pass runtime smoke tests.

## Completed migration clusters

The following are no longer teardown blockers: SDK SPV and wallet state,
transaction list/detail, receive, standard sends and fees, BIP70, address and
mnemonic validation, authentication, reachability, the app-owned fiat-rate pipeline, logging, CrowdNode
signing/APY, network identity/switch ownership, xpub export, DashPay registration
and contacts, and CoinJoin recovery/sweep.

The contacts rebuild in PR #787 is complete. Do not describe C10 as “contacts
pending”; the remaining C10 scope is invitations plus legacy identity/profile
compatibility types.

CrowdNode is also not a teardown blocker. Its migrated implementation should be
temporarily suspended/hidden for the migration release, but no CrowdNode path
may be used as a reason to retain DashSync.

## Non-blocking release actions

These actions must be tracked for the migration release but do not participate
in the T1-T5 dependency chain:

- temporarily suspend/hide CrowdNode entry points; do not add a DashSync
  fallback;
- upstream/reconcile every app-required commit from
  `local/tx-decode-plus-v4.1-dev-dashwallet` onto platform `v4.1-dev`;
- switch the sibling `../platform` checkout to `v4.1-dev`, rebuild both device
  and simulator xcframework slices, and pass both app builds before release.

The temporary platform integration branch is acceptable during development,
but it is not an acceptable final migration or release pin.

## Remaining work

### T1. Decide the DashPay invitation/profile tail

**Decision:** delete/compile-gate invitations or port them.

Current coupling includes:

- invitation create, accept, history, preview, and link UI using
  `DSBlockchainInvitation`;
- funding and status logic using `DSWallet`, `DSAccount`, `DSTransaction`, and
  `DSBlockchainIdentity`;
- old current-user profile/edit views retaining `DSBlockchainIdentity`-typed
  properties/categories even when their displayed data comes from
  `DWCurrentUserIdentityInfo`;
- `JoinDashPayViewModel` compatibility reads.

If invitations are kept, replace the whole async boundary and data model; do
not adapt SDK values back into `DSBlockchainInvitation`. If they are removed,
delete the entry points, types, project membership, and mock invitation paths
in the same change.

### T2. Decide the Apple Watch tail

**Decision:** remove or port.

The Watch targets still exist, but the phone app does not embed WatchApp on
this branch. `DWPhoneWCSessionManager` and `DSWatchTransactionDataObject` still
depend on frozen DashSync account/transaction state.

- **Remove:** delete Watch targets, `Sources/AppleWatch`, Podfile watch targets,
  and phone hooks.
- **Port:** create an SDK snapshot provider, preserve the existing NSCoding
  wire format for installed watches, replace the transaction/account reads,
  and deliberately restore the embed phase.

### T3. Cut C6-E and delete `DWEnvironment`

Do this after T1/T2 no longer need DashSync wallet objects.

Remove together:

- create/recover `standardWalletWithSeedPhrase` dual-writes;
- DashSync registry mirroring during network switch;
- DashSync Core Data/registry wipe arm;
- `DSChainWalletsDidChangeNotification` filtering;
- the DashSync half of `WalletEnvironment.hasWallet`;
- eager `DWEnvironment` bootstrap in AppDelegate;
- `DWEnvironment.{h,m}` and bridging-header exposure.

Multi-wallet warning: every operation must resolve the active wallet for the
selected network through `WalletEnvironment.activeWalletId`. Never select the
first mnemonic/wallet when more than one exists.

### T4. Replace non-wallet DashSync exports

These are active repo tasks, not externally assigned work:

| Surface | Current evidence | Required replacement |
|---|---|---|
| Uphold/profile HTTP | `HTTPLoaderManager`, `HTTPLoaderFactory`, `DSNetworkingCoordinator` | App-owned URLSession/Moya boundary preserving bearer and OTP behavior. |
| Generic keychain helpers | `getKeychainData`, `setKeychainData`, `getKeychainInt` in Coinbase, Uphold, global options | App-owned compatibility shim preserving service/account/accessibility bytes. |
| App-internal notifications | `DSWillRequestOSPermissionNotification`, `DSApplicationTerminationRequestNotification`, residual transaction notification names | App-owned typed notification names; migrate posters and observers together. |
| About/build metadata | `DashSyncCurrentCommit`, `scripts/dashsync_version.sh` | Remove resource/script and show app/platform information only. |
| Local currency DTO | `DSCurrencyPriceObject` | App-owned value/ObjC DTO returned by `CurrencyExchanger`. |
| Confirm Username fiat amount | Direct `DSPriceManager.localCurrencyStringForDashAmount` call in `DWConfirmUsernameContentView` | Route through `CurrencyExchanger_Objc` / the app-owned exchanger. |
| Localization/utilities | `DSLocalizedString`, `UIWindow+DSUtils`, umbrella-only constants such as `DUFFS` | Foundation/app helpers and app-owned constants. |
| Logger compatibility | `dwLogLevel` workaround | Revert to normal CocoaLumberjack `ddLogLevel` after DashSync headers disappear. |
| App startup | `setupDashSyncOnce`, `DSOptionsManager` | Delete once every required service has an app/SDK owner. |
| Transitive pods | `DSDynamicOptions`, `DWAlertController`, CocoaLumberjack | Keep required libraries directly declared before removing DashSync. `DSDynamicOptions` is already direct for TodayExtension; verify both app targets. |

### T5. Unlink mechanics

After T1-T4:

1. Remove `pod 'DashSync'` from both app targets.
2. Run CocoaPods 1.15.2 install.
3. Remove `libDashSync`, `DashSync.framework`, header paths, linker flags,
   `DashSync.bundle`, `DashSyncCurrentCommit`, and stale project references.
4. Remove DashSync-only bridging-header and prefix-header imports.
5. Run the audit gates and build both schemes.

## Sequence

```text
T1 invitation/profile decision + implementation ----+
                                                    +--> T3 C6-E / DWEnvironment
T2 Watch decision + implementation -----------------+             |
                                                                  +--> T5 unlink
T4 non-wallet export replacements -------------------------------+
```

T4 can run independently before the two product decisions. T3 must wait until
both remaining consumers of `DWEnvironment` have a final shape.

The non-blocking CrowdNode suspension and platform-upstream work can run in
parallel with T1-T4. They do not change the order of the DashSync unlink.

## Audit gates

Run before calling teardown complete:

```bash
rg -n "pod ['\"]DashSync|DashSync" Podfile Podfile.lock DashWallet.xcodeproj/project.pbxproj

rg -n --glob '*.{h,m,mm,swift}' \
  '(#import[[:space:]]*[<\"][^\n]*DashSync|@import DashSync|^[[:space:]]*import DashSync)' \
  DashWallet DashPay TodayExtension WatchApp 'WatchApp Extension'

rg -n --glob '*.{h,m,mm,swift}' \
  '\b(DSChain|DSWallet|DSAccount|DSTransaction|DSBlockchainIdentity|DSBlockchainInvitation)\b' \
  DashWallet DashPay TodayExtension WatchApp 'WatchApp Extension'

plutil -lint DashWallet.xcodeproj/project.pbxproj
```

Do not use a raw `DS[A-Z]` count as the completion gate; it includes app-owned
compatibility names and comments. Review each remaining match by ownership.

Build both targets with the arm64 simulator slice:

```bash
xcodebuild -workspace DashWallet.xcworkspace -scheme dashwallet \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES build

xcodebuild -workspace DashWallet.xcworkspace -scheme dashpay \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES build
```

## Required runtime checks

- upgrade from a DashSync-keychain wallet, including multiple wallets;
- create, import, switch, rename/remove, and network switch with the correct
  active wallet;
- wipe from Settings, lock screen, and recovery/backup paths;
- receive, standard send, BIP70, and pay-to-contact;
- PIN lockout and biometric spending limit;
- invitation flow if retained;
- Watch payload compatibility if retained;
- Uphold/Coinbase sessions survive the keychain-helper replacement;
- local-currency picker and About diagnostics after unlink.

Before the final release build, also verify that CrowdNode is unavailable as
intended and that `../platform` is on `v4.1-dev` rather than the temporary local
integration branch.

## Maintenance rule

Keep only present-state inventory and sequencing in this file. When a tail is
closed, remove it from the remaining-work section and update the matching row in
`DASHSYNC_MIGRATION.md` in the same change. Ownership or staffing notes do not
belong in the technical plan.

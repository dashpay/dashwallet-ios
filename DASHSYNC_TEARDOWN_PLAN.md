# DashSync pod teardown plan

Current unlink plan, audited against the working tree on 2026-07-29. This file
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

The local-currency Objective-C boundary is app-owned, including the currency
picker DTO and Confirm Username fiat formatter.

About now reports app/network information without a DashSync commit resource
or CocoaPods generation hook.

Permission and termination notifications are app-owned. Receive-address
refresh no longer observes the dead DashSync transaction-manager notification.

Dash amount and maximum-supply constants are app-owned in both Swift and
Objective-C; amount formatting and security defaults no longer import them
through DashSync.

Lockout localization/duration formatting, top-controller lookup, and the secure
mnemonic allocator are app-owned. Root navigation and wallet recovery no longer
carry incidental DashSync umbrella imports.

Generic keychain access is app-owned and byte-compatible for authentication,
Coinbase, Uphold, and global security flags. Existing service/account names and
per-item accessibility classes are adopted in place with no token migration.

Uphold's reachable OAuth, cards, address, withdrawal, commit, and revoke
requests use the app-owned Moya/`HTTPClient` stack. The Objective-C client
remains only as a UI/model compatibility facade; unreachable account, legacy
buy, and cancel endpoint chains were removed.

The contacts rebuild in PR #787 is complete. The invitation/profile tail is
also closed: the unreachable outgoing invitation chain and dead legacy profile
containers were deleted; active incoming claims and profile UI are app/SDK-owned.

`DWUploadAvatarModel` keeps its public Objective-C/KVO contract and automatic
start, but delegates Imgur delete/upload to an internal Moya/`HTTPClient`
client. It preserves resize/JPEG settings, delete retries, delete-before-upload,
manual retry, response parsing, main-thread mutation, and cancellation/late-
completion gates without importing DashSync HTTP types.

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

### T1. DashPay invitation/profile tail — complete

- Removed outgoing history/create/send/confirmation/legacy-preview UI,
  `DWInvitationLinkBuilder`, dead menu/badge/preferences hooks, DS identity
  categories, old current-profile/QR containers, and their exclusive project
  membership/resources.
- Retained the reachable claim graph unchanged: AppDelegate universal/custom
  links → root deferred state → `ClaimInvitationScreen` → Create Username
  invitation mode → SDK registration → optional contact request. Home paste and
  scan entry points plus `DWInvitationSetupState` remain.
- Home/profile/edit reads now use `DWCurrentUserIdentityInfo`; save always uses
  `DWProfileUpdateBridge`. No `DSBlockchainInvitation` wrapper was introduced.

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

Do this after the Watch tail and `DWDashPayModel`'s internal legacy
registration compatibility path no longer need DashSync wallet objects. T1 no
longer consumes them.

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
| Logger compatibility | `dwLogLevel` workaround | Revert to normal CocoaLumberjack `ddLogLevel` after DashSync headers disappear. |
| App startup | `setupDashSyncOnce`, `DSOptionsManager` | Delete once every required service has an app/SDK owner. |
| Transitive pods | `DSDynamicOptions`, `DWAlertController`, CocoaLumberjack | Keep required libraries directly declared before removing DashSync. `DSDynamicOptions` is already direct for TodayExtension; verify both app targets. |

### T5. Unlink mechanics

After T1-T4:

1. Remove `pod 'DashSync'` from both app targets.
2. Run CocoaPods 1.15.2 install.
3. Remove `libDashSync`, `DashSync.framework`, header paths, linker flags,
   `DashSync.bundle`, and stale project references.
4. Remove DashSync-only bridging-header and prefix-header imports.
5. Run the audit gates and build both schemes.

## Sequence

```text
T1 invitation/profile implementation [complete] ----+
                                                    +--> T3 C6-E / DWEnvironment
T2 Watch decision + implementation -----------------+             |
                                                                  +--> T5 unlink
T4 non-wallet export replacements -------------------------------+
```

The remaining T4 work can run independently before the Watch decision. T3 must
wait until the Watch bridge and legacy registration consumer of `DWEnvironment`
have a final shape.

### Direct DashSync import classification after T1

| Source | Classification |
|---|---|
| `DashWallet/AppDelegate.m` | C6-E/startup teardown: umbrella import for DashSync bootstrap. |
| `DashWallet/Sources/Models/DWEnvironment.h` | C6-E wallet-registry compatibility owner. |
| `DashWallet/Sources/Models/Transactions/DSAccount+SpentInputCheck.{h,m}` | Dormant DSAccount category, exposed only by the bridging header; remove with the remaining compatibility cleanup. |
| `DashWallet/Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m` | Stale, unused `DSTransactionInput` import; no live DS transaction read in the processor. |
| `DashWallet/Sources/AppleWatch/DSWatchTransactionDataObject.h` | Apple Watch tail, deliberately untouched/out of scope. |

These are six source files. The only functional `DSBlockchainIdentity` matches
outside comments are internal to `DWDashPayModel`'s legacy registration path;
there are no functional `DSBlockchainInvitation` matches.

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
- incoming invitation claim from link, Home paste/scan, inviter preview, and
  optional post-claim contact request;
- Watch payload compatibility if retained;
- Uphold/Coinbase sessions survive the keychain-helper replacement;
- local-currency picker and About diagnostics after unlink.
- camera/push permission handoff and app-termination alerts.
- amount formatting, biometric defaults, and DashPay registration thresholds.

Before the final release build, also verify that CrowdNode is unavailable as
intended and that `../platform` is on `v4.1-dev` rather than the temporary local
integration branch.

## Maintenance rule

Keep only present-state inventory and sequencing in this file. When a tail is
closed, remove it from the remaining-work section and update the matching row in
`DASHSYNC_MIGRATION.md` in the same change. Ownership or staffing notes do not
belong in the technical plan.

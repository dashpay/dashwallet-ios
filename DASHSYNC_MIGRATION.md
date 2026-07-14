# DashSync -> SwiftDashSDK migration status

Current-state ledger for the DashSync removal. Updated 2026-07-11 from the
working tree on `swift-sdk-integration`; historical stage-by-stage detail is
available in Git history.

This file answers **what is migrated**. Use
[`DASHSYNC_TEARDOWN_PLAN.md`](./DASHSYNC_TEARDOWN_PLAN.md) for the remaining
unlink sequence and [`DASHSYNC_KEY_MIGRATION.md`](./DASHSYNC_KEY_MIGRATION.md)
for the upgrade-time mnemonic handoff.

## Current state

The user-facing wallet core is SwiftDashSDK-native: SPV, balances, receive,
transaction list/detail, standard sends, fees, BIP70, authentication, wallet
creation/recovery, contacts, the fiat-rate pipeline, logging, CrowdNode signing, network
selection, and xpub export no longer depend on live DashSync wallet state.

DashSync is still linked for four bounded tails:

1. **DashPay invitations and legacy current-user profile types** — contacts are
   migrated, but invitations still use `DSBlockchainInvitation`, `DSWallet`,
   `DSAccount`, `DSTransaction`, and `DSBlockchainIdentity`. A few old profile
   views retain `DSBlockchainIdentity`-typed compatibility properties even
   where their data now comes from `DWCurrentUserIdentityInfo`.
2. **Apple Watch phone bridge** — the targets and bridge remain; transaction
   payload formatting still reads `DSAccount`/`DSTransaction`. The watch app is
   not embedded by either app target on this branch.
3. **C6-E wallet-registry teardown** — create/recover still dual-write a
   `DSWallet`; wipe clears both stores; `WalletEnvironment.hasWallet` includes
   the DashSync registry; `DSChainWalletsDidChangeNotification` is still
   observed; `DWEnvironment` mirrors the active SDK wallet when switching
   networks.
4. **Pod-unlink mechanics and compatibility surfaces** — Uphold networking,
   DashSync keychain helpers used outside wallet migration, app-internal
   `DS*` notifications, `DashSyncCurrentCommit`, `DSCurrencyPriceObject`,
   one residual `DSPriceManager` formatter on the Confirm Username screen,
   `DSLocalizedString`/`DSUtils`, AppDelegate setup, and project/Podfile link entries.

As of this audit, 29 app source files directly import DashSync. Counts of all
`DS*` tokens are not a useful progress metric because app-owned names such as
`DSTransactionDirection`, comments, and frozen compatibility contracts are
included.

## Platform pin

The app builds against sibling `../platform` on **`v4.1-dev`** (verified
2026-07-15: dashpay arm64-sim build green at app tip `62a7eb40c` against
`origin/v4.1-dev` tip `88949b7144`; the seedless-shielded-bind API drift —
`shieldedWithdraw`/`shieldedUnshield` gaining a per-operation
`resolver:` — is adapted in `ShieldedTransferCoordinator`). Every app-required surface is upstream:
tx decoding (`TransactionDecoder`, key-wallet-ffi route), DashPay fee threading,
`RawKeySigner` (#4097), the testnet faucet client (#4098), classified SPV peers,
and the filter-rescan FFI (#4099). The `local/tx-decode-plus-v4.1-dev-dashwallet`
integration branch is retired.

No open nuances: the verified tip `0bfdc5745c` IS the merge of
[platform #4049](https://github.com/dashpay/platform/pull/4049), so
`send_payment` returns the exact fee (Σinputs − Σoutputs via
dashpay/rust-dashcore#872) and the faucet captcha's aggregate
proof-of-work cap ([#4100](https://github.com/dashpay/platform/pull/4100))
is included as well.

After changing the platform checkout, rebuild both xcframework slices from
`../platform/packages/swift-sdk`:

```bash
./build_ios.sh --target ios --target sim
```

The script recreates the xcframework from the requested targets; a simulator-
only rebuild removes the device slice and breaks Archive.

## Functional migration map

Status meanings:

- **Done** — production call sites use the final non-DashSync implementation.
- **Done; teardown tail** — the capability is SDK-native, but compatibility
  plumbing remains until the pod unlink.
- **Decision required** — final shape depends on a product/owner decision.

| # | Capability | Current status | Remaining work |
|---|---|---|---|
| 1 | Receive address | Done | None. Reads the active SDK wallet/account. |
| 2 | Address validation | Done | None. Uses SwiftDashSDK address validation through app-owned parsing helpers. |
| 3 | Mnemonic generation / create wallet | Done; teardown tail | Remove the adjacent `DSWallet standardWalletWithSeedPhrase` dual-write in C6-E. |
| 4 | Mnemonic validation | Done | None. Uses `Mnemonic.validate`. |
| 5 | Wallet balance | Done | None. Uses `SwiftDashSDKWalletState`. |
| 6 | Transaction list | Done | None. Uses SDK-persisted SwiftData rows. |
| 7 | Transaction detail | Done | None. Uses SDK snapshots and recent-send resolution. |
| 8 | Send Dash | Done | None. Money movement goes through `WalletSendService` / `SwiftDashSDKTransactionSender`. |
| 9 | Fee estimation | Done | None. Confirmation uses the transaction builder's fee. |
| 10 | PIN / biometrics | Done; teardown tail | Remove incidental DashSync imports/constants and retain the byte-compatible app-owned keychain contract. |
| 11 | SPV sync | Done; teardown tail | Remove `setupDashSyncOnce` / `DSOptionsManager` and remaining legacy notification names at unlink. |
| 12 | Network switch | Done; teardown tail | Remove the temporary DashSync wallet-registry mirror with C6-E. |
| 13 | Backup seed phrase | Done | Reads the active SDK wallet mnemonic from host-owned storage. |
| 14 | Wipe wallet | Done; teardown tail | Remove the DashSync registry/Core Data wipe arm after all consumers are gone. |
| 15 | Provider-key derivation | Done for retained scope | Owner/Voting are SDK-native; Operator/HPMN and legacy “used at” UI were intentionally dropped because the required public-key/list lookup surfaces are unavailable. |
| 16 | DashPay identity creation | Done; invitation tail | Standard SDK-funded identity/name registration is migrated. Invitation-funded create/accept remains part of the invitation decision. |
| 17 | DashPay identity/profile read-write | Done; compatibility tail | Retire remaining `DSBlockchainIdentity`-typed profile properties/categories and route every old view directly through `DWCurrentUserIdentityInfo` / `DWProfileUpdateBridge`. |
| 18 | DashPay contacts and pay-to-contact | Done | PR #787 rebuilt contacts on SwiftDashSDK/SwiftData/SwiftUI and removed the old contacts subsystem. Invitations were explicitly out of scope. |
| 18a | Contested DPNS-name detection | Done for retained scope | Warning/bookmark behavior is SDK-native; richer resolution/status UX remains optional product work, not a DashSync blocker. |
| 19 | DPNS lookup | Done | Availability and contact search use SDK APIs. |
| 20 | CoinJoin | Done for retained scope | Mixing was dropped; recovery/sweep is SDK-native. Only stale imports/comments should be removed during unlink. |
| 21 | Reachability | Done | Replaced with `NWPathMonitor`; this is app-owned, not a SwiftDashSDK API. |
| 22 | BIP70 | Done | App-owned protocol stack performs build/sign -> Payment/ACK -> broadcast. Keep `BIP70_TESTING.md` as the focused verification record. |

## Non-blocking product action: CrowdNode

CrowdNode should be temporarily suspended/hidden for the migration release.
Its wallet balance, transaction, signing, and APY work is already app/SDK-owned,
so CrowdNode does **not** justify keeping DashSync linked and must not block the
pod teardown. Suspension is a product/release action, not a dependency of the
T1-T5 unlink sequence.

When CrowdNode is re-enabled, verify its account state, deposit/withdrawal,
message signing, and active-wallet scoping against the final `v4.1-dev` SDK
build. Do not reintroduce a DashSync fallback while it is suspended.

## Storage migration

No DashSync Core Data -> SwiftData copy is required:

| Data | Current handling |
|---|---|
| Addresses, transaction history, sync height, masternode cache | Re-derived by SwiftDashSDK/SPV. |
| DashPay contacts and profiles | Re-fetched/projected from Platform into SwiftData. |
| Transaction metadata, tax categories, gift-card receipts | Already app-owned SQLite data; independent of DashSync. |
| Mnemonics | Imported from the frozen DashSync keychain contract; see `DASHSYNC_KEY_MIGRATION.md`. |
| PIN/auth counters and integration tokens | Preserved through app-owned byte-compatible keychain access; final generic helper replacement is an unlink task. |

## Decisions blocking teardown

- **Invitations:** delete/compile-gate the feature now, or port create/accept/link
  behavior using the available lower-level SDK/FFI primitives.
- **Apple Watch:** remove the non-embedded legacy targets/phone bridge, or port
  and deliberately restore shipping.
- **CrowdNode:** temporarily suspend it for the migration release; this decision
  is recorded but does not block DashSync removal.

Contacts are not part of the invitation decision; they are already migrated.

## Verification baseline

The 2026-07-11 audit verified:

- clean Git worktree before documentation edits;
- `plutil -lint DashWallet.xcodeproj/project.pbxproj` passes;
- `dashpay` Debug, generic arm64 iOS Simulator build succeeds;
- the local platform checkout matches the pin above.

Feature-specific runtime smokes are still required when a remaining tail is
changed. Build success alone is not evidence that a migration flow is correct.

## Maintenance rule

Update this ledger in the same change that alters a status or a teardown tail.
Record only current behavior and remaining work here; commit-by-commit session
diaries belong in Git history. Verify claims against the working tree before
editing a status.

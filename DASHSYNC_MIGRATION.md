# DashSync -> SwiftDashSDK migration status

Current-state ledger for the DashSync removal. Updated 2026-07-28 from the
working tree; historical stage-by-stage detail is available in Git history.

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
4. **Pod-unlink mechanics and compatibility surfaces** — profile-avatar
   networking, AppDelegate setup, and project/Podfile link entries. Coinbase
   and Uphold keychain access and the reachable Uphold HTTP flows are app-owned.

As of this audit, 12 app source files directly import DashSync. Counts of all
`DS*` tokens are not a useful progress metric because app-owned names such as
`DSTransactionDirection`, comments, and frozen compatibility contracts are
included.

## Platform pin

The app consumes sibling `../platform` on **`v4.1-dev`** (verified 2026-07-21
at `origin/v4.1-dev` tip `7f4aaa2a44`: both XCFramework slices and the SDK
example app build green, and the dashpay arm64-sim build is green. The
dashwallet build and focused tests remain blocked before compilation by the
local watchOS runtime mismatch, `23S303` vs SDK `23T570`). The branch's earlier
breaking change — platform
#4140 removing `EstablishedContact`'s clone-mutating setters, which never
wrote real state — requires app tip ≥ #834, where contact alias/note/hidden
write through `setDashPayContactInfo` instead. Earlier drift notes (the
seedless-shielded-bind `resolver:` parameter, the #4093 managed-identity-
top-up removal) remain adapted as before). Every app-required surface is
upstream: tx decoding (`TransactionDecoder`, key-wallet-ffi route), DashPay
fee threading, `RawKeySigner` (#4097), the testnet faucet client (#4098),
classified SPV peers, the filter-rescan FFI (#4099), and the
partial-amount platform address withdrawal wrapper (#4139). The
`local/tx-decode-plus-v4.1-dev-dashwallet` integration branch and the
`v4.1-dev-local` sidecar are retired.

No open nuances: the verified tip includes
[platform #4049](https://github.com/dashpay/platform/pull/4049) (merged as
`0bfdc5745c`), so
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
| 3 | Mnemonic generation / create wallet | Done; teardown tail | SDK-owned mnemonic storage is verified before a wallet becomes live in `PlatformWalletManager`; remove the adjacent `DSWallet standardWalletWithSeedPhrase` dual-write in C6-E. |
| 4 | Mnemonic validation | Done | None. Uses `Mnemonic.validate`. |
| 5 | Wallet balance | Done | None. Uses `SwiftDashSDKWalletState`. |
| 6 | Transaction list | Done | None. Uses SDK-persisted SwiftData rows. |
| 7 | Transaction detail | Done | None. Uses SDK snapshots and recent-send resolution. |
| 8 | Send Dash | Done | None. Money movement goes through `WalletSendService` / `SwiftDashSDKTransactionSender`. |
| 9 | Fee estimation | Done | None. Confirmation uses the transaction builder's fee. |
| 10 | PIN / biometrics | Done; teardown tail | Authentication, lockout copy/duration formatting, and secure mnemonic allocation are app-owned; retain the byte-compatible keychain contract through pod unlink. |
| 11 | SPV sync | Done; teardown tail | Core restart/peer rotation is serialized `stopSpv → startSpv` on the existing manager, preserving Platform sync, wallet state and the process-cached per-network `ModelContainer`; clear-and-resync deletes the chain store off MainActor on the next process launch. Remove `setupDashSyncOnce` / `DSOptionsManager` at unlink; the chain-wallet notification is removed separately with C6-E. |
| 12 | Network switch | Done; teardown tail | Remove the temporary DashSync wallet-registry mirror with C6-E. |
| 13 | Backup seed phrase | Done | Reads the active SDK wallet mnemonic from host-owned storage. |
| 14 | Wipe wallet | Done; teardown tail | Reinstall recovery and Settings Debug Reset both gate onboarding behind the background wipe executor's explicit success result; per-wallet SDK deletion remains synchronous, and a failed delete preserves mnemonic/runtime state and the in-memory identity snapshot for retry. After a successful wipe the stopped runtime installs an empty identity snapshot and publishes the wallet-context change; a newly started wallet publishes the same event, rebuilding the DashPay tab bar as 3 or 5 items from that wallet's identity state. Remove the DashSync registry/Core Data wipe arm after all consumers are gone. |
| 15 | Provider-key derivation | Done | All four families are SDK-native: Owner/Voting via the key-wallet path surface, Operator (BLS) and Evonode Operator (Ed25519) via `ManagedPlatformWallet.providerKeyAtIndex` (`platform_wallet_provider_key_at_index` grew per-index BLS/EdDSA public-key export, removing the earlier blocker). Overview counts and per-keypair “used at” restored from the Rust masternode aggregation (`PlatformWalletManager.masternodes(for:)`). |
| 16 | DashPay identity creation | Done; invitation tail | Standard SDK-funded identity/name registration is migrated, with three funding paths (Core asset-lock, Platform Payment, shielded Type-20 — the privacy-preserving default, gated by `ShieldedIdentityFundingReadiness`). Every new identity registers the DashPay ENCRYPTION/DECRYPTION pair in IdentityCreate; the lazy IdentityUpdate upgrader remains as a fallback for incomplete identities. Invitation-funded create/accept remains part of the invitation decision. |
| 17 | DashPay identity/profile read-write | Done; compatibility tail | Retire remaining `DSBlockchainIdentity`-typed profile properties/categories and route every old view directly through `DWCurrentUserIdentityInfo` / `DWProfileUpdateBridge`. |
| 18 | DashPay contacts and pay-to-contact | Done | PR #787 rebuilt contacts on SwiftDashSDK/SwiftData/SwiftUI and removed the old contacts subsystem. Recipient eligibility matches the SDK's DECRYPTION-preferred, ENCRYPTION-fallback policy so encryption-only mobile identities remain reachable. Invitations were explicitly out of scope. |
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
| PIN/auth counters and integration tokens | Preserved in place through app-owned, byte-compatible keychain access with the existing service/accounts/accessibility. |

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

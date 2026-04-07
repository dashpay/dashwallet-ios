# DashSync → SwiftDashSDK Migration Map

A function-first inventory of what needs to move from DashSync (Obj-C, CocoaPods) to SwiftDashSDK (Swift, SPM at `../platform/packages/swift-sdk`). Organized by user-facing or internal capability rather than by file, so the same file appears under multiple functions where relevant.

**SDK column legend:**
- 🟢 **Ready** — SwiftDashSDK exposes a working Swift API today
- 🟡 **Partial** — Rust FFI exists, Swift wrapper missing or incomplete
- 🔴 **Blocked** — Not implemented in either layer; requires upstream work
- ⚪ **N/A** — Stays on DashSync forever, or replaceable with iOS SDK primitives

**Status column legend** (where we are in the migration of each function):
- `—` Not started
- `🌓 Shadow` Adapter wired in, both libraries called, DashSync still authoritative (Stage 0)
- `🌗 Flipped` SwiftDashSDK is authoritative, DashSync still called for safety (Stage 1)
- `🌘 Solo` Only SwiftDashSDK is called from the call sites, adapter still exists (Stage 2)
- `✅ Done` Adapter retired, call sites use SwiftDashSDK directly (Stage 3)

**Effort:** S = a few hours, M = a day or two, L = a week, XL = multi-week

**Priority:** based on (a) how user-visible the function is and (b) how much it unblocks other work

## Where we are

| Function | State | What landed |
|---|---|---|
| **#2 Address validation** | 🌘 Solo | Adapter `DWSwiftDashSDKAddressValidator` calls SwiftDashSDK exclusively for all networks (mainnet, testnet, devnet/evonet). Stage history: shadow-shipped in `19b475684`, flipped to `sdkResult`, then DashSync call dropped after we verified that `DashSync NSString+Dash.m:69-82` and `rust-dashcore dash/src/address.rs:1241-1253` use byte-identical logic for every network — both fall back to testnet's version bytes (140/19) for devnet/regtest. The adapter is now ~15 lines, no DashSync touch anywhere. **Next (Stage 3, low priority):** retire the adapter, inline `Address.validate(...)` directly at the 4 call sites in Swift wrappers. Defer until DashSync is being fully removed from the project — the adapter is harmless. |

Everything else in the table below is `—` (not started). The SwiftDashSDK package itself is linked and building (commits `8309e1ef4` for the SPM integration, `19b475684` for the first migration adapter).

---

## Functional migration table

| # | Function | Key files in dashwallet-ios | DashSync API today | SwiftDashSDK target | SDK | Status | Prio | Effort | Storage migration? |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Receive address** (show next external address) | `Sources/UI/Payments/Receive/Models/DWReceiveModel.m` | `DSAccount.receiveAddress` | `Wallet` → `ManagedWallet.getExternalAddressRange` | 🟢 | — | High | S | None — pure derivation. Used-state tracking is the only nuance, see §"Storage". |
| 2 | **Address validation** (paste/scan in Send screen) | `Sources/UI/Payments/PaymentModels/DWPaymentInputBuilder.m`, `DWPaymentProcessor.m` | `[NSString isValidDashAddressOnChain:]` | `Address.validate(_:network:)` via `DWSwiftDashSDKAddressValidator` | 🟢 | 🌘 Solo | High | S | None |
| 3 | **Mnemonic generation** (Create New Wallet) | `Sources/UI/Setup/SeedPhrase/DWNewAccountViewController.m`, `DSWallet`-backed factory | `DSBIP39Mnemonic`, `[DSWallet standardWalletWithSeedPhrase:...]` | `Mnemonic.generate` + `Wallet(mnemonic:)` | 🟢 | — | High | S | First-launch only — new wallets opt into SwiftDashSDK from day one. |
| 4 | **Mnemonic validation** (Restore Wallet) | `Sources/UI/Setup/RecoverWallet/DWRecoverModel.m`, `DWPhraseRepairViewController.m` | `[DSBIP39Mnemonic phraseIsValid:]` | `Mnemonic.validate(_:)` | 🟢 | — | High | S | None |
| 5 | **Wallet balance** (display) | `Sources/Models/BalanceNotifier.swift`, `Sources/UI/Home/Models/HomeViewModel.swift`, `DWBalanceModel.m` | `DSWallet.balance`, KVO via NSNotification | `ManagedWallet.getBalance()` (sync) or async wrapper | 🟢 | — | High | M | Balance is computed from UTXO state — needs SPV-driven UTXO sync (function #11) to be meaningful. Until then, balance display still belongs to DashSync. |
| 6 | **Transaction list** (Home screen tx history) | `Sources/UI/Home/Models/Transactions/DWTransactionListDataProvider.m`, `Sources/UI/Tx/`, `Sources/UI/Home/Models/HomeViewModel.swift` | `DSWallet.allTransactions`, `DSTransaction` properties | SwiftDashSDK `Transaction` model + persistence layer | 🟡 | — | High | L | **Yes** — tx history lives in DashSync's Core Data. SwiftDashSDK's `ManagedTransaction` exists but is empty until populated. Migration utility required. |
| 7 | **Transaction detail** (single tx view) | `Sources/UI/Tx/TxDetail/`, `DSTransaction+DashWallet.m` | `DSTransaction.txHashData`, `DSTransaction.outputs/inputs`, `DSTransactionDirection` | SwiftDashSDK `Transaction` model | 🟡 | — | Medium | M | Same store as #6. |
| 8 | **Send Dash** (build/sign/broadcast tx) | `Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m`, `Sources/UI/Send/SendViewController.swift` | `[account signTransaction:...]`, `[chainManager.transactionManager publishTransaction:]`, BIP70 via `DSPaymentRequest` | `TransactionBuilder.build()` + `SPVClient.broadcast()` | 🔴 | — | High | L | **Blocked upstream**: Rust FFI has `wallet_build_and_sign_transaction()` and `dash_spv_ffi_client_broadcast_transaction()` but Swift wrappers are stubs (`SDKError.notImplemented`). Single biggest unblocker. |
| 9 | **Fee estimation** (UI preview before sending) | `Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m` | `[chain feeForTxSize:]`, `TX_OUTPUT_SIZE` | Bundled inside the FFI build call (#8) | 🟡 | — | Medium | S | Surface a standalone Swift wrapper after #8 lands. |
| 10 | **PIN / biometric auth** (unlock wallet, authorize sends) | `Sources/Application/AppDelegate.m`, anywhere using `DSAuthenticationManager` | `DSAuthenticationManager.authenticateWithPrompt:`, `seedPhraseAfterAuthentication:` | `WalletStorage` (PBKDF2 + Keychain) + `KeychainManager` | 🟢 | — | Medium | M | None — keychain is backward-compatible. UX flow change only. |
| 11 | **SPV chain sync** (block headers, filters, masternodes, ChainLock, InstantSend) | `Sources/Application/AppDelegate.m`, `DWEnvironment.m`, `Sources/UI/Home/Models/HomeViewModel.swift` (sync state) | `DSChainManager`, `DSPeerManager`, `DSSyncState` + NSNotifications | `SPVClient` + `SPVEventHandler` (closure-based) | 🟡 | — | High | L | **Verify before trusting**: feasibility study marks this READY but the Swift surface looked thinner than the FFI when explored. 12 stub event handlers in `WalletService` need wiring. Storage migration needed for header chain + masternode list cache. |
| 12 | **Network switch** (mainnet ↔ testnet) | `Sources/Models/DWEnvironment.m`, `Sources/UI/Menu/Settings/...` | `DSChain.mainnet/.testnet`, `DSChainsManager` | `KeyWalletNetwork` enum passed to `Wallet` / `SPVClient` | 🟢 | — | Medium | S | Per-network data dirs already separated. |
| 13 | **Backup seed phrase** (show 12 words) | `Sources/UI/Backup/DWPreviewSeedPhraseViewController.m`, `DWBackupInfoViewController.m` | `seedPhraseAfterAuthentication`, `DSBIP39Mnemonic` word list | `Mnemonic` (already a `String`) | 🟢 | — | Low | S | None |
| 14 | **Wipe wallet** | `Sources/UI/Settings/ResetWalletModel.swift`, `DWEnvironment` | `[DSWallet wipeBlockchainInfoInContext:]`, `[chainManager wipeBlockchainData...]` | `WalletManager.delete(walletId:)` + clear SwiftData store | 🟢 | — | Medium | M | Must wipe both stores during the dual-stack period. |
| 15 | **Address derivation for Provider keys** (masternode setup) | `Sources/UI/Menu/Tools/Masternode Keys/DerivationPathKeysModel.swift` | `DSAuthenticationKeysDerivationPath` (voting/owner/payout) | `BLSAccount` / `EdDSAAccount` + `KeychainManager` provider key types | 🟢 | — | Low | S | None — derivation only |
| 16 | **DashPay identity create** | `DashPay/Sources/UI/DashPay/.../DWDashPayModel.m`, `DWDPRegistrationStatusViewController.m` | `DSBlockchainIdentity` (creation, registration, topup) | `Identity`, `ManagedIdentity`, `IdentityManager` | 🟡 | — | Medium | M | **Blocked by 6+ FFI signature mismatches** in `dash_sdk_identity_put_to_platform*`. Fix upstream first. |
| 17 | **DashPay identity read** (display profile, username) | 87 files reference `DSBlockchainIdentity` across `DashPay/Sources/UI/DashPay/` | `DSBlockchainIdentity.currentDashpayUsername`, `.matchingDashpayUserInContext:` | `SDK.identities.get(id:)` (currently nil-stub), `Identity` | 🟡 | — | Medium | L | Volume is here — most files are display-only. Most can migrate once #16 unblocks. |
| 18 | **DashPay contacts** (search, request, accept) | `DashPay/Sources/UI/DashPay/Contacts/`, `DWDPContactObject`, `DWDPUserObject` | `DSContact`, `DSBlockchainInvitation` | `EstablishedContact`, `ContactRequest` (currently a stub service) | 🔴 | — | Medium | L | `ObservableDashPayService` is literally a "stub that allows the app to compile". Real service must be implemented. |
| 19 | **DPNS username lookup** | `DashPay/Sources/UI/DashPay/Search/...` | DashSync's identity search | `Addresses.dpns*` operations | 🟢 | — | Low | S | New capability — could ship as additive before retiring DashSync's version. |
| 20 | **CoinJoin / mixing** | `Sources/Models/CoinJoin/CoinJoinService.swift`, `DSCoinJoinManager` consumers | `DSCoinJoinManager`, `DSAccount` mixing flags | _absent_ | 🔴 | — | Low | XL | **Largest single gap.** Mixing protocol absent at the Rust layer too. Recommendation: keep DashSync linked indefinitely just for CoinJoin until upstream ships, OR drop the feature entirely. Do **not** block the rest of the migration on this. |
| 21 | **Reachability** (online/offline indicator) | `Sources/Application/AppDelegate.m`, `DWEnvironment.m` | `DSReachabilityManager` | _absent_ | ⚪ | — | Low | S | Not a real "migration" — replace with `NWPathMonitor` (Apple framework). Trivial. |
| 22 | **BIP70 payment protocol** (merchant pay flow) | `Sources/UI/Payments/PaymentModels/DWPaymentProcessor.m`, `DSPaymentProtocol*` | `DSPaymentProtocol`, `DSPaymentProtocolRequest` | _absent_ | ⚪ | — | Low | — | BIP70 is deprecated industry-wide. **Recommendation: drop, don't migrate.** |

---

## Storage migration

This is a separate concern from per-function code migration, and it cuts across functions #5, #6, #7, #11, #14, #16, #17.

**Current state:** DashSync persists everything in **Core Data** (40+ entities): tx history, masternode list, identity entities, contact requests, address metadata, sync state. SwiftDashSDK persists in **SwiftData** (`@Model` types). The two are not interoperable — different storage frameworks, different schemas, different files on disk.

**What needs migrating:**

| Data | Volume per user | Can we re-derive? | Migration cost |
|---|---|---|---|
| BIP44 addresses (used / unused) | tens to hundreds of rows | Yes — derivation is deterministic; "used" state can be re-discovered via SPV scan from height 0 | None if user can wait for resync |
| Transaction history | tens to thousands of rows | Yes via SPV resync, but **loses any user-added metadata** (categories, memos, custom labels) | One-time importer if metadata matters |
| Masternode list cache | one snapshot | Yes — re-fetch on first launch | None |
| Identity entities + DashPay contacts | rare, identity-bound | Yes via Platform queries (one-time) | One-time importer if user shouldn't re-search contacts |
| Sync state (last block height, etc) | one row | Yes — resync from genesis or last checkpoint | None |
| Address metadata (custom labels, categories) | sparse, user-entered | **No** — purely user data, irreplaceable | Importer required, **or** accept data loss |

**Recommendation:** ship a one-shot Core Data → SwiftData migrator on first launch after the upgrade that copies the irreplaceable user-entered data (tx categories, memos, custom address labels) and lets everything else re-derive via SPV. Lower-cost than a full importer, zero data loss for the things users care about.

The migrator is **single-purpose, throwaway code** — designed to be deleted ~6 months after release once telemetry shows no users still need to upgrade through it.

---

## Hard blockers (do these first or migration is dead in the water)

1. **Send transaction (#8)** — wrap `wallet_build_and_sign_transaction()` and `dash_spv_ffi_client_broadcast_transaction()` in Swift. Lives in `platform` repo, not here.
2. **Identity FFI signature mismatches (#16)** — 6+ functions have parameter type mismatches between Swift wrappers and the C signatures. Lives in `platform` repo.
3. **Core Data → SwiftData migrator** — see "Storage migration" above. Lives here.
4. **DashPay contact service (#18)** — currently a stub. Lives in `platform` repo.

CoinJoin (#20) is **not** a hard blocker because we can keep DashSync linked solely for that path during the transition (or drop the feature). Don't let it stop everything else.

---

## Recommended order

The dependencies suggest a clear layering. Each step is independently shippable; later steps require earlier ones.

| Wave | What | Why first |
|---|---|---|
| **Wave 1** (low risk, high learning) | Functions #1, #2, #3, #4, #13, #15, #19, #21 | All 🟢 ready, all isolated, none touch tx history. Build confidence + adapter pattern. |
| **Wave 2** (Platform side) | Functions #16, #17 (after upstream FFI fixes), #18 (after upstream service), #19 expansion | Isolated to DashPay variant. Doesn't touch payment paths. |
| **Wave 3** (storage groundwork) | Storage migrator (Core Data → SwiftData) | Must be in hand before functions #5–#11 ship to existing users. |
| **Wave 4** (the hard part) | Functions #5, #6, #7, #11 | Requires storage migrator and SPV verification. |
| **Wave 5** (the big one) | Function #8 (send), then #9, #10, #14 | Requires upstream Swift wrappers. After this lands, dashwallet can in principle stop linking DashSync. |
| **Wave 6** (deferred / optional) | Function #20 (CoinJoin) | Either ships when upstream Rust mixing lands, or feature is dropped. Not blocking. |

---

## Notes

- **The two libraries can coexist.** SwiftDashSDK is already linked alongside DashSync in the `dashwallet` target (as of commit `8309e1ef4`). Migration happens function-by-function; both libraries stay linked until Wave 5 completes.
- **`DWEnvironment`** is the singleton that fans out to almost every function above. The cleanest migration shape is to refactor it into a thin facade with two backends (`DashSyncBackend` and `SwiftDashSDKBackend`) selected by feature flag, so individual functions can flip independently without one big-bang cutover.

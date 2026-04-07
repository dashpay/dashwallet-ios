# DashSync → SwiftDashSDK key migration

Status ledger for the multi-PR arc that moves wallet key material from DashSync's keychain layout into SwiftDashSDK's `WalletStorage` + SwiftData. Sibling to [`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md) (function-first map). This doc tracks **data movement**; that doc tracks function migration.

## Hard invariant

**Keys written by DashSync into the iOS Keychain (`org.dashfoundation.dash` service) are NEVER deleted by this codebase.** They are preserved indefinitely as belt-and-suspenders rollback source. The migrator only ever READS from `org.dashfoundation.dash`. All writes and deletes the migrator performs target `org.dash.wallet` (SwiftDashSDK's service) and the SwiftData store.

Even after DashSync the *library* is removed from the app binary, the keychain entries that previous app versions wrote will still exist on user devices and will still be readable by `SwiftDashSDKKeyMigrator.swift` (which doesn't import DashSync). They are intentionally never cleaned up.

## Where we are

| Phase | Status | What landed | Commit |
|---|---|---|---|
| **v1 — Full one-shot import (mnemonic → seed + HDWallet)** | 🚧 In progress (built, awaiting commit) | Migrator file, AppDelegate one-line, two platform-repo patches (`CoreWalletManager` public convenience init + `WalletStorage` public init), tracking doc | — |
| v2 — Wave-1 function adapters consume the migrated wallet | — Not started | — | — |
| v3 — DashSync library removal (keychain entries preserved) | — Not started | — | — |

## Today's frozen contract with DashSync's keychain

The migrator (`DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`) is the **only file in dashwallet-ios** that knows DashSync's keychain layout. The constants below are load-bearing — once v1 ships, they cannot change without a coordinated release.

| What | Service | Account | Format | Source |
|---|---|---|---|---|
| Mnemonic | `org.dashfoundation.dash` | `WALLET_MNEMONIC_KEY_<walletID>` | UTF-8 BIP39 phrase | `DSWallet.m:742` |
| PIN | `org.dashfoundation.dash` | `pin` | UTF-8 digits | `DSAuthenticationManager.m:751` |
| Wallet list per chain | `org.dashfoundation.dash` | `CHAIN_WALLETS_KEY_<chainGenesisShortHex>` | NSKeyedArchiver `NSArray<NSString *>` of wallet IDs | `DSChain.m:579, 1450-1462` |
| Extended public key cache | `org.dashfoundation.dash` | `<pathReference>_<walletID>` | raw NSData (BIP32 ext pub key) | `DSDerivationPath.m:592` |

Wallet ID format: `[NSString stringWithFormat:@"%0llx", uint64_t]` — 16-char hex max, derived from `ecdsa_public_key_unique_id_from_derived_key_data()`.

Chain genesis short-hex format: `[[NSData dataWithUInt256:[chain genesisHash]] shortHexString]` — first 7 hex chars of the byte-reversed UInt256 representation. Pre-computed:

| Network | Displayed genesis hex | shortHex |
|---|---|---|
| Mainnet | `00000ffd590b1485b3caadc19b22e6379c733355108f107a430458cdf3407ab6` | `b67a40f` |
| Testnet | `00000bafbc94add76cb75e2ec92894837288a481e5c005f6563d91623bf8bc2c` | `2cbcf83` |

Keychain access: default app keychain group (`<team-id>.<bundle-id>`), no `kSecAttrAccessGroup` set. No biometric/passcode access control flags — silent reads.

## Phase v1 — scope, design, and "done when"

### Scope

- **In:** mnemonic + PIN → 64-byte BIP39 seed → encrypted in `org.dash.wallet`/`wallet.seed` via `WalletStorage` → SwiftData `HDWallet` record persisted via a fresh `ModelContext` from `ModelContainerHelper.createContainer()`. Wallet bytes captured via `WalletManager.addWalletAndSerialize`. Round-trip verified. Done flag stores `SHA256(pin)` for change detection.
- **Out:** xpub-cache migration (derivable from seed; deferred indefinitely). Removing DashSync call sites. Deleting any DashSync keychain entries (never). Exposing the migrated wallet to other parts of the app (v2).

### Design

The migrator runs once per cold launch from `AppDelegate.m` immediately after the Core Data migration call (line ~138), **before** any DashSync initialization (`setupDashSyncOnce` runs much later at line ~332). This sidesteps the iPhone 17 + iOS 26.3 `[DSChain retrieveWallets]` crash entirely.

The Obj-C entry point `migrateIfNeeded()` is fully synchronous. It runs all of its work inline on the calling thread — fast pre-checks (UserDefaults flag, keychain enumeration, network detection) plus the heavy work (FFI + PBKDF2 + SwiftData). No `Task`, no `@MainActor`, no async dispatch. Total cost ~300–500 ms once per device.

The migrator uses the lowest-level public SwiftDashSDK API surface: standalone `WalletManager(network:)` (which calls `wallet_manager_create` directly with `ownsHandle = true` — no `SPVClient` or `CoreWalletManager`), then `addWalletAndSerialize` to register the wallet and capture its FFI bytes, then `ensurePlatformPaymentAccount` (non-fatal), then `Mnemonic.toSeed` + `WalletStorage().storeSeed(seed, pin:)` to write the encrypted seed, then a round-trip `retrieveSeed(pin:)` byte-compare, then a fresh `ModelContext(modelContainer)` insert+save of the `HDWallet` record. The `WalletManager` and `ModelContainer` locals go out of scope at the end of the function and ARC frees the FFI handle naturally.

### Hard invariants the migrator honors

1. **Never deletes from `org.dashfoundation.dash`.** All DashSync entries are read-only forever.
2. **Never throws or crashes.** `migrateIfNeeded()` returns `Void`, swallows all errors into `os.log` entries.
3. **Never modifies user-visible state.** No UI, no `DWGlobalOptions`, no DashSync state mutation.
4. **Runs before any DashSync init.** Sidesteps the iPhone 17 crash.
5. **No force-unwraps, no `try!`, no `as!`.**

### Skip-and-defer cases

Set per-cause UserDefaults flag and bail; the next launch will re-check.

| Condition | Flag |
|---|---|
| No PIN in DashSync keychain | `swiftSDKKeyMigration.v1.deferredNoPIN` |
| More than one wallet found | `swiftSDKKeyMigration.v1.deferredMultiWallet` (count value) |
| Wallet on devnet/regtest/evonet (unsupported in v1) | `swiftSDKKeyMigration.v1.deferredUnknownChain` |

### Special branches

- **Wipe detection:** If done flag is set but DashSync mnemonics are gone AND our SwiftDashSDK seed lingers, the migrator deletes the SwiftDashSDK seed and clears the flag. Only touches `org.dash.wallet`. Never `org.dashfoundation.dash`.
- **PIN-change re-encrypt:** If done flag is set but `SHA256(currentDashSyncPIN) != doneFlag`, re-derives the seed from the mnemonic and calls `WalletStorage.storeSeed(seed, pin: newPIN)`. Does **not** call `createWallet` again, because `addWalletAndSerialize` is non-idempotent and would create a duplicate FFI wallet. Only the encryption layer rotates.

### Done when

- Both `dashwallet` and `dashpay` targets build clean ✅
- `plutil -lint` on `project.pbxproj` is OK ✅
- Round-trip verification inside the migrator passes (seed re-read byte-equals freshly-derived) — verified by code path; runtime confirmation requires a real device
- Manual smoke test passes on a working device/simulator combo (release blocker, not merge blocker — see Risks)

## Cross-repo dependency: SwiftDashSDK patches

v1 requires two minimal visibility flips in `../platform/packages/swift-sdk/Sources/SwiftDashSDK/Core/Wallet/`:

| File | Change | Why |
|---|---|---|
| `HDWallet.swift` | Add `public` to the existing `init(walletId:serializedWalletBytes:label:network:isWatchOnly:isImported:)` | The migrator constructs `HDWallet` directly to insert into a `ModelContext` without going through `CoreWalletManager.createWallet` (which is `@MainActor` async and would force the migrator into the same isolation domain). The class itself is already `public final class HDWallet`; only the init was internal. |
| `WalletStorage.swift` | Add `public init() {}` | Synthesized inits on `public class` types default to internal. Without an explicit `public init()`, callers outside the module can't construct a `WalletStorage`. |

Both changes are additive and minimal — no behavior change, no breaking change. They must be merged in the platform repo before this dashwallet-ios PR can ship.

**Earlier design — abandoned.** An earlier attempt added `public convenience init(keyWalletNetwork:)` to `CoreWalletManager` that internally constructed an `SPVClient(dataDir: nil)` and chained to the existing internal designated init. That approach had two real problems and was reverted: (a) **use-after-free** — the convenience init dropped its local `SPVClient` at end-of-init, but `WalletManager.init(handle:)` sets `ownsHandle = false` because the handle is owned by the SPVClient; the FFI handle stored in `self.sdkWalletManager` became dangling as soon as the convenience init returned. (b) **`dataDir: nil` semantics were unverified** — every other call site in the SDK passes an explicit Documents-based path; the FFI behavior with no dataDir was unknown and the SPVClient header comment hints at a directory lock that may persist even with nil. The current design bypasses `CoreWalletManager` and `SPVClient` entirely, eliminating both problems.

## Phase v2 (sketch)

Wire up a shared `SwiftDashSDKContainer` singleton (currently the SDK is initialized ephemerally inside the migrator only). Build a `SwiftDashSDKWalletProvider` that returns the migrated `HDWallet` to consumers via `CoreWalletManager.wallets`. Wire the first Wave-1 function adapter (likely #1 receive address per [`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md)) to consume that provider. This gives us our first end-to-end test that the migration actually produced a usable wallet.

## Phase v3 (sketch)

Once Wave 1–4 of `DASHSYNC_MIGRATION.md` are complete and the app no longer needs DashSync at runtime, remove the DashSync CocoaPods dependency. The DashSync keychain entries that previous app versions wrote remain on user devices and remain readable by the migrator. **They are never deleted.**

## Open risks and notes

- **iPhone 17 + iOS 26.3 crash in `[DSChain retrieveWallets]`** is a pre-existing host-app blocker that prevents end-to-end testing of v1 on this dev machine. v1 itself is safe (it runs *before* DashSync init) but we cannot manually verify the post-migrator launch path here. Release blocker: smoke test on a different device or simulator combo before merging.
- **Multi-wallet prevalence is unknown.** v1 ships a "skip if >1 wallet" guard. We need telemetry on the `swiftSDKKeyMigration.v1.deferredMultiWallet` counter to know whether we need a follow-up to handle multi-wallet.
- **Devnet/regtest/evonet not supported in v1.** Network detection only matches mainnet and testnet. Users on other networks see migration deferred via `swiftSDKKeyMigration.v1.deferredUnknownChain`. Follow-up to add devnet support if telemetry shows non-zero incidence.
- **Wallet ID stability across libraries**: DashSync's wallet ID is `%0llx` of a 64-bit hash; SwiftDashSDK's wallet ID is 32 bytes from `wallet_manager_add_wallet_from_mnemonic_return_serialized_bytes`. These are NOT the same value and cannot be cross-referenced. Wave 4 dual-stack code that needs to correlate wallets across libraries will need an explicit mapping table.
- **PIN-hash format mismatch**: DashSync stores PIN as UTF-8 plaintext; SwiftDashSDK stores `SHA256(PIN)` (unsalted, single round). The two cannot validate each other's PIN entries. Future cleanup needs to reconcile.
- **`kSecAttrAccessible` mismatch on PIN**: DashSync's PIN uses `AfterFirstUnlockThisDeviceOnly` (background-readable); SwiftDashSDK's `wallet.pin` uses `WhenUnlockedThisDeviceOnly` (foreground-only). v1 only runs at `didFinishLaunching` so this doesn't bite us, but v2+ background unlock paths must not assume the SwiftDashSDK PIN hash is readable in the background.
- **`ensurePlatformPaymentAccount` failure** is treated as non-fatal — the migrator logs a warning and proceeds. Matches the behavior of `CoreWalletManager.createWallet` (`CoreWalletManager.swift:78-83`). Fine for v1 since we don't use platform features yet.
- **HDWallet record cleanup on wipe-detection is intentionally NOT performed.** The wipe-detection branch only deletes the encrypted seed from `WalletStorage`, not the `HDWallet` SwiftData record, because doing so would require constructing and operating on the SwiftData stack on every cold-launch fast path. The orphaned `HDWallet` record is harmless until v2 has consumers; v2 will discover it via SwiftData on first run and decide whether to delete or rebuild it.

# DashSync → SwiftDashSDK key migration

Status ledger for the wallet key-material migration from DashSync's keychain layout into SwiftDashSDK's `WalletStorage` plus an app-owned runtime wallet descriptor in Keychain. Sibling to [`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md) (function-first map). This doc tracks **data movement**; that doc tracks function migration.

**Deployment model.** All work in this doc lands on the `swift-sdk-integration` dev branch and ships in a single App Store release alongside DashSync's removal — see [`.claude/skills/dashsync-migration/SKILL.md §0`](./.claude/skills/dashsync-migration/SKILL.md). The "milestones" below are review hygiene (small commits, separable diffs), **not** separate ship cycles. The doc therefore intentionally does not design for any dual-stack window, and any branch that would only matter in such a window is dead code.

## Hard invariant

**Keys written by DashSync into the iOS Keychain (`org.dashfoundation.dash` service) are NEVER deleted by this codebase.** They are preserved indefinitely as belt-and-suspenders rollback source. The migrator only ever READS from `org.dashfoundation.dash`. All writes and deletes the migrator performs target `org.dash.wallet` (SwiftDashSDK's service) plus the app-owned runtime-descriptor keychain service.

Even after DashSync the *library* is removed from the app binary, the keychain entries that previous app versions wrote will still exist on user devices and will still be readable by `SwiftDashSDKKeyMigrator.swift` (which doesn't import DashSync). They are intentionally never cleaned up.

## Where we are

| Milestone | Status | Commits |
|---|---|---|
| **Seed migrator** — mnemonic → encrypted seed (`WalletStorage`) + runtime wallet descriptor, run silently at app launch on a background queue | ✅ Landed on `swift-sdk-integration` | `ba477919c` (initial), `a3c24e9d8` (lowest-level API rewrite), `5af09c84f` (background dispatch), `fd7b770ea` (drop PIN-change), this PR (runtime descriptor ownership cleanup) |
| Cross-repo SwiftDashSDK visibility patches | ✅ Landed in platform repo | `223dda6ca`, `b3bb5fcdf` (on `fix/swift-sdk-ios-17-deployment-target`) |
| Wave-1 function adapters consume the migrated wallet (e.g. #1 receive address) | — Not started | — |
| DashSync library removal (keychain entries preserved) | — Not started | — |

The seed migrator is feature-complete on the dev branch. The next milestone is wiring a Wave-1 adapter (or the SPV sync work) to consume the runtime descriptor end-to-end so we get proof that the wallet bytes are usable. Both follow-on milestones still belong to the same App Store release — no intermediate ship.

## Today's frozen contract with DashSync's keychain

The migrator (`DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`) is the **only file in dashwallet-ios** that knows DashSync's keychain layout. The constants below are load-bearing — they describe DashSync entries previous app versions wrote on user devices, and we never delete or rewrite those entries. They cannot change after the migrator ships.

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

## Seed migrator — scope, design, status

### Scope

- **In:** mnemonic + PIN → 64-byte BIP39 seed → encrypted in `org.dash.wallet`/`wallet.seed` via `WalletStorage` → mnemonic stored in `wallet.mnemonic` for backup display → runtime descriptor stored in app-owned Keychain (`wallet.descriptor`). Wallet bytes are captured via `WalletManager.addWalletAndSerialize`. Seed, mnemonic, and descriptor are round-trip verified. Done flag stores a version sentinel (`"v1"`) for idempotency only — no PIN tracking. (`v1` is a UserDefaults key namespace and version tag, not a release phase; the value is frozen and must not change after the migrator ships.)
- **Out:** xpub-cache migration (derivable from seed; deferred indefinitely). Removing DashSync call sites — that's the function-migration work tracked in `DASHSYNC_MIGRATION.md`. Deleting any DashSync keychain entries (never). Exposing the migrated wallet to other parts of the app — that's the Wave-1 adapter milestone in the table above.

### Design

The migrator runs once per cold launch from `AppDelegate.m` immediately after the Core Data migration call (line ~138), **before** any DashSync initialization (`setupDashSyncOnce` runs much later at line ~332). This ordering is for clean handoff — the migrator must own the keychain read window before DashSync touches its own wallet state.

The Obj-C entry point `migrateIfNeeded()` is a thin dispatcher: it immediately schedules the entire migrator body onto `DispatchQueue.global(qos: .userInitiated)` and returns to AppDelegate in microseconds, so launch is **not** blocked by the ~300–500 ms migration cost. The actual work — fast pre-checks (UserDefaults flag, keychain enumeration, network detection) plus the heavy work (FFI + PBKDF2 + keychain writes) — runs in the background while the user is already looking at the home screen. No `Task`, no `@MainActor`, no Swift Concurrency primitives — just a single GCD dispatch. Total background cost ~300–500 ms once per device.

The migrator uses the lowest-level public SwiftDashSDK API surface: standalone `WalletManager(network:)` (which calls `wallet_manager_create` directly with `ownsHandle = true` — no `SPVClient` or `CoreWalletManager`), then `addWalletAndSerialize` to register the wallet and capture its FFI bytes, then `ensurePlatformPaymentAccount` (non-fatal), then `Mnemonic.toSeed` + `WalletStorage().storeSeed(seed, pin:)` to write the encrypted seed, then a round-trip `retrieveSeed(pin:)` byte-compare, then `storeMnemonic`/`retrieveMnemonic` verification, then an app-owned runtime descriptor write/read-back in Keychain. The `WalletManager` local goes out of scope at the end of the function and ARC frees the FFI handle naturally.

### Hard invariants the migrator honors

1. **Never deletes from `org.dashfoundation.dash`.** All DashSync entries are read-only forever.
2. **Never throws or crashes.** `migrateIfNeeded()` returns `Void`, swallows all errors into `os.log` entries.
3. **Never modifies user-visible state.** No UI, no `DWGlobalOptions`, no DashSync state mutation.
4. **Runs before any DashSync init.** Owns the keychain read window before DashSync touches its own wallet state.
5. **No force-unwraps, no `try!`, no `as!`.**

### Skip-and-defer cases

Set per-cause UserDefaults flag and bail; the next launch will re-check.

| Condition | Flag |
|---|---|
| No PIN in DashSync keychain | `swiftSDKKeyMigration.v1.deferredNoPIN` |
| More than one wallet found | `swiftSDKKeyMigration.v1.deferredMultiWallet` (count value) |
| Wallet on devnet/regtest/evonet (currently unsupported) | `swiftSDKKeyMigration.v1.deferredUnknownChain` |

### One-shot, single-release deployment model

The migrator is built for a **one-shot migration in a single App Store release**. There is no intermediate release where v1's migrator ships while DashSync's UI is still authoritative — the migrator, the SDK consumers, and DashSync's removal all land together. As a direct consequence the migrator deliberately does **not** handle any of the cross-library state-drift scenarios that a dual-stack window would create:

- **No wipe-detection branch.** Because DashSync's wipe UI never coexists with a SwiftDashSDK seed in production, the "DashSync mnemonics gone but our seed lingers" state cannot occur organically. The hard invariant (we never delete from `org.dashfoundation.dash` ourselves) closes the only other path.
- **No PIN-change branch.** PIN rotation never happens through DashSync after the migrator runs in production. PIN rotation post-migration is handled by `CoreWalletManager.changeWalletPIN(currentPIN:newPIN:)` (`Core/Wallet/CoreWalletManager.swift:285`).
- **No cross-library wallet ID mapping.** The migrator hands off the wallet once and exits; nothing later needs to correlate a DashSync wallet ID against a SwiftDashSDK one.

Once the done flag is set, the migrator is done forever. The post-migration world is SwiftDashSDK-only.

### Acceptance criteria

- Both `dashwallet` and `dashpay` targets build clean ✅
- `plutil -lint` on `project.pbxproj` is OK ✅
- Round-trip verification inside the migrator passes (seed re-read byte-equals freshly-derived) — verified by code path; runtime confirmation requires a real device.
- Manual smoke test on the iPhone 17 simulator (or a real device) before the App Store release.

## Cross-repo dependency: SwiftDashSDK patches

The seed migrator requires two minimal visibility flips in `../platform/packages/swift-sdk/Sources/SwiftDashSDK/Core/Wallet/`:

| File | Change | Why |
|---|---|---|
| `HDWallet.swift` | Add `public` to the existing `init(walletId:serializedWalletBytes:label:network:isWatchOnly:isImported:)` | The app constructs detached `HDWallet` carriers from the runtime descriptor without going through `CoreWalletManager.createWallet` (which is `@MainActor` async and would force the runtime provider into the same isolation domain). The class itself is already `public final class HDWallet`; only the init was internal. |
| `WalletStorage.swift` | Add `public init() {}` | Synthesized inits on `public class` types default to internal. Without an explicit `public init()`, callers outside the module can't construct a `WalletStorage`. |

Both changes are additive and minimal — no behavior change, no breaking change. They land on `fix/swift-sdk-ios-17-deployment-target` in the platform repo (commits `223dda6ca`, `b3bb5fcdf`) and must merge before the dashwallet-ios PR ships.

**Earlier design — abandoned.** An earlier attempt added `public convenience init(keyWalletNetwork:)` to `CoreWalletManager` that internally constructed an `SPVClient(dataDir: nil)` and chained to the existing internal designated init. Two problems caused it to be reverted: (a) **use-after-free** — the convenience init dropped its local `SPVClient` at end-of-init, but `WalletManager.init(handle:)` sets `ownsHandle = false` because the handle is owned by the SPVClient; the FFI handle stored in `self.sdkWalletManager` became dangling as soon as the convenience init returned. (b) **`dataDir: nil` semantics were unverified.** The current design bypasses `CoreWalletManager` and `SPVClient` entirely, eliminating both problems.

## Follow-on milestones (same App Store release)

These are the next steps on the same dev branch. Each is a small, separately-reviewable diff but ships in the same release as the seed migrator and DashSync's removal.

**1. Wire a Wave-1 adapter to consume the migrated runtime descriptor.** Build a `SwiftDashSDKWalletProvider` that surfaces a detached `HDWallet` from the app-owned runtime descriptor, and point the first Wave-1 function adapter (likely #1 receive address per `DASHSYNC_MIGRATION.md`, or the SPV chain sync work — see `DASHSYNC_MIGRATION.md` row #11) at it. This is the first end-to-end proof that the wallet bytes the migrator wrote are usable.

**2. Remove the DashSync CocoaPods dependency.** Once every Wave 1–4 function in `DASHSYNC_MIGRATION.md` is on SwiftDashSDK and the app no longer needs DashSync at runtime, drop the pod. The DashSync keychain entries previous app versions wrote remain on user devices and remain readable by the migrator. **They are never deleted.**

## Open risks and notes

- **Multi-wallet prevalence is unknown.** The migrator ships a "skip if >1 wallet" guard. We need telemetry on the `swiftSDKKeyMigration.v1.deferredMultiWallet` counter to know whether we need a follow-up commit to handle multi-wallet on the same dev branch before the release.
- **Devnet/regtest/evonet not supported.** Network detection only matches mainnet and testnet. Users on other networks see migration deferred via `swiftSDKKeyMigration.v1.deferredUnknownChain`. Follow-up commit on the same dev branch if telemetry shows non-zero incidence.
- **Wallet ID stability across libraries (informational).** DashSync's wallet ID is `%0llx` of a 64-bit hash; SwiftDashSDK's wallet ID is 32 bytes from `wallet_manager_add_wallet_from_mnemonic_return_serialized_bytes`. These are NOT the same value and cannot be cross-referenced. Under the one-shot model nothing needs to correlate them — DashSync's IDs only matter to DashSync, and DashSync is gone after the release. Listed here only so future readers don't get confused by the difference.
- **PIN-hash format mismatch (informational).** DashSync stores PIN as UTF-8 plaintext; SwiftDashSDK stores `SHA256(PIN)` (unsalted, single round). The migrator reads the plaintext, derives the seed, and writes the encrypted seed via `WalletStorage.storeSeed(seed, pin:)`, which produces the SwiftDashSDK PIN hash as a side effect. Post-migration there is only one PIN representation in play (SwiftDashSDK's), so there is no reconciliation work to do.
- **`kSecAttrAccessible` mismatch on PIN.** DashSync's PIN uses `AfterFirstUnlockThisDeviceOnly` (background-readable); SwiftDashSDK's `wallet.pin` uses `WhenUnlockedThisDeviceOnly` (foreground-only). The migrator only runs at `didFinishLaunching` so this doesn't bite us, but background unlock paths added in future commits on this branch must not assume the SwiftDashSDK PIN hash is readable in the background.
- **`ensurePlatformPaymentAccount` failure** is treated as non-fatal — the migrator logs a warning and proceeds. Matches the behavior of `CoreWalletManager.createWallet` (`CoreWalletManager.swift:78-83`). Acceptable because we do not use platform features at the point the migrator runs.
- **Background dispatch race window.** Because the migrator body runs on `DispatchQueue.global(qos: .userInitiated)`, there is a window between launch finish and migration completion (~300–500 ms one-time, immediately after the upgrade installs) during which the SwiftDashSDK side is not yet populated. Irrelevant for the migrator in isolation because no consumer reads `wallet.seed` or the runtime descriptor synchronously on launch, but the **first** Wave-1 adapter that consumes the migrated wallet must use an explicit "migration complete" handshake — polling `UserDefaults.standard.string(forKey: "swiftSDKKeyMigration.v1.done")` or NotificationCenter post on completion — rather than assuming synchronous completion.
- **Thread-safety verification (background dispatch).** Every API the migrator touches is thread-safe or used in a thread-confined manner: `UserDefaults.standard` (thread-safe per Apple), `SecItemCopyMatching/Add/Delete` (thread-safe), `Mnemonic.validate/toSeed` (pure FFI, no shared state), `WalletManager(network:)` (creates a fresh FFI handle owned by the dispatched thread for the duration of the function), `WalletStorage()` (just keychain), `SwiftDashSDKRuntimeWalletStore()` (just keychain + property-list encode/decode), and `os.log` `Logger` (thread-safe). No actor isolation needed.

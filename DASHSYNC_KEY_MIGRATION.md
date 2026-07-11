# DashSync -> SwiftDashSDK key migration

Current contract for importing wallet mnemonics from DashSync-owned keychain
entries into the host-owned SwiftDashSDK runtime. Updated 2026-07-11 to include
multi-wallet and active-wallet behavior.

## Deployment model and invariant

The migrator ships in the same release as the final DashSync removal. It may
read old DashSync state, but it must never mutate or delete the DashSync-owned
keychain service `org.dashfoundation.dash`.

All new writes go to SDK-owned persistence:

- `PlatformWalletManager` / SwiftData for managed-wallet rows;
- SwiftDashSDK `WalletStorage` for mnemonic bytes keyed by SDK wallet ID;
- `WalletEnvironment` UserDefaults entries for the active wallet per network.

DashSync mnemonic entries remain a read-only recovery/rollback source.

## Frozen DashSync keychain contract

Only compatibility code may know these old layouts:

| Data | Service | Account | Format |
|---|---|---|---|
| Mnemonic | `org.dashfoundation.dash` | `WALLET_MNEMONIC_KEY_<dashSyncWalletID>` | UTF-8 BIP39 phrase |
| Wallet list per chain | `org.dashfoundation.dash` | `CHAIN_WALLETS_KEY_<genesisShortHex>` | NSKeyedArchiver array of DashSync wallet ID strings |
| Extended-public-key cache | `org.dashfoundation.dash` | `<pathReference>_<dashSyncWalletID>` | Raw `NSData`; not imported |

DashSync wallet IDs are short hash strings. SDK wallet IDs are 32-byte SDK
identifiers and are not expected to match.

Known chain suffixes:

| Network | Genesis short hex |
|---|---|
| Mainnet | `b67a40f` |
| Testnet | `2cbcf83` |

## Current migrator algorithm

`SwiftDashSDKKeyMigrator.migrateIfNeeded()` returns immediately and performs the
work on a background queue:

1. If `swiftSDKKeyMigration.v1.done` exists, return.
2. Clear stale legacy defer flags and enumerate every
   `WALLET_MNEMONIC_KEY_*` account.
3. If none exist, mark migration done (fresh install or already wiped device).
4. For each DashSync wallet ID not already present in the success ledger:
   - resolve mainnet/testnet membership from the frozen chain-wallet lists;
   - read and validate the mnemonic;
   - sanity-check deterministic seed derivation;
   - call `SwiftDashSDKHost.createOrImportWallet` on the main actor;
   - persist the DashSync wallet ID in
     `swiftSDKKeyMigration.v1.migratedDashSyncWalletIds`.
5. Set the done sentinel only when every discovered wallet either migrated or
   was already in the ledger and no wallet has an unknown chain/failure.
6. Notify `SwiftDashSDKWalletRuntime` after the done sentinel is written.

Partial runs are resumable: successfully migrated wallet IDs are not imported
again, while failures are retried on a later launch.

## Multi-wallet behavior

Multiple DashSync wallets are supported. The old
`swiftSDKKeyMigration.v1.deferredMultiWallet` flag is legacy compatibility
state: the current migrator clears it and does not use it as a skip condition.

After wallets load, `SwiftDashSDKHost` resolves the active wallet using
`WalletEnvironment.activeWalletId(for:)`, scoped independently to mainnet and
testnet. If the recorded ID is absent, the manager selects its deterministic
`firstWallet` fallback and persists that choice.

Create/import/switch/remove and network-mirror code must always resolve by the
active wallet ID. Selecting `persistedMnemonics().first` is forbidden when more
than one wallet exists; that previously mirrored or displayed the wrong wallet.

## Incomplete cases

| Condition | Behavior |
|---|---|
| Unknown/unsupported DashSync chain | Set `swiftSDKKeyMigration.v1.deferredUnknownChain`; leave done unset; retry later. |
| Mnemonic missing/invalid or host creation fails | Leave done unset; retain successes in the per-wallet ledger; retry later. |
| No old mnemonics | Mark done so SDK runtime startup does not wait indefinitely. |

The runtime treats legacy defer flags as permission to stop waiting, but the
migrator remains responsible for clearing stale values and retrying incomplete
work.

## Host recovery behavior

If SwiftData wallet rows are missing but SDK-owned mnemonic entries remain,
`SwiftDashSDKHost.recoverPersistedWallet` recreates managed wallets from every
valid stored mnemonic. Wallet creation is idempotent by SDK wallet ID. Because
mnemonics are network-agnostic while wallet IDs can be network-specific, the
host re-stores the mnemonic under the created ID when needed.

## Wipe contract

The app-level wipe posts `DWWillWipeWalletNotification`. The SDK wiper deletes
SDK-owned mnemonics and managed-wallet state, clears active-wallet registry
entries, and tears down runtime state. During the migration window,
`DWEnvironment` also unregisters DashSync wallets and clears DashSync Core Data,
but it still must not delete the frozen DashSync mnemonic keychain entries.

The DashSync wipe arm is removed with C6-E after invitations/profile and Watch
no longer require DashSync wallet objects.

## Acceptance criteria

- one and multiple DashSync wallets import without selecting the wrong active
  wallet;
- a partial failure resumes without duplicating successful wallets;
- mainnet and testnet retain separate active-wallet choices;
- create/import/recovery use the same host boundary;
- network switch mirrors only the active wallet while the legacy shim exists;
- wipe deletes all SDK-owned mnemonic/managed-wallet/active-wallet state;
- no migration code deletes `org.dashfoundation.dash` entries;
- both app schemes build and upgrade/multi-wallet/wipe runtime smokes pass.

## Source files

- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKKeyMigrator.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKHost.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/WalletEnvironment.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletRuntime.swift`
- `DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletWiper.swift`

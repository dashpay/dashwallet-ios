# DashSync -> SwiftDashSDK key migration

Status ledger for moving wallet key material from DashSync's keychain layout into SwiftDashSDK's host-owned wallet runtime. Sibling to [`DASHSYNC_MIGRATION.md`](./DASHSYNC_MIGRATION.md).

**Deployment model.** This migration lands on the development branch and ships in the same App Store release as DashSync removal. There is no production window where a partially migrated dual-stack wallet must be supported.

## Hard Invariant

Keys written by DashSync into the iOS Keychain (`org.dashfoundation.dash` service) are never deleted by this codebase. The migrator only reads those entries. All SwiftDashSDK writes target SDK-owned storage: SwiftData wallet rows through `SwiftDashSDKHost` and per-wallet mnemonics through `WalletStorage`.

## Current Shape

| Area | Status | Notes |
|---|---|---|
| Key migrator | Landed | Reads one DashSync mnemonic, detects mainnet/testnet, and asks `SwiftDashSDKHost` to create/import the managed wallet. |
| Runtime ownership | Landed | `SwiftDashSDKHost` owns `SDK`, `ModelContainer`, `PlatformWalletManager`, and the active `ManagedPlatformWallet`. |
| Key storage | Landed | `WalletStorage.storeMnemonic(_:for:)` stores the mnemonic under the `ManagedPlatformWallet.walletId` returned by the SDK. |
| DashSync removal | Pending | DashSync keychain entries stay on device as read-only rollback source. |

## Frozen DashSync Keychain Contract

`SwiftDashSDKKeyMigrator.swift` is the only file that knows DashSync's keychain layout. These entries describe data written by older app versions and must remain readable after the DashSync library is removed.

| What | Service | Account | Format | Source |
|---|---|---|---|---|
| Mnemonic | `org.dashfoundation.dash` | `WALLET_MNEMONIC_KEY_<walletID>` | UTF-8 BIP39 phrase | `DSWallet.m` |
| Wallet list per chain | `org.dashfoundation.dash` | `CHAIN_WALLETS_KEY_<chainGenesisShortHex>` | NSKeyedArchiver `NSArray<NSString *>` of wallet IDs | `DSChain.m` |
| Extended public key cache | `org.dashfoundation.dash` | `<pathReference>_<walletID>` | raw NSData | `DSDerivationPath.m` |

Wallet ID format is DashSync-specific (`%0llx` 64-bit hash). SwiftDashSDK wallet IDs are 32-byte SDK identifiers and are not expected to match.

Precomputed chain suffixes:

| Network | Displayed genesis hex | shortHex |
|---|---|---|
| Mainnet | `00000ffd590b1485b3caadc19b22e6379c733355108f107a430458cdf3407ab6` | `b67a40f` |
| Testnet | `00000bafbc94add76cb75e2ec92894837288a481e5c005f6563d91623bf8bc2c` | `2cbcf83` |

## Migrator Design

`migrateIfNeeded()` dispatches to a background queue, checks the one-shot `swiftSDKKeyMigration.v1.done` sentinel, reads the single DashSync mnemonic, detects the wallet network, validates the mnemonic, and then synchronously hops to `SwiftDashSDKHost` on the main actor.

The host creates/imports the wallet with `PlatformWalletManager.createWallet(mnemonic:network:name:createDefaultAccounts:)`, persists the SDK wallet row through SwiftData, stores the mnemonic in `WalletStorage` under the returned wallet id, and publishes that `ManagedPlatformWallet` as the active host wallet.

The migrator then sets the done sentinel and calls `SwiftDashSDKWalletRuntime.handleWalletMaterialChanged()` so runtime startup reloads from the host-owned managed wallet.

## Skip Cases

| Condition | Flag |
|---|---|
| More than one DashSync wallet found | `swiftSDKKeyMigration.v1.deferredMultiWallet` |
| Wallet on unsupported devnet/regtest/evonet chain | `swiftSDKKeyMigration.v1.deferredUnknownChain` |

No-PIN is no longer a skip case because SwiftDashSDK key material is mnemonic-only.

## Acceptance Criteria

- Obsolete app-owned descriptor/provider files are absent from app sources and project membership.
- `SwiftDashSDKWalletRuntime` starts SPV by network and resolves wallet state through `SwiftDashSDKHost`.
- Create, recover, and migration paths all use the same host create/import entry point.
- Wipe deletes per-wallet mnemonics and then tears down the host/runtime.
- `dashwallet` and `dashpay` simulator builds pass.

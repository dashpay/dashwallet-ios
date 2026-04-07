//
//  SwiftDashSDKKeyMigrator.swift
//  DashWallet
//
//  One-shot migrator that copies wallet key material from DashSync's
//  keychain layout into SwiftDashSDK's WalletStorage + HDWallet (SwiftData).
//
//  Hard invariants — see DASHSYNC_KEY_MIGRATION.md:
//    1. NEVER deletes from `org.dashfoundation.dash` (DashSync's keychain
//       service). DashSync entries are read-only here forever; they are
//       preserved indefinitely as belt-and-suspenders rollback source.
//    2. NEVER throws and NEVER crashes — `migrateIfNeeded()` returns Void
//       and swallows all errors into os.log entries.
//    3. NEVER modifies user-visible state. No UI, no DWGlobalOptions,
//       no DashSync state mutation.
//    4. Runs early in app launch, BEFORE any DashSync initialization, to
//       sidestep the iPhone 17 + iOS 26.3 `[DSChain retrieveWallets]` crash.
//    5. No force-unwraps, no `try!`, no `as!`.
//
//  This file is the ONLY place in dashwallet-ios that knows DashSync's
//  keychain layout. The constants below are a frozen contract — once this
//  ships, DashSync the *library* can be removed from the binary and the
//  migrator will still work, because the keychain items previous app
//  versions wrote survive app updates and we never delete them.
//

import CryptoKit
import Foundation
import OSLog
import Security
import SwiftData
import SwiftDashSDK

@objc(DWSwiftDashSDKKeyMigrator)
final class SwiftDashSDKKeyMigrator: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.key-migrator")

    // MARK: - Frozen contract: DashSync keychain layout (read-only forever)

    /// DashSync's keychain service identifier — `NSData+Dash.h:37`.
    private static let dashSyncService = "org.dashfoundation.dash"

    /// Prefix for per-wallet mnemonic items — `DSWallet.m:67`.
    /// Full account: `WALLET_MNEMONIC_KEY_<walletID>` where `walletID` is
    /// `[NSString stringWithFormat:@"%0llx", uint64_t]` (16 hex chars max).
    /// Value: raw UTF-8 BIP39 phrase. Access:
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
    private static let dashSyncMnemonicAccountPrefix = "WALLET_MNEMONIC_KEY_"

    /// PIN account name — `DSAuthenticationManager.m:62`. Plaintext UTF-8.
    private static let dashSyncPINAccount = "pin"

    /// Prefix for per-chain wallet list items — `DSChain.m:94`. Full account:
    /// `CHAIN_WALLETS_KEY_<chainGenesisShortHex>` where the suffix is the
    /// first 7 hex chars of `[NSData dataWithUInt256:genesisHash].hexString`.
    /// Value: NSKeyedArchiver-encoded `NSArray<NSString *>` of wallet IDs.
    private static let dashSyncChainWalletsKeyPrefix = "CHAIN_WALLETS_KEY_"

    /// `shortHexString` of the mainnet genesis block hash UInt256, as DashSync
    /// stores it in the keychain account suffix. The displayed (big-endian)
    /// genesis hex is `00000ffd590b1485b3caadc19b22e6379c733355108f107a430458cdf3407ab6`
    /// (`mainnet_checkpoint_array[0]` in DashSync's `DSChainCheckpoints.h`).
    /// DashSync byte-reverses it before storing as UInt256, so the in-memory
    /// representation begins with `b67a40f3...` and `shortHexString` (first 7
    /// hex chars) is `b67a40f`.
    private static let mainnetGenesisShortHex = "b67a40f"

    /// Same computation for testnet. Displayed genesis hex:
    /// `00000bafbc94add76cb75e2ec92894837288a481e5c005f6563d91623bf8bc2c`.
    /// Reversed in-memory representation begins with `2cbcf83b...`,
    /// `shortHexString` is `2cbcf83`.
    private static let testnetGenesisShortHex = "2cbcf83"

    // MARK: - SwiftDashSDK keychain layout (we own this; cleanup-safe)

    /// SwiftDashSDK's keychain service — `WalletStorage.swift:9`. Owned by us.
    private static let swiftDashSDKService = "org.dash.wallet"

    /// Encrypted seed account — `WalletStorage.swift:10`. Owned by us.
    private static let swiftDashSDKSeedAccount = "wallet.seed"

    // MARK: - UserDefaults keys

    /// Stores `SHA256(pin)` as hex when migration is complete; absent before
    /// first run. Used both for idempotency and PIN-change detection.
    private static let doneKey = "swiftSDKKeyMigration.v1.done"

    private static let deferredNoPINKey         = "swiftSDKKeyMigration.v1.deferredNoPIN"
    private static let deferredMultiWalletKey   = "swiftSDKKeyMigration.v1.deferredMultiWallet"
    private static let deferredUnknownChainKey  = "swiftSDKKeyMigration.v1.deferredUnknownChain"

    // MARK: - Public entry point

    /// Synchronous Obj-C entry point. Performs the entire migration inline
    /// on the calling thread (which is the main thread in our launch sequence).
    /// Uses the lowest-level public SwiftDashSDK API surface — standalone
    /// `WalletManager`, `WalletStorage`, and direct `HDWallet` construction —
    /// so there is no `SPVClient`, no `CoreWalletManager`, no `@MainActor`
    /// requirement, and no `Task` dispatch. Never throws, never crashes;
    /// total cost is ~300–500 ms once per device, dominated by PBKDF2 inside
    /// `WalletStorage.storeSeed`.
    @objc(migrateIfNeeded)
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        let doneFlag = defaults.string(forKey: doneKey)
        let currentPIN = readKeychainString(service: dashSyncService, account: dashSyncPINAccount)
        let currentPINHash = currentPIN.map { sha256Hex($0) }

        // Path 1 — already migrated. Handle wipe + PIN-change branches.
        if let doneFlag {
            // Wipe detection: DashSync mnemonics gone, our seed lingers.
            if enumerateDashSyncMnemonicAccounts().isEmpty && walletStorageHasSeed() {
                try? WalletStorage().deleteSeed()
                defaults.removeObject(forKey: doneKey)
                logger.info("wipe detected: cleared SwiftDashSDK seed and done flag")
                return
            }

            // PIN-change detection: re-encrypt the seed with the new PIN.
            // We do NOT recreate the HDWallet record — `addWalletAndSerialize`
            // is non-idempotent and would create a duplicate. Just rotate the
            // encryption key on the existing seed via WalletStorage.storeSeed.
            if let currentPIN, !currentPIN.isEmpty,
               let currentPINHash, doneFlag != currentPINHash {
                reencryptSeedForPINChange(newPIN: currentPIN, newPINHash: currentPINHash)
                return
            }

            // Happy-path no-op (~1 ms total).
            return
        }

        // Path 2 — fresh migration. Enumerate, validate, dispatch Task.
        let mnemonicAccounts = enumerateDashSyncMnemonicAccounts()
        switch mnemonicAccounts.count {
        case 0:
            defaults.set("none", forKey: doneKey)
            logger.info("no DashSync mnemonics found — fresh install or post-wipe, marking done")
            return
        case 1:
            break  // happy path
        default:
            logger.warning("multi-wallet detected (\(mnemonicAccounts.count, privacy: .public)) — deferring")
            defaults.set(mnemonicAccounts.count, forKey: deferredMultiWalletKey)
            return
        }

        let mnemonicAccount = mnemonicAccounts[0]
        let walletID = String(mnemonicAccount.dropFirst(dashSyncMnemonicAccountPrefix.count))

        guard let network = detectNetwork(forWalletID: walletID) else {
            logger.warning("could not determine chain for wallet \(walletID, privacy: .public) — deferring")
            defaults.set(true, forKey: deferredUnknownChainKey)
            return
        }

        guard let mnemonic = readKeychainString(service: dashSyncService, account: mnemonicAccount) else {
            logger.error("failed to read mnemonic from \(mnemonicAccount, privacy: .public)")
            return
        }

        guard let pin = currentPIN, !pin.isEmpty else {
            logger.warning("no PIN in DashSync keychain — deferring")
            defaults.set(true, forKey: deferredNoPINKey)
            return
        }

        guard Mnemonic.validate(mnemonic) else {
            logger.error("DashSync mnemonic failed SwiftDashSDK BIP39 validation")
            return
        }

        let pinHash = sha256Hex(pin)

        // Inline heavy work — fully synchronous, no Task, no @MainActor.
        // We construct a standalone WalletManager (no SPVClient), persist
        // the wallet bytes via a fresh ModelContext, and store the
        // encrypted seed via WalletStorage. Everything is local to this
        // function; the FFI wallet manager handle is freed by ARC when
        // walletManager goes out of scope at the end of this function.
        do {
            // Determinism + length sanity check (extra belt-and-suspenders).
            let seed = try Mnemonic.toSeed(mnemonic: mnemonic)
            guard seed.count == 64 else {
                logger.error("seed length invalid: \(seed.count, privacy: .public)")
                return
            }
            let seedCheck = try Mnemonic.toSeed(mnemonic: mnemonic)
            guard seedCheck == seed else {
                logger.error("seed determinism check failed")
                return
            }

            // Standalone WalletManager — public init, owns its own FFI handle.
            let walletManager = try WalletManager(network: network)

            // Register the wallet with the FFI and capture the serialized bytes.
            // birthHeight matches CoreWalletManager.createWallet's isImport: true
            // behaviour (730k for mainnet, 0 for everything else).
            let addResult = try walletManager.addWalletAndSerialize(
                mnemonic: mnemonic,
                passphrase: nil,
                birthHeight: network == .mainnet ? 730_000 : 0,
                accountOptions: .default,
                downgradeToPublicKeyWallet: false,
                allowExternalSigning: false)

            // Optional platform payment account — non-fatal, matches
            // CoreWalletManager.createWallet behaviour. v1 doesn't use
            // platform features, so failure here is fine.
            do {
                try walletManager.ensurePlatformPaymentAccount(walletId: addResult.walletId)
            } catch {
                logger.warning("ensurePlatformPaymentAccount failed (non-fatal): \(String(describing: error), privacy: .public)")
            }

            // Encrypt and store the seed via WalletStorage.
            let storage = WalletStorage()
            _ = try storage.storeSeed(seed, pin: pin)

            // Round-trip verify the encrypted seed before persisting the
            // HDWallet record. If verify fails, roll back the seed write.
            let readBack = try storage.retrieveSeed(pin: pin)
            guard readBack == seed else {
                logger.error("round-trip seed mismatch — rolling back SwiftDashSDK seed")
                try? storage.deleteSeed()
                return
            }

            // Persist the HDWallet SwiftData record. We construct a fresh
            // ModelContext (not mainContext) so this code path doesn't
            // require @MainActor isolation. The new context writes to the
            // same on-disk store as any future ModelContainer that
            // ModelContainerHelper.createContainer() returns.
            let modelContainer = try ModelContainerHelper.createContainer()
            let context = ModelContext(modelContainer)
            let appNetwork: AppNetwork = (network == .mainnet) ? .mainnet : .testnet
            let hdWallet = HDWallet(
                walletId: addResult.walletId,
                serializedWalletBytes: addResult.serializedWallet,
                label: "Migrated wallet",
                network: appNetwork,
                isWatchOnly: false,
                isImported: true)
            context.insert(hdWallet)
            try context.save()

            // Mark done. Store SHA256(pin) for PIN-change detection.
            defaults.set(pinHash, forKey: doneKey)
            defaults.removeObject(forKey: deferredNoPINKey)
            defaults.removeObject(forKey: deferredMultiWalletKey)
            defaults.removeObject(forKey: deferredUnknownChainKey)

            logger.info("migration complete: 1 wallet on \(String(describing: network), privacy: .public)")
        } catch {
            logger.error("migration threw: \(String(describing: error), privacy: .public)")
            // Best-effort: leave SwiftDashSDK side clean if anything was partially written.
            try? WalletStorage().deleteSeed()
        }
    }

    // MARK: - PIN-change re-encrypt (sync, no SDK init)

    /// Re-encrypts the existing SwiftDashSDK seed with the user's new PIN.
    /// Does NOT touch SwiftData / HDWallet — `addWalletAndSerialize` is
    /// non-idempotent so we cannot re-run the full migration without
    /// creating a duplicate FFI wallet.
    private static func reencryptSeedForPINChange(newPIN: String, newPINHash: String) {
        let mnemonicAccounts = enumerateDashSyncMnemonicAccounts()
        guard mnemonicAccounts.count == 1 else {
            // Don't second-guess multi-wallet here either; just bail and let
            // the next launch's first-run path handle it once it's resolved.
            logger.warning("PIN re-encrypt skipped: \(mnemonicAccounts.count, privacy: .public) wallets present")
            return
        }
        guard let mnemonic = readKeychainString(
            service: dashSyncService,
            account: mnemonicAccounts[0]
        ), Mnemonic.validate(mnemonic) else {
            logger.error("PIN re-encrypt: failed to read or validate mnemonic")
            return
        }

        do {
            let seed = try Mnemonic.toSeed(mnemonic: mnemonic)
            _ = try WalletStorage().storeSeed(seed, pin: newPIN)

            // Sanity round-trip
            let readBack = try WalletStorage().retrieveSeed(pin: newPIN)
            guard readBack == seed else {
                logger.error("PIN re-encrypt: round-trip mismatch")
                return
            }

            UserDefaults.standard.set(newPINHash, forKey: doneKey)
            logger.info("PIN change: re-encrypted seed with new PIN")
        } catch {
            logger.error("PIN re-encrypt threw: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Helpers

    /// Enumerate all keychain accounts in `org.dashfoundation.dash` whose
    /// account name starts with `WALLET_MNEMONIC_KEY_`. Returns the full
    /// account names (including the prefix), sorted for determinism.
    private static func enumerateDashSyncMnemonicAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     dashSyncService,
            kSecMatchLimit as String:      kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return []
        }
        return items
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(dashSyncMnemonicAccountPrefix) }
            .sorted()
    }

    /// Determine which network a wallet ID belongs to by enumerating
    /// `CHAIN_WALLETS_KEY_<chainGenesisShortHex>` items, decoding each as an
    /// NSKeyedArchiver `NSArray<NSString *>` of wallet IDs, and matching the
    /// chain genesis short-hex against our hard-coded mainnet/testnet
    /// constants. Returns `nil` for devnet/regtest/evonet (unsupported in v1).
    private static func detectNetwork(forWalletID walletID: String) -> KeyWalletNetwork? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      dashSyncService,
            kSecMatchLimit as String:       kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            return nil
        }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(dashSyncChainWalletsKeyPrefix),
                  let data = item[kSecValueData as String] as? Data else {
                continue
            }

            let chainSuffix = String(account.dropFirst(dashSyncChainWalletsKeyPrefix.count))

            let allowedClasses: [AnyClass] = [NSArray.self, NSString.self]
            guard let unarchived = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClasses: allowedClasses, from: data),
                  let walletIDs = unarchived as? [String] else {
                continue
            }

            if walletIDs.contains(walletID) {
                if chainSuffix == mainnetGenesisShortHex { return .mainnet }
                if chainSuffix == testnetGenesisShortHex { return .testnet }
                // Unknown chain (devnet/regtest/evonet) — defer in v1.
                return nil
            }
        }
        return nil
    }

    /// Read a UTF-8 string value from a keychain item. Returns nil on any failure.
    private static func readKeychainString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Returns true if SwiftDashSDK's WalletStorage already holds an encrypted seed.
    private static func walletStorageHasSeed() -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  swiftDashSDKService,
            kSecAttrAccount as String:  swiftDashSDKSeedAccount,
            kSecMatchLimit as String:   kSecMatchLimitOne,
            kSecReturnData as String:   false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Hex-encoded SHA256 of a UTF-8 string. Used for PIN-change detection.
    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

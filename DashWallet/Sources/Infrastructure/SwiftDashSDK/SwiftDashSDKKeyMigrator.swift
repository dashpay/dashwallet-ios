//
//  SwiftDashSDKKeyMigrator.swift
//  DashWallet
//
//  One-shot migrator that copies wallet key material from DashSync's
//  keychain layout into SwiftDashSDK's host-owned wallet runtime. The host
//  creates the ManagedPlatformWallet, persists the SwiftData wallet row, and
//  stores the mnemonic in WalletStorage under the returned wallet id.
//
//  Hard invariants — see DASHSYNC_KEY_MIGRATION.md:
//    1. NEVER deletes from `org.dashfoundation.dash` (DashSync's keychain
//       service). DashSync entries are read-only here forever; they are
//       preserved indefinitely as belt-and-suspenders rollback source.
//    2. NEVER throws and NEVER crashes — `migrateIfNeeded()` returns Void
//       and swallows all errors into os.log entries.
//    3. NEVER modifies user-visible state. No UI, no DWGlobalOptions,
//       no DashSync state mutation.
//    4. Runs early in app launch, BEFORE any DashSync initialization, so
//       the migrator owns the keychain read window before DashSync touches
//       its own wallet state.
//    5. No force-unwraps, no `try!`, no `as!`.
//
//  This file is the ONLY place in dashwallet-ios that knows DashSync's
//  keychain layout. The constants below are a frozen contract — once this
//  ships, DashSync the *library* can be removed from the binary and the
//  migrator will still work, because the keychain items previous app
//  versions wrote survive app updates and we never delete them.
//

import Foundation
import OSLog
import Security
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

    // MARK: - UserDefaults keys

    /// Stores a version sentinel (`"v1"`) when migration is complete;
    /// absent before first run. Used purely for idempotency; the migrator only
    /// owns the one-time DashSync → SwiftDashSDK handoff.
    private static let doneKey = "swiftSDKKeyMigration.v1.done"

    private static let deferredMultiWalletKey   = "swiftSDKKeyMigration.v1.deferredMultiWallet"
    private static let deferredUnknownChainKey  = "swiftSDKKeyMigration.v1.deferredUnknownChain"
    /// Set when a run ended with a read/validate/import failure. Without a
    /// terminal flag for this case, every consumer waiting on the sentinel
    /// (the runtime's 30s poll, the root controller's launch decision) timed
    /// out on every launch while the migrator kept failing — stranding a
    /// restored wallet behind a permanently stopped runtime.
    private static let deferredFailureKey = "swiftSDKKeyMigration.v1.deferredFailure"

    /// Per-wallet success ledger — DashSync walletIDs that already round-tripped
    /// through `createOrImportWallet`. Lets a partial-failure run resume on next
    /// launch without re-importing the ones that already landed.
    private static let migratedDashSyncWalletIdsKey = "swiftSDKKeyMigration.v1.migratedDashSyncWalletIds"

    // MARK: - Public entry point

    /// Synchronous Obj-C entry point. Dispatches the entire migrator body
    /// to a background queue (`DispatchQueue.global(qos: .userInitiated)`)
    /// and returns to the caller in microseconds, so launch is not blocked.
    /// The actual migration completes ~300–500 ms later in the background
    /// while the user is already looking at the home screen.
    ///
    /// Runtime startup waits for the `swiftSDKKeyMigration.v1.done` sentinel
    /// before it asks `SwiftDashSDKHost` to load the persisted wallet.
    ///
    /// Never throws, never crashes.
    @objc(migrateIfNeeded)
    static func migrateIfNeeded() {
        DispatchQueue.global(qos: .userInitiated).async {
            performMigration()
        }
    }

    // MARK: - Background migration body

    /// The actual migration body. Runs on a background `DispatchQueue` —
    /// validates DashSync's mnemonic on a background queue, then synchronously
    /// asks `SwiftDashSDKHost` on the main actor to create/import the managed
    /// wallet and store mnemonic material in `WalletStorage`.
    private static func performMigration() {
        let defaults = UserDefaults.standard

        // Path 1 — already migrated. One-shot, single-release migration plan:
        // there is no dual-stack window in which DashSync's wipe UI could
        // orphan SwiftDashSDK wallet material, so no cross-library
        // wipe-detection branch is needed.
        if defaults.string(forKey: doneKey) != nil {
            return
        }

        // Clear stale defer flags before re-evaluating. The runtime reads
        // any flag as permission to stop waiting for migration — leaving
        // a stale value would race the loop below.
        defaults.removeObject(forKey: deferredMultiWalletKey)
        defaults.removeObject(forKey: deferredUnknownChainKey)
        defaults.removeObject(forKey: deferredFailureKey)

        let mnemonicAccounts = enumerateDashSyncMnemonicAccounts()
        if mnemonicAccounts.isEmpty {
            defaults.set("v1", forKey: doneKey)
            logger.info("🔑 KEYMIG :: no DashSync mnemonics found — fresh install or post-wipe, marking done")
            return
        }

        var migrated = Set(defaults.stringArray(forKey: migratedDashSyncWalletIdsKey) ?? [])
        var hadUnknownChain = false
        var hadFailure = false
        var migratedThisRun = 0

        for account in mnemonicAccounts {
            let walletID = String(account.dropFirst(dashSyncMnemonicAccountPrefix.count))
            if migrated.contains(walletID) {
                continue
            }

            guard let network = detectNetwork(forWalletID: walletID) else {
                logger.warning("🔑 KEYMIG :: \(walletID, privacy: .public) chain unresolved/unsupported")
                hadUnknownChain = true
                continue
            }

            guard let mnemonic = readKeychainString(service: dashSyncService, account: account),
                  Mnemonic.validate(mnemonic) else {
                logger.error("🔑 KEYMIG :: \(walletID, privacy: .public) mnemonic read/validate failed")
                hadFailure = true
                continue
            }

            do {
                let seed = try Mnemonic.toSeed(mnemonic: mnemonic)
                guard seed.count == 64, try Mnemonic.toSeed(mnemonic: mnemonic) == seed else {
                    logger.error("🔑 KEYMIG :: \(walletID, privacy: .public) seed sanity check failed")
                    hadFailure = true
                    continue
                }
                let sdkWalletId = try createWalletOnHost(
                    mnemonic: mnemonic,
                    network: network,
                    isImported: true)
                let prefix = sdkWalletId.prefix(4).map { String(format: "%02x", $0) }.joined()
                logger.info("🔑 KEYMIG :: migrated \(walletID, privacy: .public) → \(prefix, privacy: .public)… on \(String(describing: network), privacy: .public)")

                migrated.insert(walletID)
                defaults.set(migrated.sorted(), forKey: migratedDashSyncWalletIdsKey)
                migratedThisRun += 1
            } catch {
                logger.error("🔑 KEYMIG :: \(walletID, privacy: .public) threw: \(String(describing: error), privacy: .public)")
                hadFailure = true
            }
        }

        if !hadFailure && !hadUnknownChain {
            defaults.set("v1", forKey: doneKey)
            logger.info("🔑 KEYMIG :: migration complete (\(migrated.count, privacy: .public) total, \(migratedThisRun, privacy: .public) this run)")
            // Notify runtime only after doneKey is set — its wait loop polls for it.
            SwiftDashSDKWalletRuntime.handleWalletMaterialChanged()
        } else {
            if hadUnknownChain {
                defaults.set(true, forKey: deferredUnknownChainKey)
            }
            if hadFailure {
                defaults.set(true, forKey: deferredFailureKey)
            }
            logger.warning("🔑 KEYMIG :: migration incomplete — will retry on next launch")
        }
    }

    // MARK: - Launch-decision probes

    /// True while DashSync wallet material exists in the keychain and the
    /// one-shot migration has not completed. The root controller holds its
    /// initial-screen decision while this is true — deciding "no wallet"
    /// inside the async migration window showed Create/Recover to upgrading
    /// users whose wallet was milliseconds from landing (and routed their
    /// typed phrase into the recover screen's wipe branch).
    @objc
    static func legacyWalletMaterialPendingMigration() -> Bool {
        guard UserDefaults.standard.string(forKey: doneKey) == nil else { return false }
        return !enumerateDashSyncMnemonicAccounts().isEmpty
    }

    /// True once the migrator reached a terminal state for this launch:
    /// completed, or recorded any deferral/failure flag (each of which every
    /// waiter treats as "stop waiting").
    @objc
    static func migrationSettled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: doneKey) != nil { return true }
        return [deferredMultiWalletKey, deferredUnknownChainKey, deferredFailureKey]
            .contains { defaults.object(forKey: $0) != nil }
    }

    private static func createWalletOnHost(
        mnemonic: String,
        network: Network,
        isImported: Bool
    ) throws -> Data {
        guard !Thread.isMainThread else {
            throw MigrationError.hostCreateOnMainThread
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?

        Task { @MainActor in
            defer { semaphore.signal() }
            do {
                result = .success(try await SwiftDashSDKHost.shared.createOrImportWallet(
                    mnemonic: mnemonic,
                    network: network,
                    isImported: isImported
                ).walletId)
            } catch {
                result = .failure(error)
            }
        }

        semaphore.wait()
        guard let result else {
            throw MigrationError.hostCreateDidNotReturn
        }
        return try result.get()
    }

    private enum MigrationError: LocalizedError {
        case hostCreateDidNotReturn
        case hostCreateOnMainThread
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
    private static func detectNetwork(forWalletID walletID: String) -> Network? {
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
            // Distinguish "the keychain would not talk to us" from "no chain
            // claims this wallet": both used to surface as the same silent nil,
            // and the caller's log line ("chain unresolved/unsupported") reads
            // as the second while an upgrade on a locked device produces the
            // first. `errSecInteractionNotAllowed` (-25308) is that case — this
            // query asks for kSecValueData, which the enumeration pass does
            // not, so it can fail where enumeration just succeeded.
            logger.error(
                "🔑 KEYMIG :: chain-wallets keychain query failed, status \(status, privacy: .public)")
            return nil
        }

        let chainItems = items.filter {
            ($0[kSecAttrAccount as String] as? String)?
                .hasPrefix(dashSyncChainWalletsKeyPrefix) == true
        }
        if chainItems.isEmpty {
            logger.error(
                "🔑 KEYMIG :: no \(dashSyncChainWalletsKeyPrefix, privacy: .public)* items among \(items.count, privacy: .public) keychain item(s) — cannot map any wallet to a chain")
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
                logger.error(
                    "🔑 KEYMIG :: \(walletID, privacy: .public) belongs to unsupported chain \(chainSuffix, privacy: .public)")
                return nil
            }
        }
        // The wallet has a mnemonic but no chain list claims it. Name the
        // suffixes that were present, so a prefix/format change in the source
        // keychain is distinguishable from a genuinely orphaned wallet.
        let suffixes = chainItems
            .compactMap { ($0[kSecAttrAccount as String] as? String) }
            .map { String($0.dropFirst(dashSyncChainWalletsKeyPrefix.count)) }
            .joined(separator: ",")
        logger.error(
            "🔑 KEYMIG :: \(walletID, privacy: .public) not listed by any chain; chains present: [\(suffixes, privacy: .public)]")
        return nil
    }

    /// Read a UTF-8 string value from a keychain item. Returns nil on any
    /// failure. Delegates to the shared raw primitive in `PinStore` (C7).
    private static func readKeychainString(service: String, account: String) -> String? {
        PinStore.readData(service: service, account: account)
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    #if DEBUG
    // MARK: - QA fixture (DEBUG only)

    /// Fabricate DashSync's keychain layout so the App Store → SDK upgrade
    /// path can be exercised on a simulator without a real legacy install.
    /// Two mutually exclusive triggers, each clearing the migration
    /// sentinel so the migrator re-runs:
    /// - `LEGACY_KEYCHAIN_INVALID=1` plants one never-valid mnemonic entry
    ///   (the perpetually-failing-migration state) and nothing else.
    /// - `LEGACY_KEYCHAIN_MNEMONIC` = BIP39 phrase to plant, with a legacy
    ///   PIN (`LEGACY_KEYCHAIN_PIN`, default 1111); optional
    ///   `LEGACY_KEYCHAIN_ORPHAN=1` skips the chain-wallets list (the
    ///   unknown-chain defer path). This variant also clears the per-wallet
    ///   ledger and removes any previously planted invalid entry.
    /// Call before `migrateIfNeeded`.
    @objc
    static func debugInstallLegacyFixtureIfRequested() {
        let env = ProcessInfo.processInfo.environment
        // Variant: a DashSync entry whose phrase can never validate — the
        // migrator fails every run (deferredFailure), reproducing the
        // "stranded upgrader" state without touching any valid material
        // already present.
        if env["LEGACY_KEYCHAIN_INVALID"] == "1" {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: doneKey)
            _ = KeychainStore.set(
                data: Data("definitely not a valid bip39 phrase".utf8),
                service: dashSyncService,
                account: dashSyncMnemonicAccountPrefix + "deadbeefdeadbeef",
                accessibility: .whenUnlockedThisDeviceOnly)
            logger.warning("🔑 KEYMIG :: DEBUG invalid-mnemonic fixture installed")
            return
        }
        guard let phrase = env["LEGACY_KEYCHAIN_MNEMONIC"], !phrase.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: doneKey)
        defaults.removeObject(forKey: migratedDashSyncWalletIdsKey)
        // Drop any invalid entry a previous LEGACY_KEYCHAIN_INVALID run
        // planted — otherwise this run's migration sees both accounts,
        // fails on the invalid one, and can never mark itself done.
        _ = KeychainStore.set(
            data: nil,
            service: dashSyncService,
            account: dashSyncMnemonicAccountPrefix + "deadbeefdeadbeef",
            accessibility: .whenUnlockedThisDeviceOnly)

        // The legacy install had a PIN (PinStore reads DashSync's records
        // in place) — plant one so the post-migration lock screen is
        // satisfiable, as it is on a real upgrade.
        let pin = env["LEGACY_KEYCHAIN_PIN"] ?? "1111"
        _ = PinStore.set(string: pin, for: .pin)
        _ = PinStore.set(int64: 1, for: .usesAuthentication)

        let walletID = "1122334455667788"
        _ = KeychainStore.set(
            data: Data(phrase.utf8),
            service: dashSyncService,
            account: dashSyncMnemonicAccountPrefix + walletID,
            accessibility: .whenUnlockedThisDeviceOnly)
        let orphan = env["LEGACY_KEYCHAIN_ORPHAN"] == "1"
        if orphan {
            _ = KeychainStore.set(
                data: nil,
                service: dashSyncService,
                account: dashSyncChainWalletsKeyPrefix + mainnetGenesisShortHex,
                accessibility: .whenUnlockedThisDeviceOnly)
        } else if let archive = try? NSKeyedArchiver.archivedData(
            withRootObject: [walletID] as NSArray, requiringSecureCoding: false) {
            _ = KeychainStore.set(
                data: archive,
                service: dashSyncService,
                account: dashSyncChainWalletsKeyPrefix + mainnetGenesisShortHex,
                accessibility: .whenUnlockedThisDeviceOnly)
        }
        logger.warning("🔑 KEYMIG :: DEBUG legacy fixture installed (orphan=\(orphan, privacy: .public))")
    }
    #endif

}

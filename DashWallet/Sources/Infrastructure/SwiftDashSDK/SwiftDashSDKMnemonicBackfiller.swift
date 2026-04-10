//
//  SwiftDashSDKMnemonicBackfiller.swift
//  DashWallet
//
//  One-shot backfill at app launch for users who already ran the
//  key migrator or wallet creator BEFORE mnemonic storage was added.
//  Those users have a seed in WalletStorage but no mnemonic. This
//  class reads the mnemonic from DashSync's keychain and stores it
//  in WalletStorage so the backup phrase display can read from
//  SwiftDashSDK without touching DashSync.
//
//  Sentinel-gated: runs once, sets "swiftSDKMnemonicBackfill.v1.done"
//  in UserDefaults, never runs again.
//
//  This file is intentionally decoupled from DashSync — it references
//  DashSync's keychain layout as a string contract (frozen since 2019).
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKMnemonicBackfiller)
final class SwiftDashSDKMnemonicBackfiller: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.mnemonic-backfiller")

    // MARK: - Sentinel

    private static let sentinelKey = "swiftSDKMnemonicBackfill.v1.done"

    // MARK: - Public entry point

    @objc(backfillIfNeeded)
    static func backfillIfNeeded() {
        DispatchQueue.global(qos: .userInitiated).async {
            performBackfill()
        }
    }

    // MARK: - Background body

    private static func performBackfill() {
        guard !UserDefaults.standard.bool(forKey: sentinelKey) else {
            return
        }

        let storage = WalletStorage()

        // 1) Check if mnemonic already exists in WalletStorage.
        //    No PIN needed — plain keychain read.
        do {
            _ = try storage.retrieveMnemonic()
            UserDefaults.standard.set(true, forKey: sentinelKey)
            logger.info("mnemonic already in WalletStorage; marking backfill done")
            return
        } catch WalletStorageError.mnemonicNotFound {
            // Expected — proceed with backfill
        } catch {
            logger.warning("retrieveMnemonic pre-check failed: \(String(describing: error), privacy: .public)")
            return
        }

        // 2) Read mnemonic from DashSync's keychain.
        //    DashSync stores at: "WALLET_MNEMONIC_KEY_<uniqueID>" under
        //    service "org.dashfoundation.dash" (DSWallet.m:67,464).
        //    Since dashwallet-ios is single-wallet, enumerate and find
        //    the first match.
        let dashSyncService = "org.dashfoundation.dash"
        guard let mnemonic = findDashSyncMnemonic(service: dashSyncService),
              !mnemonic.isEmpty else {
            logger.info("no DashSync mnemonic found; marking backfill done")
            UserDefaults.standard.set(true, forKey: sentinelKey)
            return
        }

        // 3) Store in WalletStorage (plain keychain).
        do {
            try storage.storeMnemonic(mnemonic)
            logger.info("backfilled mnemonic into WalletStorage successfully")
        } catch {
            logger.error("backfill storeMnemonic failed: \(String(describing: error), privacy: .public)")
            return
        }

        UserDefaults.standard.set(true, forKey: sentinelKey)
    }

    // MARK: - DashSync keychain helpers

    /// Find the mnemonic stored by DashSync. DashSync uses
    /// "WALLET_MNEMONIC_KEY_<uniqueID>" as the keychain account name
    /// (DSWallet.m:67,464). Since dashwallet-ios is single-wallet,
    /// enumerate keychain items and find the first match.
    private static func findDashSyncMnemonic(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return nil
        }

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix("WALLET_MNEMONIC_KEY_"),
                  let data = item[kSecValueData as String] as? Data,
                  let mnemonic = String(data: data, encoding: .utf8),
                  !mnemonic.isEmpty else {
                continue
            }
            return mnemonic
        }
        return nil
    }
}

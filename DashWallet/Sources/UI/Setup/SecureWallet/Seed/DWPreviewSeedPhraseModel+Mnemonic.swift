//
//  DWPreviewSeedPhraseModel+Mnemonic.swift
//  DashWallet
//
//  Co-located Swift extension bridging Obj-C `DWPreviewSeedPhraseModel`
//  to SwiftDashSDK's `Mnemonic.generate(wordCount:)` (fresh-install
//  entropy source) and `WalletStorage.retrieveMnemonic(for:)`
//  (Settings → View Recovery Phrase read path). Replaces the standalone
//  `DWSwiftDashSDKMnemonicGenerator` and `DWSwiftDashSDKMnemonicReader`
//  adapters.
//

import Foundation
import OSLog
import SwiftDashSDK

extension DWPreviewSeedPhraseModel {
    private static let mnemonicLogger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.preview-seed-phrase-model")

    /// Generate a BIP-39 mnemonic of `newWalletWordCount` words (12 or 24,
    /// per the user's pick; anything else falls back to the 12-word default)
    /// via SwiftDashSDK's Rust FFI. Persistence is deferred to the async
    /// `SwiftDashSDKHost.createOrImportWallet` path; see
    /// `getOrCreateNewWallet`'s call site for the surrounding flow.
    @objc(generateAndStoreMnemonic)
    func generateAndStoreMnemonic() -> String? {
        let length = RecoveryPhraseLength(rawValue: Int(newWalletWordCount)) ?? .default
        do {
            let mnemonic = try Mnemonic.generate(wordCount: length.wordCount)
            Self.mnemonicLogger.info("generated \(length.rawValue, privacy: .public)-word mnemonic")
            return mnemonic
        } catch {
            Self.mnemonicLogger.error("generateAndStoreMnemonic failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Read the ACTIVE wallet's mnemonic from SwiftDashSDK's `WalletStorage`,
    /// resolved via the per-network active-wallet registry
    /// (`WalletEnvironment.activeWalletId`, seeded on wallet create/start/
    /// switch). Falls back to the sole stored wallet on pre-registry installs.
    /// Returns nil if no mnemonic is stored yet (migration deferred, async
    /// creation in flight) — or if several wallets exist and none matches the
    /// registry: showing ANOTHER wallet's phrase would have the user back up
    /// the wrong words, so an empty screen is the safer failure.
    @objc(readStoredMnemonic)
    func readStoredMnemonic() -> String? {
        do {
            let storage = WalletStorage()
            let walletIds = try storage.listWalletIdsWithMnemonic()
            let activeId = WalletEnvironment.activeWalletId(for: WalletEnvironment.networkKind)
            let walletId: Data
            if let activeId, walletIds.contains(activeId) {
                walletId = activeId
            } else if walletIds.count == 1, let only = walletIds.first {
                walletId = only
            } else {
                Self.mnemonicLogger.error("readStoredMnemonic: active wallet not resolvable among \(walletIds.count, privacy: .public) stored mnemonic(s)")
                return nil
            }
            return try storage.retrieveMnemonic(for: walletId)
        } catch {
            Self.mnemonicLogger.error("readStoredMnemonic failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

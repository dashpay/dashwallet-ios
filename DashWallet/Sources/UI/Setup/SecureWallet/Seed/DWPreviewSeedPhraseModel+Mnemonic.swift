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

    /// Generate a 12-word BIP-39 mnemonic via SwiftDashSDK's Rust FFI.
    /// Persistence is deferred to the async `SwiftDashSDKHost.createOrImportWallet`
    /// path; see `getOrCreateNewWallet`'s call site for the surrounding
    /// flow.
    @objc(generateAndStoreMnemonic)
    func generateAndStoreMnemonic() -> String? {
        do {
            let mnemonic = try Mnemonic.generate(wordCount: 12)
            Self.mnemonicLogger.info("generated 12-word mnemonic")
            return mnemonic
        } catch {
            Self.mnemonicLogger.error("generateAndStoreMnemonic failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Read the mnemonic of the first wallet known to SwiftDashSDK's
    /// `WalletStorage`. Returns nil if no wallet has stored a mnemonic
    /// yet (e.g. migration deferred, async creation still in flight).
    @objc(readStoredMnemonic)
    func readStoredMnemonic() -> String? {
        do {
            let storage = WalletStorage()
            let walletIds = try storage.listWalletIdsWithMnemonic()
            guard let walletId = walletIds.first else { return nil }
            return try storage.retrieveMnemonic(for: walletId)
        } catch {
            Self.mnemonicLogger.error("readStoredMnemonic failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

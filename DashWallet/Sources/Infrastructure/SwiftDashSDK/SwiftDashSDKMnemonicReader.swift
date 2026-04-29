//
//  SwiftDashSDKMnemonicReader.swift
//  DashWallet
//
//  Thin Obj-C bridge for reading the mnemonic from SwiftDashSDK's
//  WalletStorage at runtime. Used by DWPreviewSeedPhraseModel for
//  the Settings → View Recovery Phrase path.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKMnemonicReader)
final class SwiftDashSDKMnemonicReader: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.mnemonic-reader")

    /// Read the mnemonic from SwiftDashSDK's WalletStorage.
    /// Returns nil if the mnemonic isn't stored yet.
    /// Never throws, never crashes; errors logged to os.log.
    @objc(readMnemonic)
    static func readMnemonic() -> String? {
        do {
            let storage = WalletStorage()
            let walletIds = try storage.listWalletIdsWithMnemonic()
            guard let walletId = walletIds.first else { return nil }
            return try storage.retrieveMnemonic(for: walletId)
        } catch {
            logger.error("readMnemonic failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

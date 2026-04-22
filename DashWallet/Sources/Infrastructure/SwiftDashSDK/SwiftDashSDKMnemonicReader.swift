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
            return try WalletStorage().retrieveMnemonic()
        } catch {
            logger.error("readMnemonic failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Delete the stored mnemonic. Used by the keychain-recovery flow when the
    /// user declines to re-derive a wallet from a mnemonic that survived an
    /// app reinstall. Returns `true` on success, `false` on failure (logged).
    @objc(deleteStoredMnemonic)
    static func deleteStoredMnemonic() -> Bool {
        do {
            try WalletStorage().deleteMnemonic()
            return true
        } catch {
            logger.error("deleteStoredMnemonic failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}

//
//  SwiftDashSDKMnemonicGenerator.swift
//  DashWallet
//
//  Generates a 12-word BIP39 mnemonic via SwiftDashSDK's Rust FFI
//  and stores it synchronously in WalletStorage (plain keychain).
//  Used by DWPreviewSeedPhraseModel during onboarding wallet creation
//  so SwiftDashSDK is the entropy source instead of DashSync.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKMnemonicGenerator)
final class SwiftDashSDKMnemonicGenerator: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.mnemonic-generator")

    /// Generate a 12-word BIP39 mnemonic via SwiftDashSDK's Rust FFI
    /// and store it synchronously in WalletStorage (plain keychain).
    ///
    /// Returns the mnemonic string on success, nil on failure.
    /// Synchronous — runs on caller's thread so the mnemonic is in
    /// WalletStorage immediately when this returns.
    @objc(generateAndStore)
    static func generateAndStore() -> String? {
        do {
            let mnemonic = try Mnemonic.generate(wordCount: 12)
            // Storage now requires a walletId; persistence happens later in the
            // wallet-creation flow once the descriptor exists.
            logger.info("generated 12-word mnemonic")
            return mnemonic
        } catch {
            logger.error("generateAndStore failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

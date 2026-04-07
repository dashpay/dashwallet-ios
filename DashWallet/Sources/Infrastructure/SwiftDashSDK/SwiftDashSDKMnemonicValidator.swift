//
//  SwiftDashSDKMnemonicValidator.swift
//  DashWallet
//
//  BIP-39 mnemonic phrase validation adapter — Stage 1 (Flipped).
//
//  Calls both DashSync and SwiftDashSDK on every invocation, returns
//  SwiftDashSDK's result (now authoritative), and continues to log any
//  disagreements via os.log (subsystem org.dashfoundation.dash,
//  category swift-sdk-migration.mnemonic-validator).
//
//  Stage progression:
//    Stage 0 — Shadow:  call both, return DashSync, log mismatches
//    Stage 1 — Flipped: call both, return SwiftDashSDK, log mismatches (current)
//    Stage 2 — Solo:    drop the parallel DashSync call entirely
//    Stage 3 — Done:    retire this file, inline at the call site (deferred)
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKMnemonicValidator)
final class SwiftDashSDKMnemonicValidator: NSObject {

    private static let logger = Logger(subsystem: "org.dashfoundation.dash",
                                       category: "swift-sdk-migration.mnemonic-validator")

    /// Validates a BIP-39 mnemonic phrase. Stage 1 returns SwiftDashSDK's result.
    @objc(phraseIsValid:)
    static func phraseIsValid(_ phrase: String?) -> Bool {
        guard let phrase = phrase, !phrase.isEmpty else {
            return false
        }

        let dashSyncResult = DSBIP39Mnemonic.sharedInstance()?.phraseIsValid(phrase) ?? false
        let sdkResult = Mnemonic.validate(phrase)

        if sdkResult != dashSyncResult {
            logger.warning("phraseIsValid mismatch: dashSync=\(dashSyncResult, privacy: .public) sdk=\(sdkResult, privacy: .public)")
        }

        return sdkResult  // Stage 2 will drop the DashSync parallel call entirely
    }
}

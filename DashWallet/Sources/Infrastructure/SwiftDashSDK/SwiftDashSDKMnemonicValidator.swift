//
//  SwiftDashSDKMnemonicValidator.swift
//  DashWallet
//
//  BIP-39 mnemonic phrase validation adapter — SwiftDashSDK is the sole authoritative source.
//
//  Stage history:
//    Stage 0 — Shadow:  called both libraries, returned DashSync result, logged mismatches
//    Stage 1 — Flipped: called both libraries, returned SwiftDashSDK result, logged mismatches
//    Stage 2 — Solo:    only SwiftDashSDK is called (current)
//    Stage 3 — Done:    adapter retired, call sites use SwiftDashSDK directly (future)
//
//  The DashSync parallel call was removed after Stage 1 baked clean: a manual smoke
//  test in the Restore Wallet flow produced zero `phraseIsValid mismatch` warnings.
//  Both implementations follow the BIP-39 RFC against the same 2048-word English
//  list, so any divergence would be a bug in one side rather than an edge case to
//  design around.
//

import Foundation
import SwiftDashSDK

@objc(DWSwiftDashSDKMnemonicValidator)
final class SwiftDashSDKMnemonicValidator: NSObject {

    /// Validates a BIP-39 mnemonic phrase using SwiftDashSDK.
    @objc(phraseIsValid:)
    static func phraseIsValid(_ phrase: String?) -> Bool {
        guard let phrase = phrase, !phrase.isEmpty else {
            return false
        }
        return Mnemonic.validate(phrase)
    }
}

//
//  DWRecoverModel+Mnemonic.swift
//  DashWallet
//
//  Co-located Swift extension that bridges Obj-C `DWRecoverModel.phraseIsValid:`
//  to SwiftDashSDK's `Mnemonic.validate(_:)`. Replaces the standalone
//  `DWSwiftDashSDKMnemonicValidator` adapter — migration row #4 (Mnemonic
//  validation) is now ✅ Done at the call-site level.
//

import Foundation
import SwiftDashSDK

extension DWRecoverModel {
    @objc(phraseIsValid:)
    func phraseIsValid(_ phrase: String?) -> Bool {
        guard let phrase, !phrase.isEmpty else { return false }
        return Mnemonic.validate(phrase)
    }
}

//
//  DWRecoverModel+Mnemonic.swift
//  DashWallet
//
//  Co-located Swift extension bridging Obj-C `DWRecoverModel`'s mnemonic
//  helpers (`phraseIsValid:`, `cleanupPhrase:`, `normalizePhrase:`,
//  `wordIsLocal:`, `wordIsValid:`) to SwiftDashSDK's `Mnemonic`. Replaces the
//  DashSync `DSBIP39Mnemonic` calls that previously lived in `DWRecoverModel.m`
//  — migration row #4 (validation) plus its sister word helpers, now on
//  SwiftDashSDK. Phrase-repair (`DWPhraseRepairViewController`) stays on
//  DashSync (no SDK equivalent).
//

import Foundation
import SwiftDashSDK

extension DWRecoverModel {
    @objc(phraseIsValid:)
    func phraseIsValid(_ phrase: String?) -> Bool {
        guard let phrase, !phrase.isEmpty else { return false }
        return Mnemonic.validate(phrase)
    }

    @objc(cleanupPhrase:)
    func cleanupPhrase(_ phrase: String) -> String {
        Mnemonic.cleanupPhrase(phrase)
    }

    @objc(normalizePhrase:)
    func normalizePhrase(_ phrase: String?) -> String? {
        guard let phrase else { return nil }
        return Mnemonic.normalizePhrase(phrase)
    }

    @objc(wordIsLocal:)
    func wordIsLocal(_ word: String) -> Bool {
        Mnemonic.wordIsLocal(word)
    }

    @objc(wordIsValid:)
    func wordIsValid(_ word: String) -> Bool {
        Mnemonic.wordIsValid(word)
    }
}

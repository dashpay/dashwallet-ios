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

// Cached BIP-39 wordlist membership sets, composed once from the SDK's
// `Mnemonic.wordList` primitive. The SDK used to own these checks
// (`wordIsValid` / `wordIsInLanguage`); it now exposes only the raw wordlists,
// so the recover flow builds the policy here:
//   • the any-language union backs `wordIsValid:` (a word the user typed is
//     "valid" if it appears in *any* supported language's list — strictly more
//     lenient than DashSync's 7-language subset, still correct: the recover
//     flow validates the full phrase per language afterwards);
//   • the English list backs `wordIsLocal:` (English is the default language).
// Both are global `let`s — initialized lazily and thread-safely on first
// access (the Swift runtime guarantees once-only init). Callers normalize the
// word first (membership here is exact, matching the old FFI behavior).
private let dwEnglishWordSet: Set<String> = Set(Mnemonic.wordList(language: .english))

private let dwAllLanguagesWordSet: Set<String> = MnemonicLanguage.allCases
    .reduce(into: Set<String>()) { union, language in
        union.formUnion(Mnemonic.wordList(language: language))
    }

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
        // "Local" is the recover flow's default language (English): membership
        // in the cached English wordlist (the word is normalized by the caller).
        dwEnglishWordSet.contains(word)
    }

    @objc(wordIsValid:)
    func wordIsValid(_ word: String) -> Bool {
        // Valid if the (normalized) word appears in any supported language's
        // wordlist — the union DashSync's `wordIsValid:` used to compute.
        dwAllLanguagesWordSet.contains(word)
    }
}

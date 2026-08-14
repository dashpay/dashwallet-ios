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
import OSLog
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

private let dwRecoverLogger = Logger(
    subsystem: "org.dashfoundation.dash",
    category: "recover-wipe")

extension DWRecoverModel {
    /// The plain-"wipe" gate: empty means "zero SDK balance AND the chain is
    /// fully synced" — an unsynced wallet can't prove it's empty, so it reads
    /// as non-empty (fail-closed; an exact recovery phrase remains available).
    /// Replaces the DashSync read (`wallet.balance` + frozen
    /// `lastSyncBlockTimestamp`/`lastSyncBlockHeight`), which post-M6 never
    /// advanced and made this permanently false — the plain-"wipe" phrase was
    /// always refused. The literal shortcut is additionally permitted only
    /// when Keychain proves there is exactly one stored wallet id AND the
    /// active network is mainnet: the published balance is active-wallet,
    /// active-network state, so it can prove neither another wallet's balance
    /// nor the same seed's mainnet balance while running on testnet. The
    /// cheap in-memory checks run first; the id count is an attributes-only
    /// Keychain enumeration (no mnemonic secrets are read). Enumeration
    /// failure denies (logged).
    @objc(isWalletEmpty)
    func isWalletEmpty() -> Bool {
        guard let balance = SwiftDashSDKWalletState.shared.balance,
              balance.total == 0,
              SyncingActivityMonitor.shared.state == .syncDone,
              WalletEnvironment.isMainnet else { return false }
        do {
            return try SwiftDashSDKHost.persistedWalletIdCount() == 1
        } catch {
            dwRecoverLogger.error("plain-wipe gate: wallet-id count failed; refusing: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// The plain-"wipe" shortcut is mainnet-only (see `isWalletEmpty`). Lets
    /// the wipe screen explain a testnet denial honestly instead of claiming
    /// the wallet is not empty.
    @objc(plainWipeAllowedOnCurrentNetwork)
    func plainWipeAllowedOnCurrentNetwork() -> Bool {
        WalletEnvironment.isMainnet
    }

    /// True when more than one wallet id is stored — the reason the plain
    /// "wipe" shortcut (and a single wallet's phrase) can be refused. Lets
    /// the wipe screen explain a denial honestly instead of blaming balance
    /// or the phrase. Enumeration failure reads as false (the generic denial
    /// copy applies; logged).
    @objc(hasMultipleStoredWalletIds)
    func hasMultipleStoredWalletIds() -> Bool {
        do {
            return try SwiftDashSDKHost.persistedWalletIdCount() > 1
        } catch {
            dwRecoverLogger.error("wallet-id count failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Authorizes the GLOBAL wipe with a recovery phrase: the typed phrase,
    /// normalized, must match EVERY stored SDK mnemonic
    /// (`SwiftDashSDKHost.allStoredMnemonicsMatch`). Multiple network-scoped
    /// ids for the same seed are allowed; a distinct second wallet blocks
    /// authorization. Enumeration or any individual read failure also blocks
    /// it (logged), so a partially readable Keychain can never be mistaken
    /// for the complete wallet set. Phrase→seed is deterministic, but no key
    /// material is derived here. The support acknowledgement is deliberately
    /// isolated in `DWRecoverAction_SupportWipe`; the regular caller routes the
    /// literal `DW_WIPE` shortcut to `isWalletEmpty` before this check.
    @objc(canWipeWithPhrase:)
    func canWipeWithPhrase(_ phrase: String) -> Bool {
        do {
            return try SwiftDashSDKHost.allStoredMnemonicsMatch(phrase: phrase)
        } catch {
            dwRecoverLogger.error("wipe-with-phrase: keychain read failed; refusing: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Matches the localized support-only destructive acknowledgement after
    /// applying the same Unicode canonicalization to both strings. The raw
    /// text must reach this method before mnemonic cleanup, which deliberately
    /// strips punctuation. `normalizePhrase` performs NFKD, lowercasing, and
    /// whitespace collapsing without discarding diacritics or punctuation.
    @objc(isWipeAcceptancePhrase:)
    func isWipeAcceptancePhrase(_ phrase: String) -> Bool {
        guard action == .supportWipe else { return false }
        return Self.wipeAcceptancePhraseMatches(
            phrase,
            expectedPhrase: wipeAcceptPhrase())
    }

    static func wipeAcceptancePhraseMatches(
        _ phrase: String,
        expectedPhrase: String
    ) -> Bool {
        Mnemonic.normalizePhrase(phrase) == Mnemonic.normalizePhrase(expectedPhrase)
    }

    /// True when `phrase` matches at least one readable stored mnemonic — a
    /// non-destructive ownership signal. Backs the forgot-PIN check and the
    /// wipe screen's honest-denial copy (the typed phrase matches one wallet
    /// of several, so the set-wide wipe authorization refused it).
    @objc(phraseMatchesAnyStoredWallet:)
    func phraseMatchesAnyStoredWallet(_ phrase: String) -> Bool {
        SwiftDashSDKHost.anyStoredMnemonicMatches(phrase: phrase)
    }

    /// Non-destructive forgot-PIN ownership check. Any one persisted wallet's
    /// phrase is sufficient because resetting the app-global PIN keeps every
    /// wallet intact. This deliberately differs from `canWipeWithPhrase`,
    /// whose global destructive action must account for the complete set.
    @objc(canResetPinWithPhrase:)
    func canResetPinWithPhrase(_ phrase: String) -> Bool {
        phraseMatchesAnyStoredWallet(phrase)
    }

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

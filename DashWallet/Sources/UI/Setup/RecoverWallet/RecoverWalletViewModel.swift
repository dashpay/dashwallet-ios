//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI

// MARK: - RecoverPhraseChecking

/// What the recovery phrase screen asks of the wallet. `DWRecoverModel`
/// answers it; tests stand in for it.
protocol RecoverPhraseChecking: AnyObject {
    var action: DWRecoverAction { get }
    func hasWallet() -> Bool
    func hasPinSet() -> Bool
    func isWipeAcceptancePhrase(_ phrase: String) -> Bool
    func cleanupPhrase(_ phrase: String) -> String
    func normalizePhrase(_ phrase: String?) -> String?
    func wordIsValid(_ word: String) -> Bool
    func phraseIsValid(_ phrase: String?) -> Bool
    func canResetPinWithPhrase(_ phrase: String) -> Bool
    func isWalletEmpty() -> Bool
    func hasMultipleStoredWalletIds() -> Bool
    func plainWipeAllowedOnCurrentNetwork() -> Bool
    func canWipeWithPhrase(_ phrase: String) -> Bool
    func phraseMatchesAnyStoredWallet(_ phrase: String) -> Bool
    func wipeWallet()
}

extension DWRecoverModel: RecoverPhraseChecking { }

// MARK: - RecoverPhraseEvaluator

/// Decides what an entered phrase leads to, for each of the screen's
/// actions: recovering a wallet, wiping it, resetting the PIN, or the
/// support-assisted wipe.
struct RecoverPhraseEvaluator {
    enum Outcome: Equatable {
        /// Too few words to act on.
        case none
        case recover(phrase: String)
        case verifiedForPinReset
        /// Ask to confirm wiping.
        case confirmWipe
        /// More than one word is not a recovery phrase word.
        case incorrectWord(String)
        /// One word is not a recovery phrase word: offer to find it.
        case offerWordRepair(incorrectWord: String, phrase: String)
        /// 10 or 11 words: offer to find the missing ones.
        case offerMissingWordsRepair(words: [String])
        case invalidWordCount
        case badPhrase
        case wipeNotAllowed
        case phraseMismatch
        case multipleWallets
        case wipeShortcutUnavailableOnTestnet
    }

    struct Evaluation: Equatable {
        /// The phrase as cleaned up, to show in place of what was typed.
        var cleanedPhrase: String?
        var outcome: Outcome
    }

    let model: RecoverPhraseChecking

    func evaluate(_ rawPhrase: String) -> Evaluation {
        let count = (rawPhrase as NSString).wordsCount
        let isSupportAcceptancePhrase = model.isWipeAcceptancePhrase(rawPhrase)
        if count < 10 && !isSupportAcceptancePhrase {
            return Evaluation(outcome: .none)
        }

        // The support acknowledgement is not a mnemonic. It is recognised as
        // typed, before cleanup strips punctuation (the comma in Polish, for
        // one) or the word check rejects it.
        if isSupportAcceptancePhrase {
            return Evaluation(outcome: wipe(with: rawPhrase))
        }

        var phrase = rawPhrase
        var cleanedPhrase: String?
        if phrase != DW_WIPE_STRONG {
            phrase = model.cleanupPhrase(phrase)
            if !rawPhrase.hasPrefix(DW_WATCH) && phrase != rawPhrase {
                cleanedPhrase = phrase
            }
            phrase = model.normalizePhrase(phrase) ?? phrase
        }

        let words = Self.words(of: phrase)
        var incorrectWord: String?
        var incorrectWordCount = 0
        for word in words where !model.wordIsValid(word) {
            if incorrectWord == nil {
                incorrectWord = word
            }
            incorrectWordCount += 1
        }

        let action = model.action
        let outcome: Outcome
        if action == .wipe && (phrase == DW_WIPE || phrase == DW_WIPE_STRONG) {
            outcome = wipe(with: phrase)
        }
        else if let incorrectWord, incorrectWordCount > 1 {
            outcome = .incorrectWord(incorrectWord)
        }
        else if let incorrectWord, incorrectWordCount == 1, action == .recover {
            outcome = .offerWordRepair(incorrectWord: incorrectWord, phrase: phrase)
        }
        else if action == .recover
            && (words.count < DW_PHRASE_MIN_LENGTH || words.count % DW_PHRASE_MULTIPLE != 0) {
            outcome = words.count == 10 || words.count == 11
                ? .offerMissingWordsRepair(words: words)
                : .invalidWordCount
        }
        else if !model.phraseIsValid(phrase) {
            outcome = .badPhrase
        }
        else if model.hasWallet() {
            outcome = wipe(with: phrase)
        }
        else if action == .recover {
            outcome = .recover(phrase: phrase)
        }
        else {
            outcome = wipe(with: phrase)
        }
        return Evaluation(cleanedPhrase: cleanedPhrase, outcome: outcome)
    }

    /// Whether the phrase entered so far is enough to try.
    func canSubmit(_ phrase: String) -> Bool {
        (phrase as NSString).wordsCount >= 10 || model.isWipeAcceptancePhrase(phrase)
    }

    private func wipe(with phrase: String) -> Outcome {
        let action = model.action

        // Forgot PIN only proves ownership: a phrase matching a stored wallet
        // resets the PIN and keeps the wallet. Anything else, the wipe words
        // included, is a mismatch. No wallet is ever erased here.
        if action == .resetPin {
            return model.canResetPinWithPhrase(phrase) ? .verifiedForPinReset : .phraseMismatch
        }

        if action == .wipe && phrase == DW_WIPE {
            if model.isWalletEmpty() {
                return .confirmWipe
            }
            if model.hasMultipleStoredWalletIds() {
                // Refused because of how many wallets are stored, not their
                // balance or sync: "not empty" would be untrue.
                return .multipleWallets
            }
            if !model.plainWipeAllowedOnCurrentNetwork() {
                // A zero testnet balance cannot prove the mainnet balance.
                return .wipeShortcutUnavailableOnTestnet
            }
            return .wipeNotAllowed
        }

        if (action == .wipe && phrase == DW_WIPE_STRONG) || model.isWipeAcceptancePhrase(phrase) {
            return .confirmWipe
        }
        if model.canWipeWithPhrase(phrase) {
            return .confirmWipe
        }
        if model.phraseMatchesAnyStoredWallet(phrase) {
            // It matches a stored wallet, just not all of them: "doesn't
            // match" would be untrue and alarming.
            return .multipleWallets
        }
        return .phraseMismatch
    }

    /// The words of a phrase, split with the allocator that wipes memory
    /// when the strings are released.
    private static func words(of phrase: String) -> [String] {
        guard let words = CFStringCreateArrayBySeparatingStrings(DWSecureAllocator().takeUnretainedValue(),
                                                                  phrase as CFString,
                                                                  " " as CFString) as? [String]
        else {
            return phrase.components(separatedBy: " ")
        }
        return words
    }
}

// MARK: - RecoverWalletViewModel

/// The recovery phrase screen: Recover Wallet, Wipe Wallet, Reset PIN, or the
/// support-assisted wipe of all wallets.
@MainActor
final class RecoverWalletViewModel: ObservableObject {
    struct Alert: Identifiable {
        struct Action {
            enum Role {
                case cancel
                case destructive
                case plain
            }

            var title: String
            var role: Role = .plain
            var handler: () -> Void = { }
        }

        let id = UUID()
        var title: String?
        var message: String?
        var actions: [Action]
    }

    @Published var phrase = ""
    @Published var alert: Alert?
    @Published var isWipeConfirmationPresented = false
    @Published var repair: PhraseRepairViewModel?
    /// Bumped to put the keyboard back on the phrase.
    @Published private(set) var focusRequests = 0
    /// A word of the phrase to select, with a bump to apply it again.
    @Published private(set) var selection: (word: String, request: Int)?

    let action: DWRecoverAction
    let title: String
    let heading: String

    var onRecover: (DWRecoverWalletCommand) -> Void = { _ in }
    var onVerifyForPinReset: () -> Void = { }
    var onWipe: () -> Void = { }

    private let model: RecoverPhraseChecking
    private let evaluator: RecoverPhraseEvaluator
    private let wiper: RecoverWalletWiper
    private let makeRepair: @MainActor (_ phrase: String, _ incorrectWord: String?) -> PhraseRepairViewModel

    init(model: RecoverPhraseChecking,
         wiper: RecoverWalletWiper = .live,
         makeRepair: @escaping @MainActor (_ phrase: String, _ incorrectWord: String?) -> PhraseRepairViewModel = {
             PhraseRepairViewModel(phrase: $0, incorrectWord: $1)
         }) {
        self.model = model
        self.wiper = wiper
        self.makeRepair = makeRepair
        evaluator = RecoverPhraseEvaluator(model: model)
        action = model.action

        // Reset PIN proves ownership before setting a PIN. With no PIN
        // stored (a partial keychain restore, an interrupted setup) there is
        // nothing to reset, so it says "set".
        let hasPinSet = model.hasPinSet()
        switch model.action {
        case .recover:
            title = String(localized: "Recover Wallet", comment: "")
        case .wipe:
            title = String(localized: "Wipe Wallet", comment: "")
        case .resetPin:
            title = hasPinSet
                ? String(localized: "Reset PIN", comment: "")
                : String(localized: "Set PIN", comment: "")
        case .supportWipe:
            title = String(localized: "Wipe All Wallets", comment: "")
        @unknown default:
            title = String(localized: "Recover Wallet", comment: "")
        }

        if model.action == .resetPin {
            heading = hasPinSet
                ? String(localized: "Enter your recovery phrase to reset your PIN", comment: "")
                : String(localized: "Enter your recovery phrase to set a new PIN", comment: "")
        } else {
            heading = String(localized: "Enter Recovery Phrase", comment: "")
        }
    }

    var canContinue: Bool {
        evaluator.canSubmit(phrase)
    }

    func focus() {
        focusRequests += 1
    }

    // MARK: Continue

    func submit() {
        let evaluation = evaluator.evaluate(phrase)
        if let cleanedPhrase = evaluation.cleanedPhrase {
            phrase = cleanedPhrase
        }
        handle(evaluation.outcome)
    }

    private func handle(_ outcome: RecoverPhraseEvaluator.Outcome) {
        switch outcome {
        case .none:
            break

        case .recover(let phrase):
            onRecover(DWRecoverWalletCommand(phrase: phrase))

        case .verifiedForPinReset:
            onVerifyForPinReset()

        case .confirmWipe:
            isWipeConfirmationPresented = true

        case .incorrectWord(let word):
            selection = (word, (selection?.request ?? 0) + 1)
            showMessage(String(format: String(localized: "\"%@\" is not a recovery phrase word", comment: ""), word))

        case .offerWordRepair(let word, let phrase):
            offerRepair(
                message: String(format: String(localized: "\"%@\" is not a recovery phrase word. Would you like to try to recover the correct word that should be in its place?", comment: ""), word),
                phrase: phrase,
                incorrectWord: word
            )

        case .offerMissingWordsRepair(let words):
            let message = words.count == 10
                ? String(localized: "It would seem like you are attempting to restore your wallet a using a 12 word recovery phrase, however you have only entered 10 words, would you like to automatically recover missing words? This might take around an hour. We recommend plugging in your device.", comment: "")
                : String(localized: "It would seem like you are attempting to restore your wallet a using a 12 word recovery phrase, however you have only entered 11 words, would you like to automatically recover the missing word?", comment: "")
            offerRepair(message: message, phrase: words.joined(separator: " "), incorrectWord: nil)

        case .invalidWordCount:
            showMessage(String(localized: "Recovery phrase must have 12, 15, 18, 21 or 24 words", comment: ""))

        case .badPhrase:
            showMessage(String(localized: "Bad recovery phrase", comment: ""))

        case .wipeNotAllowed:
            showMessage(String(localized: "Enter the recovery phrase to continue.", comment: ""),
                        title: String(localized: "This wallet is not empty or sync has not finished, you may not wipe it without the recovery phrase", comment: ""))

        case .phraseMismatch:
            showMessage(String(localized: "Recovery phrase doesn't match", comment: ""))

        case .multipleWallets:
            showMessage(String(localized: "A single wallet's recovery phrase cannot authorize deleting multiple different wallets.", comment: ""),
                        title: String(localized: "Multiple wallets are stored on this device", comment: ""))

        case .wipeShortcutUnavailableOnTestnet:
            showMessage(String(localized: "A zero testnet balance cannot prove this wallet is empty on mainnet. Enter the recovery phrase to continue.", comment: ""),
                        title: String(localized: "The \"wipe\" shortcut is not available on testnet", comment: ""))
        }
    }

    private func showMessage(_ message: String, title: String? = nil) {
        alert = Alert(title: title, message: message, actions: [
            .init(title: String(localized: "OK", comment: ""), role: .cancel) { [weak self] in self?.focus() },
        ])
    }

    // MARK: Phrase repair

    private func offerRepair(message: String, phrase: String, incorrectWord: String?) {
        alert = Alert(title: nil, message: message, actions: [
            .init(title: String(localized: "Cancel", comment: ""), role: .cancel) { [weak self] in self?.focus() },
            .init(title: String(localized: "Recover", comment: "")) { [weak self] in
                self?.startRepair(phrase: phrase, incorrectWord: incorrectWord)
            },
        ])
    }

    private func startRepair(phrase: String, incorrectWord: String?) {
        let repair = makeRepair(phrase, incorrectWord)
        repair.onFinish = { [weak self] words in
            self?.apply(repairedWords: words, incorrectWord: incorrectWord)
            self?.repair = nil
        }
        self.repair = repair
        repair.start()
    }

    /// Puts the found word in place of the wrong one, or after the phrase
    /// when words were missing.
    func apply(repairedWords words: [String], incorrectWord: String?) {
        guard let word = words.first else { return }
        if let incorrectWord {
            phrase = phrase.replacingOccurrences(of: incorrectWord, with: word, options: .caseInsensitive)
        } else {
            phrase += " " + word
        }
    }

    // MARK: Wipe

    var wipeTitle: String {
        action == .supportWipe
            ? String(localized: "Delete All", comment: "")
            : String(localized: "Wipe", comment: "")
    }

    func cancelWipe() {
        focus()
    }

    func wipe() {
        let isSupportWipe = action == .supportWipe
        let progress = isSupportWipe
            ? String(localized: "Deleting All Wallets…", comment: "")
            : String(localized: "Deleting Wallet…", comment: "")

        // The progress shows in the app-wide lifecycle overlay. Refused when
        // another wallet operation is under way: never start a second wipe,
        // and never swallow the refusal of a confirmed destructive action.
        guard wiper.begin(progress) else {
            showMessage(String(localized: "Another wallet operation is already in progress.", comment: ""))
            return
        }

        model.wipeWallet()

        let wiper = wiper
        wiper.waitForPendingWipe { [weak self] succeeded in
            // The overlay goes first, whatever happened to this screen.
            wiper.finish()
            guard let self else { return }
            if succeeded {
                self.onWipe()
            } else {
                self.showWipeFailure(isSupportWipe: isSupportWipe)
            }
        }
    }

    private func showWipeFailure(isSupportWipe: Bool) {
        if isSupportWipe {
            alert = Alert(
                title: String(localized: "Couldn’t Delete All Wallets", comment: ""),
                message: String(localized: "Not all wallets could be deleted. Please try again.", comment: ""),
                actions: [
                    .init(title: String(localized: "Cancel", comment: ""), role: .cancel) { [weak self] in self?.focus() },
                    .init(title: String(localized: "Retry", comment: "")) { [weak self] in
                        self?.isWipeConfirmationPresented = true
                    },
                ]
            )
        } else {
            showMessage(String(localized: "The wallet is still stored on this device. Please try again.", comment: ""),
                        title: String(localized: "Couldn’t Delete Wallet", comment: ""))
        }
    }
}

// MARK: - RecoverWalletWiper

/// The app-wide wipe the screen drives once a wipe is confirmed.
struct RecoverWalletWiper {
    /// Shows the progress overlay; false when another wallet operation is
    /// under way.
    var begin: @MainActor (_ title: String) -> Bool
    var waitForPendingWipe: @MainActor (_ completion: @escaping @MainActor (Bool) -> Void) -> Void
    var finish: @MainActor () -> Void

    static var live: RecoverWalletWiper {
        RecoverWalletWiper(
            begin: { WalletLifecycleOverlayBridge.beginWiping(title: $0) },
            waitForPendingWipe: { completion in
                SwiftDashSDKWalletWiper.waitForPendingWipe { succeeded in
                    Task { @MainActor in completion(succeeded) }
                }
            },
            finish: { WalletLifecycleOverlayBridge.finishWiping() }
        )
    }
}

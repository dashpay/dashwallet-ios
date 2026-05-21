//
//  Created by Roman Chornyi
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

import Combine
import SwiftUI
import UIKit

#if SEED_INPUT_DIAGNOSTICS
// TEMPORARY: Seed input diagnostics for targeted TestFlight troubleshooting.
// Enable only in dedicated diagnostic builds and disable/remove before release.
private enum RecoverSeedPhraseControllerDebugLog {
    static let isEnabled = true

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        // TODO: Verify this NSLog stream is included in logs received from
        // remote TestFlight users for this diagnostic campaign.
        NSLog("[RecoverSeedController] %@", message())
    }
}
#endif

/// Observable state driving the bridged SwiftUI seed-entry view. Mutating any
/// `@Published` property re-renders the hosted view; mutating `phrase` via
/// `setPhrase(_:notifyHandler:)` lets ObjC update text without emitting a
/// change notification (mirroring direct `UITextView.text =` writes in the
/// legacy `DWRecoverContentView`).
final class RecoverSeedPhraseInputState: ObservableObject {
    @Published var title: String = ""
    @Published var phrase: String = ""
    @Published var focusToken: Int = 0
    @Published var selectionToken: Int = 0
    /// Substring that should be selected next time `selectionToken` advances.
    /// Held alongside the token so we can deliver both atomically through the
    /// SwiftUI body without spawning extra `@Published` updates.
    var selectionSubstring: String?

    /// Invoked when the user mutates the seed text through the SwiftUI binding.
    var onPhraseChange: ((String) -> Void)?
    /// Invoked when the user presses Return / Done.
    var onSubmit: (() -> Void)?

    func requestFocus() {
        focusToken &+= 1
    }

    /// Asks the embedded UITextView to highlight the first (case-insensitive)
    /// occurrence of `substring`. Matches the legacy
    /// `textView.selectedRange = [text.lowercaseString rangeOfString:word]`.
    func requestSelection(ofFirstOccurrenceOf substring: String) {
        selectionSubstring = substring
        selectionToken &+= 1
    }

    /// Replaces `phrase` from outside (e.g. ObjC append/replace operations).
    /// `notifyHandler` controls whether `onPhraseChange` is invoked — the
    /// legacy text-view writes did not call the delegate, so we default to
    /// `false`.
    func setPhrase(_ newValue: String, notifyHandler: Bool = false) {
        phrase = newValue
        if notifyHandler {
            onPhraseChange?(newValue)
        }
    }
}

/// Internal SwiftUI host that observes the state object and forwards changes
/// into the existing `RecoverSeedPhraseInputView`. Kept private — ObjC talks
/// to `RecoverSeedPhraseInputController` instead.
private struct BridgedRecoverSeedPhraseInputView: View {
    @ObservedObject var state: RecoverSeedPhraseInputState

    var body: some View {
        RecoverSeedPhraseInputView(
            title: state.title,
            phrase: Binding(
                get: { state.phrase },
                set: { newValue in
                    // Only mutations originating from the SwiftUI view
                    // (user typing / paste) flow through this setter, so it
                    // is the right place to broadcast `onPhraseChange`.
                    state.phrase = newValue
                    state.onPhraseChange?(newValue)
                }
            ),
            onSubmit: { state.onSubmit?() },
            focusToken: state.focusToken,
            selectionToken: state.selectionToken,
            selectionSubstring: state.selectionSubstring
        )
    }
}

/// ObjC-facing bridge that hosts the SwiftUI seed-entry view inside the
/// legacy `DWRecoverContentView`. In Stage 3 it owns the recover/wipe seed
/// phrase decision logic while keeping `RecoverSeedPhraseInputView`
/// presentation-only.
@objc protocol DWRecoverSeedPhraseInputControllerDelegate: AnyObject {
    func recoverSeedPhraseInputController(_ controller: RecoverSeedPhraseInputController,
                                          phraseDidChange phrase: String)
    func recoverSeedPhraseInputController(_ controller: RecoverSeedPhraseInputController,
                                          showIncorrectWord incorrectWord: String)
    func recoverSeedPhraseInputController(_ controller: RecoverSeedPhraseInputController,
                                          offerToReplaceIncorrectWord incorrectWord: String,
                                          inPhrase phrase: String)
    func recoverSeedPhraseInputController(_ controller: RecoverSeedPhraseInputController,
                                          usedWordsHaveInvalidCount words: NSArray)
    func recoverSeedPhraseInputControllerBadRecoveryPhrase(_ controller: RecoverSeedPhraseInputController)
    func recoverSeedPhraseInputController(_ controller: RecoverSeedPhraseInputController,
                                          didRecoverWalletWith phrase: String)
    func recoverSeedPhraseInputControllerPerformWipe(_ controller: RecoverSeedPhraseInputController)
    func recoverSeedPhraseInputControllerWipeNotAllowed(_ controller: RecoverSeedPhraseInputController)
    func recoverSeedPhraseInputControllerWipeNotAllowedPhraseMismatch(_ controller: RecoverSeedPhraseInputController)
}

@objc(DWRecoverSeedPhraseInputController)
final class RecoverSeedPhraseInputController: NSObject {
    // MARK: - Outputs

    // MARK: - State

    private let state = RecoverSeedPhraseInputState()
    @objc weak var delegate: DWRecoverSeedPhraseInputControllerDelegate?
    @objc var model: DWRecoverModel?

    // MARK: - ObjC API

    @objc var title: String {
        get { state.title }
        set { state.title = newValue }
    }

    @objc var phrase: String {
        get { state.phrase }
        // Direct ObjC writes don't notify, matching the legacy behaviour
        // where assigning to `UITextView.text` did not call the delegate.
        set {
#if SEED_INPUT_DIAGNOSTICS
            RecoverSeedPhraseControllerDebugLog.log(
                "external phrase set (property): chars=\(newValue.count), words=\((newValue as NSString).wordsCount)"
            )
#endif
            state.setPhrase(newValue, notifyHandler: false)
        }
    }

    @objc lazy var viewController: UIViewController = {
        let host = UIHostingController(
            rootView: BridgedRecoverSeedPhraseInputView(state: state)
        )
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        return host
    }()

    // MARK: - Lifecycle

    @objc override init() {
        super.init()
        state.onPhraseChange = { [weak self] newValue in
            guard let self else { return }
            self.delegate?.recoverSeedPhraseInputController(self, phraseDidChange: newValue)
        }
        state.onSubmit = { [weak self] in
            self?.continueAction()
        }
    }

    // MARK: - Methods

    @objc func activate() {
#if SEED_INPUT_DIAGNOSTICS
        RecoverSeedPhraseControllerDebugLog.log("activate()")
#endif
        state.requestFocus()
    }

    @objc func continueAction() {
        guard let model else { return }
        let phraseText = state.phrase
        guard (phraseText as NSString).wordsCount >= 10 else {
            return
        }

        autoreleasepool {
            let originalPhrase = phraseText
            var phrase = originalPhrase
            var incorrectWord: String?
            var incorrectWordCount: UInt32 = 0

            if phrase != DW_WIPE_STRONG {
                phrase = model.cleanupPhrase(phrase)

                if !originalPhrase.hasPrefix(DW_WATCH), phrase != originalPhrase {
                    // Keep legacy behavior: direct programmatic text updates
                    // should not emit `phraseDidChange`.
#if SEED_INPUT_DIAGNOSTICS
                    RecoverSeedPhraseControllerDebugLog.log(
                        "external phrase set (cleanup): chars=\(phrase.count), words=\((phrase as NSString).wordsCount)"
                    )
#endif
                    state.setPhrase(phrase, notifyHandler: false)
                }

                phrase = model.normalizePhrase(phrase) ?? phrase
            }

            let wordsArray = CFStringCreateArrayBySeparatingStrings(
                SecureAllocator(),
                phrase as CFString,
                " " as CFString
            ) as NSArray

            for case let word as String in wordsArray {
                if !model.wordIsValid(word) {
                    if incorrectWord == nil {
                        incorrectWord = word
                    }
                    incorrectWordCount &+= 1
                }
            }

            if isWipePhrase(phrase, model: model) {
                wipe(with: phrase, model: model)
            }
            else if let incorrectWord, incorrectWordCount > 1 {
                // Match legacy UX: highlight first invalid word before alert.
                state.requestSelection(ofFirstOccurrenceOf: incorrectWord)
                delegate?.recoverSeedPhraseInputController(self, showIncorrectWord: incorrectWord)
            }
            else if let incorrectWord, incorrectWordCount == 1, isRecoverAction(model) {
                delegate?.recoverSeedPhraseInputController(
                    self,
                    offerToReplaceIncorrectWord: incorrectWord,
                    inPhrase: phrase
                )
            }
            else if isRecoverAction(model) &&
                        (wordsArray.count < Int(DW_PHRASE_MIN_LENGTH) ||
                         wordsArray.count % Int(DW_PHRASE_MULTIPLE) != 0) {
                delegate?.recoverSeedPhraseInputController(self, usedWordsHaveInvalidCount: wordsArray)
            }
            else if !model.phraseIsValid(phrase) {
                delegate?.recoverSeedPhraseInputControllerBadRecoveryPhrase(self)
            }
            else if model.hasWallet() {
                wipe(with: phrase, model: model)
            }
            else if isRecoverAction(model) {
                delegate?.recoverSeedPhraseInputController(self, didRecoverWalletWith: phrase)
            }
            else {
                wipe(with: phrase, model: model)
            }
        }
    }

    @objc func appendText(_ text: String) {
        // Matches legacy `[textView.text stringByAppendingFormat:@" %@", text]`
        // exactly — including the leading space for empty initial phrases.
        let updated = state.phrase + " " + text
#if SEED_INPUT_DIAGNOSTICS
        RecoverSeedPhraseControllerDebugLog.log(
            "external phrase set (appendText): chars=\(updated.count), words=\((updated as NSString).wordsCount)"
        )
#endif
        state.setPhrase(updated, notifyHandler: false)
    }

    /// Selects the first case-insensitive occurrence of `substring` inside the
    /// embedded UITextView. Restores the highlight-the-bad-word UX from the
    /// legacy `DWRecoverTextView`.
    @objc func selectFirstOccurrence(of substring: String) {
#if SEED_INPUT_DIAGNOSTICS
        RecoverSeedPhraseControllerDebugLog.log(
            "external selection request: substringLength=\(substring.count)"
        )
#endif
        state.requestSelection(ofFirstOccurrenceOf: substring)
    }

    @objc func replaceText(_ target: String, with replacement: String) {
        let current = state.phrase
        guard !current.isEmpty else { return }
        let updated = (current as NSString).replacingOccurrences(
            of: target,
            with: replacement,
            options: [.caseInsensitive],
            range: NSRange(location: 0, length: (current as NSString).length)
        )
#if SEED_INPUT_DIAGNOSTICS
        RecoverSeedPhraseControllerDebugLog.log(
            "external phrase set (replaceText): chars=\(updated.count), words=\((updated as NSString).wordsCount)"
        )
#endif
        state.setPhrase(updated, notifyHandler: false)
    }

    // MARK: - Private

    private func isRecoverAction(_ model: DWRecoverModel) -> Bool {
        model.action == DWRecoverAction_Recover
    }

    private func isWipePhrase(_ phrase: String, model: DWRecoverModel) -> Bool {
        phrase == DW_WIPE ||
            phrase == DW_WIPE_STRONG ||
            phrase.lowercased() == model.wipeAcceptPhrase().lowercased()
    }

    private func wipe(with phrase: String, model: DWRecoverModel) {
        autoreleasepool {
            if phrase == DW_WIPE {
                if model.isWalletEmpty() {
                    delegate?.recoverSeedPhraseInputControllerPerformWipe(self)
                }
                else {
                    delegate?.recoverSeedPhraseInputControllerWipeNotAllowed(self)
                }
            }
            else if phrase == DW_WIPE_STRONG ||
                        phrase.lowercased() == model.wipeAcceptPhrase().lowercased() {
                delegate?.recoverSeedPhraseInputControllerPerformWipe(self)
            }
            else if model.canWipe(withPhrase: phrase) {
                delegate?.recoverSeedPhraseInputControllerPerformWipe(self)
            }
            else if !phrase.isEmpty {
                delegate?.recoverSeedPhraseInputControllerWipeNotAllowedPhraseMismatch(self)
            }
        }
    }
}

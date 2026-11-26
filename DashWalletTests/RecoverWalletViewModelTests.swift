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

@testable import dashpay
import XCTest

/// Stands in for `DWRecoverModel`: words are valid when listed, a phrase is
/// valid when listed.
private final class FakeRecoverModel: RecoverPhraseChecking {
    var action: DWRecoverAction
    var validWords: Set<String> = []
    var validPhrases: Set<String> = []
    var hasWalletValue = false
    var hasPinSetValue = true
    var acceptancePhrase: String?
    var resetPinPhrases: Set<String> = []
    var wipePhrases: Set<String> = []
    var anyStoredWalletPhrases: Set<String> = []
    var walletEmpty = false
    var multipleWallets = false
    var plainWipeAllowed = true
    var wipeCount = 0

    init(action: DWRecoverAction) {
        self.action = action
    }

    func hasWallet() -> Bool { hasWalletValue }
    func hasPinSet() -> Bool { hasPinSetValue }
    func isWipeAcceptancePhrase(_ phrase: String) -> Bool { phrase == acceptancePhrase }
    func cleanupPhrase(_ phrase: String) -> String {
        phrase.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    func normalizePhrase(_ phrase: String?) -> String? { phrase }
    func wordIsValid(_ word: String) -> Bool { validWords.contains(word) }
    func phraseIsValid(_ phrase: String?) -> Bool { phrase.map(validPhrases.contains) ?? false }
    func canResetPinWithPhrase(_ phrase: String) -> Bool { resetPinPhrases.contains(phrase) }
    func isWalletEmpty() -> Bool { walletEmpty }
    func hasMultipleStoredWalletIds() -> Bool { multipleWallets }
    func plainWipeAllowedOnCurrentNetwork() -> Bool { plainWipeAllowed }
    func canWipeWithPhrase(_ phrase: String) -> Bool { wipePhrases.contains(phrase) }
    func phraseMatchesAnyStoredWallet(_ phrase: String) -> Bool { anyStoredWalletPhrases.contains(phrase) }
    func wipeWallet() { wipeCount += 1 }
}

private let twelveWords = (1...12).map { "word\($0)" }
private let validPhrase = twelveWords.joined(separator: " ")

@MainActor
final class RecoverPhraseEvaluatorTests: XCTestCase {
    private func model(_ action: DWRecoverAction) -> FakeRecoverModel {
        let model = FakeRecoverModel(action: action)
        model.validWords = Set(twelveWords)
        model.validPhrases = [validPhrase]
        return model
    }

    private func evaluate(_ phrase: String, with model: FakeRecoverModel) -> RecoverPhraseEvaluator.Evaluation {
        RecoverPhraseEvaluator(model: model).evaluate(phrase)
    }

    // MARK: Recover

    func testFewerThanTenWordsDoNothing() {
        let recover = model(.recover)
        XCTAssertEqual(evaluate("word1 word2", with: recover).outcome, .none)
        XCTAssertFalse(RecoverPhraseEvaluator(model: recover).canSubmit("word1 word2"))
        XCTAssertTrue(RecoverPhraseEvaluator(model: recover).canSubmit(validPhrase))
    }

    func testAValidPhraseRecovers() {
        XCTAssertEqual(evaluate(validPhrase, with: model(.recover)).outcome, .recover(phrase: validPhrase))
    }

    func testThePhraseIsCleanedUpAndShown() {
        let typed = "  " + validPhrase.uppercased() + "\n"
        let evaluation = evaluate(typed, with: model(.recover))
        XCTAssertEqual(evaluation.cleanedPhrase, validPhrase)
        XCTAssertEqual(evaluation.outcome, .recover(phrase: validPhrase))
    }

    func testOneWrongWordOffersARepair() {
        let phrase = (twelveWords.dropLast() + ["wrong"]).joined(separator: " ")
        XCTAssertEqual(evaluate(phrase, with: model(.recover)).outcome,
                       .offerWordRepair(incorrectWord: "wrong", phrase: phrase))
    }

    func testTwoWrongWordsNameTheFirst() {
        let phrase = (["bad1"] + twelveWords.dropFirst(2) + ["bad2"]).joined(separator: " ")
        XCTAssertEqual(evaluate(phrase, with: model(.recover)).outcome, .incorrectWord("bad1"))
    }

    func testTenOrElevenWordsOfferToFindTheMissingOnes() {
        let ten = Array(twelveWords.prefix(10))
        XCTAssertEqual(evaluate(ten.joined(separator: " "), with: model(.recover)).outcome,
                       .offerMissingWordsRepair(words: ten))
        let eleven = Array(twelveWords.prefix(11))
        XCTAssertEqual(evaluate(eleven.joined(separator: " "), with: model(.recover)).outcome,
                       .offerMissingWordsRepair(words: eleven))
    }

    func testThirteenWordsAreTheWrongCount() {
        let recover = model(.recover)
        recover.validWords.insert("word13")
        let phrase = (twelveWords + ["word13"]).joined(separator: " ")
        XCTAssertEqual(evaluate(phrase, with: recover).outcome, .invalidWordCount)
    }

    func testAnInvalidChecksumIsABadPhrase() {
        let phrase = twelveWords.reversed().joined(separator: " ")
        XCTAssertEqual(evaluate(phrase, with: model(.recover)).outcome, .badPhrase)
    }

    // MARK: Wipe

    func testWipeWithTheWalletsPhraseAsksToConfirm() {
        let wipe = model(.wipe)
        wipe.hasWalletValue = true
        wipe.wipePhrases = [validPhrase]
        XCTAssertEqual(evaluate(validPhrase, with: wipe).outcome, .confirmWipe)
    }

    func testWipeWithAnotherPhraseIsAMismatch() {
        let wipe = model(.wipe)
        wipe.hasWalletValue = true
        XCTAssertEqual(evaluate(validPhrase, with: wipe).outcome, .phraseMismatch)
    }

    func testWipeWithThePhraseOfOneOfSeveralWallets() {
        let wipe = model(.wipe)
        wipe.hasWalletValue = true
        wipe.anyStoredWalletPhrases = [validPhrase]
        XCTAssertEqual(evaluate(validPhrase, with: wipe).outcome, .multipleWallets)
    }

    func testOneWrongWordInWipeIsNotRepaired() {
        let wipe = model(.wipe)
        let phrase = (twelveWords.dropLast() + ["wrong"]).joined(separator: " ")
        XCTAssertEqual(evaluate(phrase, with: wipe).outcome, .badPhrase)
    }

    // MARK: Support wipe

    func testTheSupportAcknowledgementIsTakenAsTyped() {
        let support = model(.supportWipe)
        support.acceptancePhrase = "I understand, delete everything"
        XCTAssertTrue(RecoverPhraseEvaluator(model: support).canSubmit("I understand, delete everything"))
        let evaluation = evaluate("I understand, delete everything", with: support)
        XCTAssertNil(evaluation.cleanedPhrase)
        XCTAssertEqual(evaluation.outcome, .confirmWipe)
    }

    // MARK: Reset PIN

    func testResetPinWithAStoredWalletsPhrase() {
        let reset = model(.resetPin)
        reset.hasWalletValue = true
        reset.resetPinPhrases = [validPhrase]
        XCTAssertEqual(evaluate(validPhrase, with: reset).outcome, .verifiedForPinReset)
    }

    func testResetPinNeverWipes() {
        let reset = model(.resetPin)
        reset.hasWalletValue = true
        reset.wipePhrases = [validPhrase]
        XCTAssertEqual(evaluate(validPhrase, with: reset).outcome, .phraseMismatch)
    }
}

@MainActor
final class RecoverWalletViewModelTests: XCTestCase {
    func testResetPinTitleDependsOnAStoredPin() {
        let model = FakeRecoverModel(action: .resetPin)
        model.hasPinSetValue = false
        let viewModel = RecoverWalletViewModel(model: model)
        XCTAssertEqual(viewModel.title, String(localized: "Set PIN", comment: ""))
        XCTAssertEqual(viewModel.heading,
                       String(localized: "Enter your recovery phrase to set a new PIN", comment: ""))
    }

    func testARepairedWordReplacesTheWrongOne() {
        let viewModel = RecoverWalletViewModel(model: FakeRecoverModel(action: .recover))
        viewModel.phrase = "one Wrong three"
        viewModel.apply(repairedWords: ["two"], incorrectWord: "wrong")
        XCTAssertEqual(viewModel.phrase, "one two three")
    }

    func testFoundMissingWordsAreAppended() {
        let viewModel = RecoverWalletViewModel(model: FakeRecoverModel(action: .recover))
        viewModel.phrase = "one two"
        viewModel.apply(repairedWords: ["three"], incorrectWord: nil)
        XCTAssertEqual(viewModel.phrase, "one two three")
    }

    func testNoRepairedWordsLeaveThePhrase() {
        let viewModel = RecoverWalletViewModel(model: FakeRecoverModel(action: .recover))
        viewModel.phrase = "one two"
        viewModel.apply(repairedWords: [], incorrectWord: nil)
        XCTAssertEqual(viewModel.phrase, "one two")
    }

    func testAWipeThatCannotStartWipesNothing() {
        let model = FakeRecoverModel(action: .wipe)
        let viewModel = RecoverWalletViewModel(model: model, wiper: RecoverWalletWiper(
            begin: { _ in false },
            waitForPendingWipe: { _ in XCTFail("Nothing to wait for") },
            finish: { XCTFail("Nothing to finish") }
        ))

        viewModel.wipe()

        XCTAssertEqual(model.wipeCount, 0)
        XCTAssertNotNil(viewModel.alert)
    }

    func testACompletedWipeIsReported() {
        let model = FakeRecoverModel(action: .wipe)
        var finished = 0
        let viewModel = RecoverWalletViewModel(model: model, wiper: RecoverWalletWiper(
            begin: { _ in true },
            waitForPendingWipe: { $0(true) },
            finish: { finished += 1 }
        ))
        var wiped = 0
        viewModel.onWipe = { wiped += 1 }

        viewModel.wipe()

        XCTAssertEqual(model.wipeCount, 1)
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(wiped, 1)
    }
}

@MainActor
final class PhraseRepairViewModelTests: XCTestCase {
    private func makeRepair() -> PhraseRepairViewModel {
        PhraseRepairViewModel(search: { _, _ in }, maxConfidence: 0)
    }

    func testOneCertainWordIsFound() {
        let repair = makeRepair()
        var chosen: [String]?
        repair.onFinish = { chosen = $0 }

        repair.complete(with: ["apple": 0])
        XCTAssertEqual(repair.state, .found("apple"))

        repair.dismiss()
        XCTAssertEqual(chosen, ["apple"])
    }

    func testCandidatesComeLikeliestFirst() {
        let repair = makeRepair()
        repair.complete(with: ["far": 3, "near": 1, "mid": 2])
        XCTAssertEqual(repair.state, .candidates(["near", "mid", "far"]))
    }

    func testChoosingACandidateFinishesWithIt() {
        let repair = makeRepair()
        var chosen: [String]?
        repair.onFinish = { chosen = $0 }
        repair.complete(with: ["near": 1, "far": 3])

        repair.choose("far")

        XCTAssertEqual(chosen, ["far"])
    }

    func testNothingFoundFinishesEmpty() {
        let repair = makeRepair()
        var chosen: [String]?
        repair.onFinish = { chosen = $0 }

        repair.complete(with: [:])
        XCTAssertEqual(repair.state, .notFound)
        repair.dismiss()

        XCTAssertEqual(chosen, [])
    }

    func testCancelStopsAtTheNextTick() {
        var tick: ((Float, UnsafeMutablePointer<ObjCBool>) -> Void)?
        let repair = PhraseRepairViewModel(search: { progress, _ in tick = progress }, maxConfidence: 0)
        var finishes = 0
        repair.onFinish = { _ in finishes += 1 }
        repair.start()

        repair.cancel()
        let stop = UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1)
        defer { stop.deallocate() }
        stop.initialize(to: false)
        tick?(0.5, stop)

        XCTAssertTrue(stop.pointee.boolValue)
        XCTAssertEqual(finishes, 1)

        repair.complete(with: ["late": 0])
        XCTAssertEqual(finishes, 1, "A result after Cancel is ignored")
    }
}

//
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

import XCTest
@testable import dashpay

/// Pure rules behind the charged-failure explanation: the returned amount and the
/// amount to add. The amount-to-add boundary is asserted through `canFund` itself.
final class ShieldedChargedFailureFiguresTests: XCTestCase {
    private typealias Policy = PlatformPaymentIdentityFundingPolicy

    private let standardDenomination: UInt64 = 3_000_000
    private let contestedDenomination: UInt64 = 25_000_000
    private let standardFundingDuffs: UInt64 = 3_000_000
    private let contestedFundingDuffs = ContestedUsernameFee.Amounts.legacy.fundingDuffs

    private func candidate(hashByte: UInt8, balance: UInt64) -> Policy.Candidate {
        Policy.Candidate(addressType: 0, hash: Data(repeating: hashByte, count: 20), balance: balance)
    }

    /// `candidates` with `addedCredits` put on the `nextReceive` address, built
    /// independently of the function under test.
    private func adding(
        _ addedCredits: UInt64,
        to nextReceive: Policy.Candidate,
        in candidates: [Policy.Candidate]
    ) -> [Policy.Candidate] {
        var result = candidates
        if let index = result.firstIndex(where: {
            $0.addressType == nextReceive.addressType && $0.hash == nextReceive.hash
        }) {
            result[index] = Policy.Candidate(
                addressType: nextReceive.addressType,
                hash: nextReceive.hash,
                balance: result[index].balance + addedCredits)
        } else {
            result.append(Policy.Candidate(
                addressType: nextReceive.addressType,
                hash: nextReceive.hash,
                balance: nextReceive.balance + addedCredits))
        }
        return result
    }

    /// Asserts `x` is the smallest whole-duff top-up the policy accepts.
    private func assertMinimal(
        _ x: UInt64,
        candidates: [Policy.Candidate],
        nextReceive: Policy.Candidate,
        fundingDuffs: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(x, 0, file: file, line: line)
        XCTAssertTrue(
            Policy.canFund(candidates: adding(x * 1000, to: nextReceive, in: candidates), fundingDuffs: fundingDuffs),
            "X = \(x) must be accepted", file: file, line: line)
        XCTAssertFalse(
            Policy.canFund(
                candidates: adding((x - 1) * 1000, to: nextReceive, in: candidates), fundingDuffs: fundingDuffs),
            "X - 1 = \(x - 1) must be rejected", file: file, line: line)
    }

    // MARK: - returnedDuffs

    func test_returned_zeroIncreaseIsNil() {
        XCTAssertNil(Policy.returnedDuffs(
            snapshotCredits: 5_000, currentCredits: 5_000, exitDenominationDuffs: standardDenomination))
    }

    func test_returned_decreaseIsNil() {
        XCTAssertNil(Policy.returnedDuffs(
            snapshotCredits: 5_000_000_000, currentCredits: 4_000_000_000, exitDenominationDuffs: standardDenomination))
    }

    func test_returned_increaseUnderOneDuffIsNil() {
        // Stated as 0 it would be fixed for good and hide a later real return.
        XCTAssertNil(Policy.returnedDuffs(
            snapshotCredits: 5_000, currentCredits: 5_000 + 999, exitDenominationDuffs: standardDenomination))
        XCTAssertEqual(
            Policy.returnedDuffs(
                snapshotCredits: 5_000, currentCredits: 5_000 + 1_000, exitDenominationDuffs: standardDenomination),
            1)
    }

    func test_returned_increaseAboveDenominationIsNil() {
        XCTAssertNil(Policy.returnedDuffs(
            snapshotCredits: 0, currentCredits: 3_000_000_001, exitDenominationDuffs: standardDenomination))
    }

    func test_returned_increaseEqualToDenominationIsTheDenomination() {
        XCTAssertEqual(
            Policy.returnedDuffs(
                snapshotCredits: 1_000, currentCredits: 1_000 + 3_000_000_000,
                exitDenominationDuffs: standardDenomination),
            3_000_000)
    }

    func test_returned_roundsDownToWholeDuffs() {
        XCTAssertEqual(
            Policy.returnedDuffs(
                snapshotCredits: 7_000, currentCredits: 7_000 + 2_980_000_500,
                exitDenominationDuffs: standardDenomination),
            2_980_000)
    }

    func test_returned_smallExtraPaymentWithinDenominationIsIncluded() {
        // 2_900_000_000 returned + 50_000_000 (below the ~0.0002 DASH penalty scale, 0.00005 DASH) paid in between
        XCTAssertEqual(
            Policy.returnedDuffs(
                snapshotCredits: 5_000, currentCredits: 5_000 + 2_900_000_000 + 50_000_000,
                exitDenominationDuffs: standardDenomination),
            2_950_000)
    }

    func test_returned_contestedDenomination() {
        XCTAssertEqual(
            Policy.returnedDuffs(
                snapshotCredits: 0, currentCredits: 24_999_999_999, exitDenominationDuffs: contestedDenomination),
            24_999_999)
        XCTAssertEqual(
            Policy.returnedDuffs(
                snapshotCredits: 0, currentCredits: 25_000_000_000, exitDenominationDuffs: contestedDenomination),
            25_000_000)
        XCTAssertNil(Policy.returnedDuffs(
            snapshotCredits: 0, currentCredits: 25_000_000_001, exitDenominationDuffs: contestedDenomination))
    }

    // MARK: - amountToAddDuffs

    func test_amountToAdd_zeroWhenAlreadyFundable() {
        let a = candidate(hashByte: 1, balance: 4_000_000_000)
        XCTAssertTrue(Policy.canFund(candidates: [a], fundingDuffs: standardFundingDuffs))
        XCTAssertEqual(
            Policy.amountToAddDuffs(candidates: [a], nextReceive: a, fundingDuffs: standardFundingDuffs), 0)
    }

    func test_amountToAdd_singleAddressShort_isMinimal() {
        let a = candidate(hashByte: 1, balance: 2_500_000_000)
        let x = Policy.amountToAddDuffs(candidates: [a], nextReceive: a, fundingDuffs: standardFundingDuffs)
        assertMinimal(x, candidates: [a], nextReceive: a, fundingDuffs: standardFundingDuffs)
    }

    func test_amountToAdd_freshNextReceiveAddress_isMinimal() {
        let existing = candidate(hashByte: 1, balance: 2_500_000_000)
        let fresh = candidate(hashByte: 9, balance: 0)
        let x = Policy.amountToAddDuffs(candidates: [existing], nextReceive: fresh, fundingDuffs: standardFundingDuffs)
        assertMinimal(x, candidates: [existing], nextReceive: fresh, fundingDuffs: standardFundingDuffs)
    }

    func test_amountToAdd_emptyWallet_isMinimal() {
        let fresh = candidate(hashByte: 9, balance: 0)
        let x = Policy.amountToAddDuffs(candidates: [], nextReceive: fresh, fundingDuffs: standardFundingDuffs)
        assertMinimal(x, candidates: [], nextReceive: fresh, fundingDuffs: standardFundingDuffs)
    }

    func test_amountToAdd_splitBalanceWithStrandedLeadingNextReceive() {
        // The next receive address (smaller hash) holds 0.001 DASH, below the fee reserve, so it is skipped
        // and the usable suffix (3.0e9) is short. It only counts once it exceeds the reserve (strictly), so the
        // minimum is not the plain shortfall: 200_000_000 credits is still rejected, 200_001_000 accepted.
        let stranded = candidate(hashByte: 1, balance: 100_000_000)
        let big = candidate(hashByte: 2, balance: 3_000_000_000)
        let x = Policy.amountToAddDuffs(
            candidates: [stranded, big], nextReceive: stranded, fundingDuffs: standardFundingDuffs)
        assertMinimal(x, candidates: [stranded, big], nextReceive: stranded, fundingDuffs: standardFundingDuffs)
        XCTAssertEqual(x, 100_001)
    }

    func test_amountToAdd_splitBalanceNextReceiveIsLaterAddress() {
        let first = candidate(hashByte: 1, balance: 1_000_000_000)
        let next = candidate(hashByte: 2, balance: 500_000_000)
        let x = Policy.amountToAddDuffs(
            candidates: [first, next], nextReceive: next, fundingDuffs: standardFundingDuffs)
        assertMinimal(x, candidates: [first, next], nextReceive: next, fundingDuffs: standardFundingDuffs)
    }

    func test_amountToAdd_contestedFunding_isMinimal() {
        let a = candidate(hashByte: 1, balance: 5_000_000_000)
        let b = candidate(hashByte: 2, balance: 1_000_000_000)
        let x = Policy.amountToAddDuffs(
            candidates: [a, b], nextReceive: b, fundingDuffs: contestedFundingDuffs)
        assertMinimal(x, candidates: [a, b], nextReceive: b, fundingDuffs: contestedFundingDuffs)
    }

    // MARK: - Explanation model

    private let network = 1
    private let walletHex = "aa11"
    private let snapshot: UInt64 = 1_000
    private let fallbackHash = Data(repeating: 0xFA, count: 20)

    private var fallbackKey: Data { Data([0]) + fallbackHash }

    private func fallbackCandidate(balance: UInt64) -> Policy.Candidate {
        Policy.Candidate(addressType: 0, hash: fallbackHash, balance: balance)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ShieldedChargedFailureExplanationModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func saveRecord(
        _ store: ShieldedChargedFailureStore, isContested: Bool = false, returnedDuffs: UInt64? = nil
    ) {
        var record = ShieldedChargedFailureStore.Record.charged(
            username: "alice", isContested: isContested,
            denominationCredits: (isContested ? contestedDenomination : standardDenomination) * 1_000,
            fallbackAddress: fallbackKey, snapshotCredits: snapshot)
        record.returnedDuffs = returnedDuffs
        store.save(record, networkRawValue: network, walletIdHex: walletHex)
    }

    /// Mutable fakes the model reads through its closures.
    private final class Fakes {
        var candidates: [Policy.Candidate]
        var nextReceive: Policy.Candidate?
        /// The Platform balance read fails: the model gets no list, not an empty one.
        var readFails = false
        var fundingRequests: [Bool] = []
        init(candidates: [Policy.Candidate], nextReceive: Policy.Candidate?) {
            self.candidates = candidates
            self.nextReceive = nextReceive
        }
    }

    @MainActor
    private func makeModel(
        _ store: ShieldedChargedFailureStore, _ fakes: Fakes, network: Int? = nil, wallet: String? = nil
    ) -> ShieldedChargedFailureExplanationModel {
        let standard = standardFundingDuffs
        let contested = contestedFundingDuffs
        return ShieldedChargedFailureExplanationModel(
            store: store,
            networkRawValue: network ?? self.network,
            walletIdHex: wallet ?? walletHex,
            candidates: { fakes.readFails ? nil : fakes.candidates },
            nextReceive: { fakes.nextReceive },
            fundingDuffs: { isContested in
                fakes.fundingRequests.append(isContested)
                return isContested ? contested : standard
            })
    }

    /// Fallback at the snapshot balance, another empty address as the next receive address.
    private func freshFakes(fallbackBalance: UInt64? = nil) -> Fakes {
        Fakes(
            candidates: [fallbackCandidate(balance: fallbackBalance ?? snapshot)],
            nextReceive: candidate(hashByte: 9, balance: 0))
    }

    private func assertText(
        _ actual: (block1: String, block2: String?)?,
        returned: UInt64?, toAdd: UInt64?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expected = ShieldedChargedFailureExplanation.text(returnedDuffs: returned, amountToAddDuffs: toAdd)
        XCTAssertEqual(actual?.block1, expected.block1, file: file, line: line)
        XCTAssertEqual(actual?.block2, expected.block2, file: file, line: line)
    }

    /// 2_000_000_500 credits come back: 2_000_000 duffs, rounded down.
    private let returnedCredits: UInt64 = 2_000_000_500
    private let returnedFixed: UInt64 = 2_000_000

    @MainActor
    func test_model_noRecord_textIsNil() {
        let model = makeModel(ShieldedChargedFailureStore(defaults: makeDefaults()), freshFakes())
        model.refresh()
        XCTAssertNil(model.text)
        XCTAssertFalse(model.needsBalanceUpdates)
    }

    @MainActor
    func test_model_otherWalletOrNetwork_textIsNil_switchingBackShowsIt() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let fakes = freshFakes()

        let otherWallet = makeModel(store, fakes, wallet: "bb22")
        otherWallet.refresh()
        XCTAssertNil(otherWallet.text)
        XCTAssertFalse(otherWallet.needsBalanceUpdates)

        let otherNetwork = makeModel(store, fakes, network: 2)
        otherNetwork.refresh()
        XCTAssertNil(otherNetwork.text)

        let back = makeModel(store, fakes)
        back.refresh()
        assertText(back.text, returned: nil, toAdd: nil)
    }

    @MainActor
    func test_model_balanceUnchanged_isChecking() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let model = makeModel(store, freshFakes())
        model.refresh()
        assertText(model.text, returned: nil, toAdd: nil)
        XCTAssertNotNil(model.text?.block2)
        XCTAssertTrue(model.needsBalanceUpdates)
        XCTAssertNil(store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs)
    }

    @MainActor
    func test_model_balanceRisesWithinDenomination_fixesAmountAndExplains() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let fakes = freshFakes()
        let model = makeModel(store, fakes)
        model.refresh()

        fakes.candidates = [fallbackCandidate(balance: snapshot + returnedCredits)]
        model.refresh()

        XCTAssertEqual(
            store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs, returnedFixed)
        let toAdd = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: fakes.nextReceive!, fundingDuffs: standardFundingDuffs)
        XCTAssertGreaterThan(toAdd, 0)
        assertText(model.text, returned: returnedFixed, toAdd: toAdd)
        XCTAssertFalse(model.needsBalanceUpdates)
    }

    @MainActor
    func test_model_amountIsFixedOnce_furtherRiseKeepsIt() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let fakes = freshFakes(fallbackBalance: snapshot + returnedCredits)
        let model = makeModel(store, fakes)
        model.refresh()

        fakes.candidates = [fallbackCandidate(balance: snapshot + returnedCredits + 500_000_000)]
        model.refresh()

        XCTAssertEqual(
            store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs, returnedFixed)
        let toAdd = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: fakes.nextReceive!, fundingDuffs: standardFundingDuffs)
        assertText(model.text, returned: returnedFixed, toAdd: toAdd)
    }

    @MainActor
    func test_model_amountToAddFollowsBalanceNow() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let fakes = freshFakes(fallbackBalance: snapshot + returnedCredits)
        let model = makeModel(store, fakes)
        model.refresh()

        let before = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: fakes.nextReceive!, fundingDuffs: standardFundingDuffs)
        assertText(model.text, returned: returnedFixed, toAdd: before)

        // Another address gets some funds: the amount to add shrinks.
        let other = candidate(hashByte: 9, balance: 500_000_000)
        fakes.candidates.append(other)
        fakes.nextReceive = other
        model.refresh()
        let smaller = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: other, fundingDuffs: standardFundingDuffs)
        XCTAssertLessThan(smaller, before)
        assertText(model.text, returned: returnedFixed, toAdd: smaller)

        // Enough now: nothing to add.
        let rich = candidate(hashByte: 9, balance: 5_000_000_000)
        fakes.candidates = [fallbackCandidate(balance: snapshot + returnedCredits), rich]
        fakes.nextReceive = rich
        model.refresh()
        XCTAssertEqual(
            Policy.amountToAddDuffs(
                candidates: fakes.candidates, nextReceive: rich, fundingDuffs: standardFundingDuffs),
            0)
        assertText(model.text, returned: returnedFixed, toAdd: 0)
        XCTAssertEqual(
            store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs, returnedFixed)
    }

    @MainActor
    func test_model_riseAboveDenomination_staysChecking() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let model = makeModel(store, freshFakes(fallbackBalance: snapshot + standardDenomination * 1_000 + 1))
        model.refresh()
        assertText(model.text, returned: nil, toAdd: nil)
        XCTAssertTrue(model.needsBalanceUpdates)
        XCTAssertNil(store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs)
    }

    @MainActor
    func test_model_contestedRecord_usesContestedFundingAndNoContestFeeWording() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store, isContested: true)
        let fakes = freshFakes(fallbackBalance: snapshot + 20_000_000_000)
        let model = makeModel(store, fakes)
        model.refresh()

        XCTAssertTrue(fakes.fundingRequests.contains(true))
        XCTAssertFalse(fakes.fundingRequests.contains(false))
        let toAdd = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: fakes.nextReceive!, fundingDuffs: contestedFundingDuffs)
        XCTAssertGreaterThan(toAdd, 0)
        assertText(model.text, returned: 20_000_000, toAdd: toAdd)
        XCTAssertFalse(model.text?.block2?.lowercased().contains("contest fee") ?? false)
    }

    @MainActor
    func test_model_amountFixed_nextReceiveNotDerivedYet_statesReturnedAmountWithoutAdvice() {
        // A relaunch before the Platform addresses are derived again.
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store, returnedDuffs: returnedFixed)
        let fakes = freshFakes()
        fakes.nextReceive = nil
        let model = makeModel(store, fakes)
        model.refresh()
        assertText(model.text, returned: returnedFixed, toAdd: nil)
        XCTAssertNotEqual(
            model.text?.block2,
            ShieldedChargedFailureExplanation.text(returnedDuffs: nil, amountToAddDuffs: nil).block2)
        XCTAssertFalse(model.needsBalanceUpdates)
    }

    @MainActor
    func test_model_amountFixed_balanceReadFails_statesReturnedAmountWithoutAdvice() {
        // A failed read is not an empty wallet: no amount to add until a read succeeds.
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store, returnedDuffs: returnedFixed)
        let fakes = freshFakes()
        fakes.readFails = true
        let model = makeModel(store, fakes)
        model.refresh()
        assertText(model.text, returned: returnedFixed, toAdd: nil)
        XCTAssertFalse(model.needsBalanceUpdates)

        fakes.readFails = false
        model.refresh()
        let toAdd = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: fakes.nextReceive!, fundingDuffs: standardFundingDuffs)
        assertText(model.text, returned: returnedFixed, toAdd: toAdd)
    }

    @MainActor
    func test_model_amountNotFixed_balanceReadFails_staysCheckingAndFixesNothing() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store)
        let fakes = freshFakes(fallbackBalance: snapshot + returnedCredits)
        fakes.readFails = true
        let model = makeModel(store, fakes)
        model.refresh()
        assertText(model.text, returned: nil, toAdd: nil)
        XCTAssertTrue(model.needsBalanceUpdates)
        XCTAssertNil(store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs)
    }

    @MainActor
    func test_model_amountAlreadyFixedElsewhere_isReadFromStore() {
        let store = ShieldedChargedFailureStore(defaults: makeDefaults())
        saveRecord(store, returnedDuffs: 1_234_000)
        // The balance now would give another figure; the stored one wins.
        let fakes = freshFakes(fallbackBalance: snapshot + returnedCredits)
        let model = makeModel(store, fakes)
        model.refresh()

        XCTAssertEqual(
            store.record(networkRawValue: network, walletIdHex: walletHex)?.returnedDuffs, 1_234_000)
        let toAdd = Policy.amountToAddDuffs(
            candidates: fakes.candidates, nextReceive: fakes.nextReceive!, fundingDuffs: standardFundingDuffs)
        assertText(model.text, returned: 1_234_000, toAdd: toAdd)
        XCTAssertFalse(model.needsBalanceUpdates)
    }
}

//
//  PooledSendableBalanceTests.swift
//  DashWalletTests
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

import Combine
import XCTest
@testable import dashpay

/// The app-side half of the pooled-balance contract: which of the two figures
/// the send ceiling reads, what a shortfall between them means, and how Max
/// explains itself when it comes up short. The SDK's arithmetic is tested in
/// `platform-wallet`; none of that says anything about these decisions, and
/// each of them has already been wrong once — a silent 0 blocked every send on
/// the 2026-09-03 QA build, and the fee-and-unconfirmed wording misattributed
/// 94 DASH of mixed coins.
final class PooledSendableBalanceTests: XCTestCase {

    // MARK: The fallback policy

    func testPooledFigureIsPreferredWhenItIsSmallerThanTheWalletTotal() {
        XCTAssertEqual(
            SwiftDashSDKWalletState.sendableDuffs(pooled: 538_503, walletSpendable: 9_460_987_512),
            538_503,
            "the ceiling is what the pool can fund, not what the wallet holds")
    }

    func testASuccessfulZeroDoesNotFallBack() {
        // The CoinJoin-only wallet: the SDK answered, and the answer is zero.
        // Falling back here would re-offer the whole balance and put back the
        // "insufficient unreserved core funds" failure this gate exists to stop.
        XCTAssertEqual(
            SwiftDashSDKWalletState.sendableDuffs(pooled: 0, walletSpendable: 9_460_987_512),
            0)
    }

    func testAnUnavailableReadFallsBackToTheWalletWideFigure() {
        // Over-offering is the pre-#1107 behaviour and recoverable. A silent 0
        // is not: on the 2026-09-03 QA build the FFI refused every call and a
        // permanent 0 zeroed Max and blocked every send.
        XCTAssertEqual(
            SwiftDashSDKWalletState.sendableDuffs(pooled: nil, walletSpendable: 9_460_987_512),
            9_460_987_512)
    }

    func testRecoveryFromAnUnavailableReadTakesTheLowerCeilingBack() {
        let duringOutage = SwiftDashSDKWalletState.sendableDuffs(
            pooled: nil, walletSpendable: 9_460_987_512)
        let afterRecovery = SwiftDashSDKWalletState.sendableDuffs(
            pooled: 538_503, walletSpendable: 9_460_987_512)
        XCTAssertGreaterThan(duringOutage, afterRecovery,
                             "recovery must be able to lower the ceiling, not only raise it")
        XCTAssertEqual(afterRecovery, 538_503)
    }

    func testNeitherFigureAvailableIsZero() {
        XCTAssertEqual(
            SwiftDashSDKWalletState.sendableDuffs(pooled: nil, walletSpendable: nil), 0)
    }

    // MARK: What the shortfall means

    func testExcludedFundsAreTheDifferenceBetweenTheTwoFigures() {
        XCTAssertEqual(
            SwiftDashSDKWalletState.excludedFromSendPool(
                pooled: 538_503, walletSpendable: 9_460_987_512),
            9_460_449_009)
    }

    func testNothingIsExcludedWhileThePooledFigureIsUnknown() {
        // An outage is not evidence that funds are excluded — and the ceiling
        // is falling back to the wallet-wide figure anyway, so nothing is being
        // withheld from Max to explain.
        XCTAssertEqual(
            SwiftDashSDKWalletState.excludedFromSendPool(
                pooled: nil, walletSpendable: 9_460_987_512),
            0)
    }

    func testAPooledFigureAboveTheWalletWideOneExcludesNothing() {
        // The two are read at different moments; a larger pooled figure means
        // they disagree, not that the difference is negative.
        XCTAssertEqual(
            SwiftDashSDKWalletState.excludedFromSendPool(pooled: 200, walletSpendable: 100), 0)
    }

    // MARK: Max flooring

    func testMaxFloorsAtTheFeeReserveRatherThanWrapping() {
        XCTAssertEqual(SwiftDashSDKWalletState.feeAwareMax(spendable: 100, reserve: 100_000), 0)
        XCTAssertEqual(
            SwiftDashSDKWalletState.feeAwareMax(spendable: 100_000, reserve: 100_000), 0,
            "a balance exactly equal to the reserve leaves nothing to send")
        XCTAssertEqual(
            SwiftDashSDKWalletState.feeAwareMax(spendable: 100_001, reserve: 100_000), 1)
    }

    // MARK: A shortfall that is only waiting on confirmations

    private func pool(confirmed: UInt64, unconfirmed: UInt64) -> SendPoolConfirmationSnapshot {
        SendPoolConfirmationSnapshot(confirmedDuffs: confirmed, unconfirmedDuffs: unconfirmed)
    }

    private func judge(
        _ requested: UInt64, reserve: UInt64 = 0, sendable: UInt64, pool: SendPoolConfirmationSnapshot?
    ) -> SendFundsVerdict {
        SwiftDashSDKWalletState.judgeShortfall(
            requested: requested, sendable: sendable, pool: pool, reserve: { reserve })
    }

    func testAnAmountThatFitsOnceIncomingFundsConfirmIsNamedAsConfirming() {
        // Just after a receive: 1 DASH confirmed, 2 DASH more in the pool still
        // waiting on a block or a lock. 2.5 DASH is on screen and refused.
        XCTAssertEqual(
            judge(250_000_000, reserve: 1_000, sendable: 100_000_000,
                  pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)),
            .confirming(200_000_000))
    }

    func testAnAmountThatLeavesNoRoomForTheFeeOnceConfirmedIsStillInsufficient() {
        // The whole pool, once confirmed, still cannot pay amount + fee:
        // telling the user to wait would promise a send that then fails.
        let pool = pool(confirmed: 100_000_000, unconfirmed: 200_000_000)
        XCTAssertEqual(judge(300_000_000, reserve: 1_000, sendable: 100_000_000, pool: pool), .insufficient)
        XCTAssertEqual(judge(299_999_000, reserve: 1_000, sendable: 100_000_000, pool: pool),
                       .confirming(200_000_000))
    }

    func testNothingConfirmedYetStillKeepsTheFeeReserve() {
        // A fee-aware ceiling floors at 0 here: 1 DASH received, none of it
        // confirmed, 1 DASH entered — it cannot also pay the fee.
        let pool = pool(confirmed: 0, unconfirmed: 100_000_000)
        XCTAssertEqual(judge(100_000_000, reserve: 300, sendable: 0, pool: pool), .insufficient)
        XCTAssertEqual(judge(99_999_700, reserve: 300, sendable: 0, pool: pool), .confirming(100_000_000))
    }

    func testAGapWithNothingConfirmingIsNeverCalledAWait() {
        // The pool holds more than the gate counts, but none of it is
        // confirming — a pooled figure not re-read yet, or an account the
        // SDK's pool does not fund from. Waiting changes nothing, so saying
        // "wait" here would never clear.
        XCTAssertEqual(
            judge(250_000_000, sendable: 100_000_000, pool: pool(confirmed: 300_000_000, unconfirmed: 0)),
            .insufficient)
    }

    func testOnlyWhatConfirmationAddsCountsTowardTheFit() {
        // 1 DASH confirmed in the pool but only 0.7 counted, 0.1 confirming:
        // confirmation frees 0.1, not the whole 0.4 gap, so 1.05 never fits.
        XCTAssertEqual(
            judge(105_000_000, sendable: 70_000_000, pool: pool(confirmed: 100_000_000, unconfirmed: 10_000_000)),
            .insufficient)
        XCTAssertEqual(
            judge(80_000_000, sendable: 70_000_000, pool: pool(confirmed: 100_000_000, unconfirmed: 10_000_000)),
            .confirming(10_000_000))
    }

    func testCoinJoinFundsDoNotShrinkTheNamedWait() {
        // Pool: 1 confirmed + 2 waiting; 1.5 DASH of confirmed CoinJoin lifts
        // the wallet-wide side, so `sendable` is 2.5. What is confirming is
        // still 2 DASH, and the pool total of 3 is what it fits under.
        let pool = pool(confirmed: 100_000_000, unconfirmed: 200_000_000)
        XCTAssertEqual(judge(280_000_000, sendable: 250_000_000, pool: pool), .confirming(200_000_000))
        XCTAssertEqual(judge(300_000_001, sendable: 250_000_000, pool: pool), .insufficient)
    }

    func testAPooledFigureThatAlreadyCountsTheUnconfirmedCoinsMeansNoWait() {
        // Today's pooled figure includes unconfirmed coins; when it is the
        // smaller of the two (CoinJoin makes the wallet-wide one larger) the
        // gate already counts them, and waiting changes nothing.
        XCTAssertEqual(
            judge(350_000_000, sendable: 300_000_000, pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)),
            .insufficient)
    }

    func testAReserveAboveEverythingThePoolWillHoldNeverClaimsAWait() {
        XCTAssertEqual(judge(1, reserve: 100_000, sendable: 0, pool: pool(confirmed: 0, unconfirmed: 50_000)),
                       .insufficient)
    }

    func testAnAmountAboveEverythingThePoolWillHoldIsStillInsufficient() {
        XCTAssertEqual(
            judge(300_000_001, sendable: 100_000_000, pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)),
            .insufficient, "waiting would not make this fit")
    }

    func testAnUnreadablePoolNeverClaimsFundsAreConfirming() {
        XCTAssertEqual(judge(250_000_000, sendable: 100_000_000, pool: nil), .insufficient)
    }

    func testAnAmountThatCannotFitIsRefusedWithoutReadingTheReserve() {
        // The reserve is a walk over every pooled UTXO on the main thread;
        // typing past everything the pool holds must not pay for it per key.
        var reserveReads = 0
        let verdict = SwiftDashSDKWalletState.judgeShortfall(
            requested: 400_000_000,
            sendable: 100_000_000,
            pool: pool(confirmed: 100_000_000, unconfirmed: 100_000_000),
            reserve: { reserveReads += 1; return 1_000 })
        XCTAssertEqual(verdict, .insufficient)
        XCTAssertEqual(reserveReads, 0)
    }

    func testAnAmountThatMayFitStillKeepsTheLazyReserve() {
        var reserveReads = 0
        let verdict = SwiftDashSDKWalletState.judgeShortfall(
            requested: 199_999_500,
            sendable: 100_000_000,
            pool: pool(confirmed: 100_000_000, unconfirmed: 100_000_000),
            reserve: { reserveReads += 1; return 1_000 })
        XCTAssertEqual(verdict, .insufficient, "fits only without the reserve")
        XCTAssertEqual(reserveReads, 1)
    }

    func testAVerdictMapsToTheRefusalItNames() {
        XCTAssertNil(SendAmountError(refusing: .fits))
        XCTAssertEqual(SendAmountError(refusing: .insufficient)?.errorDescription,
                       SendAmountError.insufficientFunds.errorDescription)
        XCTAssertEqual(SendAmountError(refusing: .confirming(5))?.errorDescription,
                       SendAmountError.fundsStillConfirming(5).errorDescription)
    }

    func testTheConfirmingMessageNamesTheWaitingAmount() {
        let message = SendAmountError.fundsStillConfirming(200_000_000).errorDescription ?? ""
        XCTAssertTrue(message.contains("still confirming"), "got: \(message)")
        XCTAssertTrue(message.contains(UInt64(200_000_000).formattedDashAmountWithoutCurrencySymbol),
                      "got: \(message)")
    }

    func testOnlyAffordabilityVerdictsCountAsFundsVerdicts() {
        XCTAssertTrue(SendAmountError.insufficientFunds.isFundsVerdict)
        XCTAssertTrue(SendAmountError.fundsStillConfirming(1).isFundsVerdict)
        XCTAssertFalse(SendAmountError.maxUnavailable("x").isFundsVerdict,
                       "a Max explanation must survive a balance change")
        XCTAssertFalse(SendAmountError.syncingChain.isFundsVerdict)
    }

    func testTheSameAmountErrorAssignedAgainIsNotPresentedAgain() {
        // The UIKit amount screens present each handled error, dropping their
        // progress indicator; a re-check that lands on the same error must not.
        XCTAssertTrue(BaseAmountModel.isSameAmountError(
            SendAmountError.fundsStillConfirming(5), SendAmountError.fundsStillConfirming(5)))
        XCTAssertFalse(BaseAmountModel.isSameAmountError(
            SendAmountError.fundsStillConfirming(5), SendAmountError.fundsStillConfirming(6)))
        XCTAssertFalse(BaseAmountModel.isSameAmountError(SendAmountError.insufficientFunds, nil))
        XCTAssertFalse(BaseAmountModel.isSameAmountError(
            URLError(.notConnectedToInternet), URLError(.notConnectedToInternet)),
                       "only amount errors are known to say the same thing twice")
    }

    func testAWalletChangeReJudgesOnlyWhatTheWalletDecides() {
        XCTAssertEqual(SendAmountModel.walletChangeAction(for: nil), .recheckAmount)
        XCTAssertEqual(SendAmountModel.walletChangeAction(for: SendAmountError.insufficientFunds), .recheckAmount)
        XCTAssertEqual(SendAmountModel.walletChangeAction(for: SendAmountError.fundsStillConfirming(1)),
                       .recheckAmount)
        // `checkAmountForErrors` never sets it, so clearing it would leave no
        // explanation, and keeping it would say "still confirming" after the
        // coins confirmed.
        XCTAssertEqual(SendAmountModel.walletChangeAction(for: SendAmountError.maxUnavailable("x")),
                       .refreshMaxExplanation)
        XCTAssertEqual(SendAmountModel.walletChangeAction(for: SendAmountError.syncingChain), .keep,
                       "the sync monitor owns this one")
        XCTAssertEqual(SendAmountModel.walletChangeAction(for: URLError(.notConnectedToInternet)), .keep,
                       "a subclass's own failure is not the wallet's to clear")
    }

    // MARK: How Max explains an empty result

    func testAConfirmedCoinJoinOnlyBalanceIsNotBlamedOnTheFee() {
        // The wallet from ticket 32081: 94.6 DASH confirmed, 0.0054 of it
        // transparent. Before this, Max said the balance was too low to cover
        // the transfer fee — which is false, and points at waiting rather than
        // at the mixed-coins move.
        let message = InternalTransferViewModel.coreZeroMaxMessage(
            totalDuffs: 9_460_987_512,
            confirmedSpendableDuffs: 9_460_987_512,
            excludedFromPoolDuffs: 9_460_987_512)
        XCTAssertTrue(message.contains("mixed coins"), "got: \(message)")
        XCTAssertFalse(message.lowercased().contains("fee"), "got: \(message)")
    }

    func testStillConfirmingWinsOverTheMixedCoinsWording() {
        let message = InternalTransferViewModel.coreZeroMaxMessage(
            totalDuffs: 9_460_987_512,
            confirmedSpendableDuffs: 0,
            excludedFromPoolDuffs: 0)
        XCTAssertTrue(message.contains("still confirming"), "got: \(message)")
    }

    func testAnEmptyWalletIsStillAnEmptyWallet() {
        let message = InternalTransferViewModel.coreZeroMaxMessage(
            totalDuffs: 0, confirmedSpendableDuffs: 0, excludedFromPoolDuffs: 0)
        XCTAssertFalse(message.contains("mixed coins"), "got: \(message)")
    }

    func testAConfirmedTransparentBalanceTooSmallForTheFeeStillSaysSo() {
        let message = InternalTransferViewModel.coreZeroMaxMessage(
            totalDuffs: 50_000, confirmedSpendableDuffs: 50_000, excludedFromPoolDuffs: 0)
        XCTAssertFalse(message.contains("mixed coins"), "got: \(message)")
        // Naming the reason, not merely NOT naming the wrong one: without this
        // the assertion above also passes for an empty or unrelated message.
        XCTAssertTrue(message.lowercased().contains("fee"), "got: \(message)")
    }

    func testTheCeilingTakesTheLowerOfTwoKnownFigures() {
        // The two are independent snapshots: `applyBalance` publishes the
        // wallet-wide figure while the pooled read is still in flight, so a
        // pooled value from before a spend can outlive the wallet-wide one
        // that already reflects it. Gating on the stale higher number accepts
        // an amount the builder then refuses.
        XCTAssertEqual(
            SwiftDashSDKWalletState.sendableDuffs(pooled: 9_000_000, walletSpendable: 1_000_000),
            1_000_000,
            "a pooled figure above the wallet-wide one is stale, not a larger pool")
    }

    // MARK: - The ceiling publisher the amount screen validates against

    /// `SendAmountModel.observeSendableCeiling` subscribes to this. A test over
    /// the pure `sendableDuffs` arithmetic cannot tell a live subscription from
    /// a missing one, so the derived publisher is what these exercise.

    func testTheCeilingEmitsWhenThePooledFigureArrives() {
        let pooled = CurrentValueSubject<UInt64?, Never>(nil)
        let spendable = CurrentValueSubject<UInt64?, Never>(94_000_000)
        var seen: [UInt64] = []
        let token = SwiftDashSDKWalletState
            .sendableCeilingPublisher(pooled: pooled.eraseToAnyPublisher(),
                                      walletSpendable: spendable.eraseToAnyPublisher())
            .sink { seen.append($0) }

        pooled.send(120_000)

        XCTAssertEqual(seen, [94_000_000, 120_000],
                       "the fallback ceiling, then the pooled one that replaces it")
        token.cancel()
    }

    func testTheCeilingEmitsWhenOnlyTheFallbackMovesDuringAPooledOutage() {
        // The case a `$pooledSpendableDuffs`-only subscription misses: through
        // an outage the pooled value stays nil and `removeDuplicates` swallows
        // every repeat, while the wallet balance keeps moving the ceiling.
        let pooled = CurrentValueSubject<UInt64?, Never>(nil)
        let spendable = CurrentValueSubject<UInt64?, Never>(10_000)
        var seen: [UInt64] = []
        let token = SwiftDashSDKWalletState
            .sendableCeilingPublisher(pooled: pooled.eraseToAnyPublisher(),
                                      walletSpendable: spendable.eraseToAnyPublisher())
            .sink { seen.append($0) }

        spendable.send(4_000)
        pooled.send(nil)

        XCTAssertEqual(seen, [10_000, 4_000],
                       "the drop reaches the screen, and the repeated nil adds nothing")
        token.cancel()
    }

    func testTheCeilingIgnoresAnUpdateThatLeavesItWhereItWas() {
        let pooled = CurrentValueSubject<UInt64?, Never>(120_000)
        let spendable = CurrentValueSubject<UInt64?, Never>(94_000_000)
        var seen: [UInt64] = []
        let token = SwiftDashSDKWalletState
            .sendableCeilingPublisher(pooled: pooled.eraseToAnyPublisher(),
                                      walletSpendable: spendable.eraseToAnyPublisher())
            .sink { seen.append($0) }

        // The wallet-wide figure moves, but the pooled one rules — the screen
        // has nothing to revalidate.
        spendable.send(80_000_000)
        pooled.send(120_000)

        XCTAssertEqual(seen, [120_000], "a ceiling that did not move must not churn validation")
        token.cancel()
    }


    // MARK: - The verdict publisher

    private func balance(confirmed: UInt64, unconfirmed: UInt64 = 0, locked: UInt64 = 0) -> WalletBalance {
        WalletBalance(confirmed: confirmed, unconfirmed: unconfirmed, immature: 0, locked: locked)
    }

    private func verdictEmissions(
        from start: WalletBalance, then updates: [WalletBalance],
        pooled: UInt64? = 100_000_000, pooledUpdates: [UInt64?] = []
    ) -> Int {
        let pooledSubject = CurrentValueSubject<UInt64?, Never>(pooled)
        let balanceSubject = CurrentValueSubject<WalletBalance?, Never>(start)
        var emissions = 0
        let token = SwiftDashSDKWalletState
            .sendVerdictInputsPublisher(pooled: pooledSubject.eraseToAnyPublisher(),
                                        balance: balanceSubject.eraseToAnyPublisher())
            .sink { emissions += 1 }
        updates.forEach { balanceSubject.send($0) }
        pooledUpdates.forEach { pooledSubject.send($0) }
        token.cancel()
        return emissions
    }

    func testTheVerdictIsReJudgedWhenThePooledFigureFirstArrivesWithoutMovingTheCeiling() {
        // The verdict needs the pooled figure known at all; its arrival can
        // leave min(pooled, walletSpendable) exactly where the fallback was.
        XCTAssertEqual(
            verdictEmissions(from: balance(confirmed: 100_000_000, unconfirmed: 50_000_000), then: [],
                             pooled: nil, pooledUpdates: [150_000_000]),
            2, "the current state, then the pooled figure")
    }

    func testTheVerdictIsReJudgedWhenOnlyTheUnconfirmedBucketMoves() {
        // Coins arriving or leaving the unconfirmed bucket decide between
        // "Insufficient funds" and "still confirming" with `spendable` put.
        XCTAssertEqual(
            verdictEmissions(from: balance(confirmed: 100_000_000, unconfirmed: 50_000_000),
                             then: [balance(confirmed: 100_000_000)]),
            2, "the current state, then the unconfirmed change")
    }

    func testTheVerdictIsReJudgedWhenCoinsConfirm() {
        XCTAssertEqual(
            verdictEmissions(from: balance(confirmed: 100_000_000, unconfirmed: 50_000_000),
                             then: [balance(confirmed: 150_000_000)]),
            2, "the current state, then the confirmation")
    }

    func testTheVerdictIsReJudgedWhenOnlyAnUnspendableBucketMoves() {
        // A locked or immature coin moves the pool's UTXO count, and with it
        // the fee reserve, while every spendable figure stays put.
        XCTAssertEqual(
            verdictEmissions(from: balance(confirmed: 100_000_000),
                             then: [balance(confirmed: 100_000_000, locked: 1_000_000)]),
            2)
    }

    func testARepeatedBalanceDoesNotChurnTheVerdict() {
        XCTAssertEqual(
            verdictEmissions(from: balance(confirmed: 100_000_000), then: [balance(confirmed: 100_000_000)]),
            1)
    }

    // MARK: Single-flight ownership of the pooled read

    func testASecondRequestDuringAReadCoalescesIntoOneRerun() {
        var slot = PooledReadSlot()
        let first = slot.begin()
        XCTAssertNotNil(first)
        XCTAssertNil(slot.begin(), "a second read must not run concurrently")
        XCTAssertNil(slot.begin(), "and a third must not queue a second rerun")
        XCTAssertTrue(slot.finish(first!), "the pending request becomes exactly one rerun")
        XCTAssertFalse(slot.rerunRequested)
    }

    func testAFinishedReadWithNoRequestsStartsNoRerun() {
        var slot = PooledReadSlot()
        let generation = slot.begin()!
        XCTAssertFalse(slot.finish(generation))
    }

    /// The reviewed race, in order: a read is cancelled, its replacement starts,
    /// and the cancelled one completes last. Before the generation guard it
    /// cleared the replacement's slot on its way out, which freed the slot for a
    /// third read while the second was still in flight — and the two then
    /// published in whatever order they finished.
    func testACancelledReadCompletingLastCannotTakeItsReplacementsSlot() {
        var slot = PooledReadSlot()
        let cancelled = slot.begin()!

        slot.cancel()
        let replacement = slot.begin()!
        XCTAssertNotEqual(cancelled, replacement)

        // The cancelled read resumes here, after the replacement has started.
        XCTAssertFalse(slot.owns(cancelled), "a cancelled read owns nothing")
        XCTAssertFalse(slot.finish(cancelled), "and cannot release the slot")
        XCTAssertTrue(slot.owns(replacement), "the replacement still holds it")

        XCTAssertFalse(slot.finish(replacement))
        XCTAssertNotNil(slot.begin(), "the slot is free once its owner releases it")
    }

    func testACancelledReadCannotConsumeTheReplacementsRerun() {
        var slot = PooledReadSlot()
        let cancelled = slot.begin()!
        slot.cancel()
        let replacement = slot.begin()!

        // A request arrives while the replacement runs, and belongs to it.
        XCTAssertNil(slot.begin())
        XCTAssertFalse(slot.finish(cancelled), "the cancelled read must not swallow it")
        XCTAssertTrue(slot.rerunRequested)
        XCTAssertTrue(slot.finish(replacement))
    }

    func testCancellingWithNothingInFlightLeavesTheSlotClaimable() {
        var slot = PooledReadSlot()
        slot.cancel()
        XCTAssertNotNil(slot.begin())
    }
}

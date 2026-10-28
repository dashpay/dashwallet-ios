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

    func testAnAmountThatFitsOnceIncomingFundsConfirmIsNamedAsConfirming() {
        // Just after a receive: 1 DASH confirmed, 2 DASH more in the pool still
        // waiting on a block or a lock. 2.5 DASH is on screen and refused.
        XCTAssertEqual(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 250_000_000,
                reserve: 1_000,
                sendable: 100_000_000,
                pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)),
            200_000_000)
    }

    func testAnAmountThatLeavesNoRoomForTheFeeOnceConfirmedIsStillInsufficient() {
        // The whole pool, once confirmed, still cannot pay amount + fee:
        // telling the user to wait would promise a send that then fails.
        let pool = pool(confirmed: 100_000_000, unconfirmed: 200_000_000)
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 300_000_000, reserve: 1_000, sendable: 100_000_000, pool: pool))
        XCTAssertEqual(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 299_999_000, reserve: 1_000, sendable: 100_000_000, pool: pool),
            200_000_000)
    }

    func testNothingConfirmedYetStillKeepsTheFeeReserve() {
        // A fee-aware ceiling floors at 0 here: 1 DASH received, none of it
        // confirmed, 1 DASH entered — it cannot also pay the fee.
        let pool = pool(confirmed: 0, unconfirmed: 100_000_000)
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 100_000_000, reserve: 300, sendable: 0, pool: pool))
        XCTAssertEqual(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 99_999_700, reserve: 300, sendable: 0, pool: pool),
            100_000_000)
    }

    func testAGapWithNothingConfirmingIsNeverCalledAWait() {
        // The pool holds more than the gate counts, but none of it is
        // confirming — a pooled figure not re-read yet, or an account the
        // SDK's pool does not fund from. Waiting changes nothing, so saying
        // "wait" here would never clear.
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 250_000_000,
                reserve: 0,
                sendable: 100_000_000,
                pool: pool(confirmed: 300_000_000, unconfirmed: 0)))
    }

    func testCoinJoinFundsDoNotShrinkTheReportedWait() {
        // Pool: 1 confirmed + 2 waiting; 1.5 DASH of confirmed CoinJoin lifts
        // the wallet-wide side, so `sendable` is 2.5. The wait is still 2.
        XCTAssertEqual(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 280_000_000,
                reserve: 0,
                sendable: 250_000_000,
                pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)),
            200_000_000)
    }

    func testAPooledFigureThatAlreadyCountsTheUnconfirmedCoinsMeansNoWait() {
        // Today's pooled figure includes unconfirmed coins; when it is the
        // smaller of the two (CoinJoin makes the wallet-wide one larger) the
        // gate already counts them, and waiting changes nothing.
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 350_000_000,
                reserve: 0,
                sendable: 300_000_000,
                pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)))
    }

    func testAReserveAboveEverythingThePoolWillHoldNeverClaimsAWait() {
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 1, reserve: 100_000, sendable: 0,
                pool: pool(confirmed: 0, unconfirmed: 50_000)))
    }

    func testAnAmountAboveEverythingThePoolWillHoldIsStillInsufficient() {
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 300_000_001,
                reserve: 0,
                sendable: 100_000_000,
                pool: pool(confirmed: 100_000_000, unconfirmed: 200_000_000)),
            "waiting would not make this fit")
    }

    func testAnUnreadablePoolNeverClaimsFundsAreConfirming() {
        XCTAssertNil(
            SwiftDashSDKWalletState.fundsStillConfirming(
                requested: 250_000_000, reserve: 0, sendable: 100_000_000, pool: nil))
    }

    func testAnAmountThatCannotFitIsRefusedWithoutReadingTheReserve() {
        // The reserve is a walk over every pooled UTXO on the main thread;
        // typing past everything the pool holds must not pay for it per key.
        var reserveReads = 0
        let verdict = SwiftDashSDKWalletState.fundsStillConfirming(
            requested: 400_000_000,
            lazyReserve: { reserveReads += 1; return 1_000 },
            sendable: 100_000_000,
            pool: pool(confirmed: 100_000_000, unconfirmed: 100_000_000))
        XCTAssertNil(verdict)
        XCTAssertEqual(reserveReads, 0)
    }

    func testAnAmountThatMayFitStillKeepsTheLazyReserve() {
        var reserveReads = 0
        let verdict = SwiftDashSDKWalletState.fundsStillConfirming(
            requested: 199_999_500,
            lazyReserve: { reserveReads += 1; return 1_000 },
            sendable: 100_000_000,
            pool: pool(confirmed: 100_000_000, unconfirmed: 100_000_000))
        XCTAssertNil(verdict, "fits only without the reserve, so still insufficient")
        XCTAssertEqual(reserveReads, 1)
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

    func testTheVerdictIsReJudgedWhenCoinsConfirmWithoutMovingTheCeiling() {
        XCTAssertEqual(
            verdictEmissions(from: balance(confirmed: 100_000_000, unconfirmed: 50_000_000),
                             then: [balance(confirmed: 100_000_000)]),
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

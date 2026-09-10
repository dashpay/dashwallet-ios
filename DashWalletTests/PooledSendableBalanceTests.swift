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

}

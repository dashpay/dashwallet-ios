//
//  CoinJoinMoveDestinationPolicyTests.swift
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

import XCTest
@testable import dashpay

/// Pins the one policy that decides what all three "move mixed coins" surfaces
/// offer — the post-sync popup and the durable Settings / Tools rows. The
/// numbers it encodes (credits → duffs, the fee reserve, the ×2 headroom) are
/// invisible in the UI, and getting them wrong either hides the Shielded route
/// from a wallet that could use it or offers a drain that cannot pay its fee.
final class CoinJoinMoveDestinationPolicyTests: XCTestCase {

    /// 200 000 credits = 200 duffs of pool fee, so the floor is
    /// (200 + 100 000) × 2 = 200 400 duffs.
    private let poolFeeCredits: UInt64 = 200_000
    private var floorDuffs: UInt64 { (poolFeeCredits / 1000 + WalletBalance.sendFeeReserveDuffs) * 2 }

    private func shieldedAvailable(
        hasShieldedAddress: Bool = true,
        poolFeeCredits: UInt64? = 200_000,
        balanceDuffs: UInt64
    ) -> Bool {
        CoinJoinMoveDestinationPolicy.shieldedDestinationAvailable(
            hasShieldedAddress: hasShieldedAddress,
            poolFeeCredits: poolFeeCredits,
            balanceDuffs: balanceDuffs)
    }

    // MARK: - Shielded viability

    func testNoShieldedAddressIsNeverAvailableHoweverLargeTheBalance() {
        XCTAssertFalse(shieldedAvailable(hasShieldedAddress: false, balanceDuffs: 100 * 100_000_000))
    }

    func testMissingPoolFeeEstimateFailsClosed() {
        XCTAssertFalse(shieldedAvailable(poolFeeCredits: nil, balanceDuffs: 100 * 100_000_000))
    }

    func testBalanceBelowTheEconomicFloorIsUnavailable() {
        XCTAssertFalse(shieldedAvailable(balanceDuffs: floorDuffs - 1))
    }

    func testBalanceExactlyAtTheEconomicFloorIsAvailable() {
        XCTAssertTrue(shieldedAvailable(balanceDuffs: floorDuffs))
    }

    func testBalanceAboveTheEconomicFloorIsAvailable() {
        XCTAssertTrue(shieldedAvailable(balanceDuffs: floorDuffs + 1))
    }

    func testZeroBalanceIsUnavailable() {
        XCTAssertFalse(shieldedAvailable(balanceDuffs: 0))
    }

    /// Pins the conversion and the headroom factor against a second fee value,
    /// so a change to either arithmetic fails here rather than in the field.
    func testFloorTracksThePoolFeeInCreditsNotDuffs() {
        // 1 000 000 credits = 1 000 duffs → floor (1 000 + 100 000) × 2 = 202 000.
        let floor: UInt64 = (1_000_000 / 1000 + WalletBalance.sendFeeReserveDuffs) * 2
        XCTAssertEqual(floor, 202_000)
        XCTAssertFalse(shieldedAvailable(poolFeeCredits: 1_000_000, balanceDuffs: floor - 1))
        XCTAssertTrue(shieldedAvailable(poolFeeCredits: 1_000_000, balanceDuffs: floor))
    }

    // MARK: - Durable menu rows

    func testMenuRowNeedsBothALeftoverAndAFinishedSync() {
        XCTAssertTrue(CoinJoinMoveDestinationPolicy.menuRowAvailable(hasLeftover: true, isChainSynced: true))
        XCTAssertFalse(CoinJoinMoveDestinationPolicy.menuRowAvailable(hasLeftover: true, isChainSynced: false))
        XCTAssertFalse(CoinJoinMoveDestinationPolicy.menuRowAvailable(hasLeftover: false, isChainSynced: true))
        XCTAssertFalse(CoinJoinMoveDestinationPolicy.menuRowAvailable(hasLeftover: false, isChainSynced: false))
    }

    func testEligibleBalanceOpensTheDestinationChoice() {
        XCTAssertEqual(
            CoinJoinMoveDestinationPolicy.menuRoute(isChainSynced: true, shieldedAvailable: true),
            .destinationChoice)
    }

    func testIneligibleBalanceOpensTheTransparentConfirmation() {
        XCTAssertEqual(
            CoinJoinMoveDestinationPolicy.menuRoute(isChainSynced: true, shieldedAvailable: false),
            .transparentConfirmation)
    }

    /// The regression that matters most: an unfinished sync must open nothing.
    /// Mapping it to the transparent confirmation would move mixed coins into
    /// the spendable balance — undoing the user's mixing — on the strength of a
    /// balance the scan is still discovering.
    func testUnfinishedSyncOpensNothingRatherThanTheTransparentFallback() {
        XCTAssertNil(CoinJoinMoveDestinationPolicy.menuRoute(isChainSynced: false, shieldedAvailable: false))
        XCTAssertNil(CoinJoinMoveDestinationPolicy.menuRoute(isChainSynced: false, shieldedAvailable: true))
    }
}

/// Pins the CoinJoin → Shielded input planning (ticket 32500): an asset lock
/// may spend at most 100 inputs, and its shield transition with an InstantSend
/// proof outgrows Platform's 20 480-byte limit from about 65, so an account
/// above 50 is consolidated onto one of its own addresses first, and the drain
/// waits for final inputs.
final class CoinJoinShieldPlannerTests: XCTestCase {

    // MARK: nextStep

    func testEmptyAccountHasNothingToMove() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 0, finalCount: 0), .nothingToMove)
    }

    func testThresholdIsBelowBothLimits() {
        XCTAssertEqual(CoinJoinShieldPlanner.maxAssetLockInputs, 100)
        XCTAssertEqual(CoinJoinShieldPlanner.consolidationThreshold, 50)
        // Below ~65 inputs, where an IS-proof transition passes 20 480 bytes.
        XCTAssertLessThan(CoinJoinShieldPlanner.consolidationThreshold, 65)
    }

    func testAtTheThresholdDrainsDirectly() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 50, finalCount: 50), .drain)
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 1, finalCount: 1), .drain)
    }

    func testJustOverTheThresholdConsolidates() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 51, finalCount: 51), .consolidate)
    }

    /// 65–100 coins: Core would accept the asset lock, but its shield
    /// transition with an InstantSend proof is too large for Platform.
    func testCoreAcceptableButTransitionTooLargeConsolidates() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 65, finalCount: 65), .consolidate)
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 100, finalCount: 100), .consolidate)
    }

    /// The ticket's wallet: 104 mixed coins, one over-cap drain refused by
    /// Core as `assetlocktx-too-many-inputs`.
    func testOverTheCapConsolidates() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 101, finalCount: 101), .consolidate)
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 104, finalCount: 104), .consolidate)
        // Finality does not matter above the cap — the sweep is a regular tx.
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 2_000, finalCount: 0), .consolidate)
    }

    /// After a consolidation the output is not final until InstantSend locks
    /// it; draining then would lock nothing (or only the final remainder).
    func testUnderTheCapWithPendingCoinsWaits() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 1, finalCount: 0), .awaitFinality(pending: 1))
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 3, finalCount: 1), .awaitFinality(pending: 2))
    }

    func testFinalCountAboveCountIsClamped() {
        XCTAssertEqual(CoinJoinShieldPlanner.nextStep(utxoCount: 2, finalCount: 5), .drain)
    }

    // MARK: isFinal

    func testMinedUtxoIsFinal() {
        XCTAssertTrue(CoinJoinShieldPlanner.isFinal(height: 2_556_386, txid: Data([1]), instantLockedTxids: []))
    }

    func testInstantLockedUtxoIsFinal() {
        XCTAssertTrue(CoinJoinShieldPlanner.isFinal(height: 0, txid: Data([1]), instantLockedTxids: [Data([1])]))
    }

    func testMempoolUtxoIsNotFinal() {
        XCTAssertFalse(CoinJoinShieldPlanner.isFinal(height: 0, txid: Data([1]), instantLockedTxids: [Data([2])]))
    }

    // MARK: consolidationSettled

    func testConsolidationSettledNeedsAFinalOutputPerTransaction() {
        let a = Data([0xaa]), b = Data([0xbb]), other = Data([0xcc])
        XCTAssertFalse(CoinJoinShieldPlanner.consolidationSettled(
            consolidationTxids: [a, b],
            utxos: [(a, true), (other, true)]))
        XCTAssertFalse(CoinJoinShieldPlanner.consolidationSettled(
            consolidationTxids: [a, b],
            utxos: [(a, true), (b, false)]))
        XCTAssertTrue(CoinJoinShieldPlanner.consolidationSettled(
            consolidationTxids: [a, b],
            utxos: [(a, true), (b, true), (other, false)]))
    }

    func testNoConsolidationIsTriviallySettled() {
        XCTAssertTrue(CoinJoinShieldPlanner.consolidationSettled(consolidationTxids: [], utxos: []))
    }

    // MARK: Chunk planning (the consolidation reuses the sweep's chunking)

    private func chunkSizes(_ n: Int) -> [Int] {
        SwiftDashSDKTransactionSender.balancedChunks(
            Array(0..<n), maxPerChunk: SwiftDashSDKTransactionSender.maxInputsPerSweep
        ).map(\.count)
    }

    func testChunkPlanning() {
        XCTAssertEqual(SwiftDashSDKTransactionSender.maxInputsPerSweep, 500)
        XCTAssertEqual(chunkSizes(0), [])
        XCTAssertEqual(chunkSizes(104), [104])
        XCTAssertEqual(chunkSizes(500), [500])
        XCTAssertEqual(chunkSizes(501), [251, 250])
        XCTAssertEqual(chunkSizes(1_000), [500, 500])
        XCTAssertEqual(chunkSizes(1_001), [334, 334, 333])
    }

    func testChunksPreserveOrderAndCoverEveryInput() {
        let chunks = SwiftDashSDKTransactionSender.balancedChunks(Array(0..<1_234), maxPerChunk: 500)
        XCTAssertEqual(chunks.flatMap { $0 }, Array(0..<1_234))
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 500 })
    }

    /// A consolidation produces one output per chunk; even very large
    /// accounts land at or under the direct-drain threshold after one pass.
    func testOneConsolidationPassFitsUnderTheThreshold() {
        XCTAssertLessThanOrEqual(chunkSizes(25_000).count, CoinJoinShieldPlanner.consolidationThreshold)
    }

    // MARK: Checklist

    func testPreparedChecklistIndex() {
        typealias VM = CoinJoinMoveFundsViewModel
        XCTAssertNil(VM.preparedChecklistIndex(preparation: nil, phase: .idle))
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .authorizing, phase: .idle), 0)
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .preparingCoins, phase: .idle), 1)
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .done, phase: .signing), 2)
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .done, phase: .locking), 2)
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .done, phase: .proving), 3)
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .done, phase: .broadcasting), 4)
        XCTAssertEqual(VM.preparedChecklistIndex(preparation: .done, phase: .success), 5)
        XCTAssertNil(VM.preparedChecklistIndex(preparation: .done, phase: .failed("x")))
    }
}

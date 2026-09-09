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

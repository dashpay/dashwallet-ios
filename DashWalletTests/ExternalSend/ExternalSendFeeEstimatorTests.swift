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

@testable import dashpay
import SwiftDashSDK
import XCTest

/// The per-route fee estimate of the Send screen (AC-01b, AC-08 input): only the SDK and wallet edge
/// (`SendFeeSourcing`) is scripted. The fee comes back in the source's unit: duffs for Core, Shielded and
/// Platform, credits for Identity (as `AmountRules` counts them); a failing edge is `.unavailable`, never a fee.
final class ExternalSendFeeEstimatorTests: XCTestCase {
    private enum EdgeError: Error { case noAnswer }

    private final class FakeSources: SendFeeSourcing, @unchecked Sendable {
        var coreFeeDuffs: UInt64? = 2_250
        var shieldedFeeCredits: [PlatformWalletManager.ShieldedFeeKind: UInt64] = [
            .transfer: 7_000_001, .unshield: 9_000_002, .withdrawal: 11_000_003, .identityTopUpFromPool: 13_000_004
        ]
        var addressFundingFeeCredits: UInt64? = 5_000_500
        var withdrawalFeeCredits: UInt64? = 3_000_001
        private(set) var coreAmounts: [UInt64] = []
        private(set) var shieldedCalls: [(kind: PlatformWalletManager.ShieldedFeeKind, numActions: Int)] = []
        private(set) var fundingShapes: [(inputs: Int, outputs: Int)] = []
        private(set) var withdrawalReads = 0
        private(set) var totalReads = 0

        func coreSendFeeDuffs(amountDuffs: UInt64) async throws -> UInt64 {
            totalReads += 1
            coreAmounts.append(amountDuffs)
            guard let coreFeeDuffs else { throw EdgeError.noAnswer }
            return coreFeeDuffs
        }

        func shieldedFeeCredits(kind: PlatformWalletManager.ShieldedFeeKind, numActions: Int) async throws -> UInt64 {
            totalReads += 1
            shieldedCalls.append((kind, numActions))
            guard let fee = shieldedFeeCredits[kind] else { throw EdgeError.noAnswer }
            return fee
        }

        func addressFundingFeeCredits(inputCount: Int, outputCount: Int) async throws -> UInt64 {
            totalReads += 1
            fundingShapes.append((inputCount, outputCount))
            guard let addressFundingFeeCredits else { throw EdgeError.noAnswer }
            return addressFundingFeeCredits
        }

        func platformWithdrawalFeeCredits() async throws -> UInt64 {
            totalReads += 1
            withdrawalReads += 1
            guard let withdrawalFeeCredits else { throw EdgeError.noAnswer }
            return withdrawalFeeCredits
        }

        func failEverything() {
            coreFeeDuffs = nil
            shieldedFeeCredits = [:]
            addressFundingFeeCredits = nil
            withdrawalFeeCredits = nil
        }
    }

    private let allRoutes: [SendRoute] = [
        .coreToCore, .coreToShielded, .coreToPlatform, .coreToIdentity,
        .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity,
        .platformToCore, .platformToShielded, .platformToPlatform, .platformToIdentity,
        .identityToCore, .identityToPlatform, .identityToIdentity
    ]
    private let amount: UInt64 = 123_456

    private func estimate(_ route: SendRoute, _ sources: FakeSources) async -> SendFeeEstimate {
        await ExternalSendFeeEstimator(sources: sources).estimate(route: route, amount: amount)
    }

    // MARK: - One case per route

    func testCoreToCoreIsTheWalletSendFeeInDuffsForThatAmount() async {
        let sources = FakeSources()
        let result = await estimate(.coreToCore, sources)
        XCTAssertEqual(result, .fee(2_250))
        XCTAssertEqual(sources.coreAmounts, [amount])
    }

    func testCoreToShieldedIsTheShieldPoolFeeRoundedUpToWholeDuffs() async {
        let sources = FakeSources()
        // (transfer, 2) 7_000_001 credits + asset-lock base cost 50_000_000 = 57_000_001 credits -> 57_001 duffs.
        // Plus the asset lock's own L1 miner fee, 2_250 duffs, which the Core wallet pays on top.
        let result = await estimate(.coreToShielded, sources)
        XCTAssertEqual(result, .fee(57_001 + 2_250, assetLockMinerFee: 2_250))
        XCTAssertEqual(sources.shieldedCalls.map(\.kind), [.transfer])
        XCTAssertEqual(sources.shieldedCalls.map(\.numActions), [2])
    }

    func testCoreToPlatformIsTheAddressFundingReserveRoundedUpToWholeDuffsPlusTheL1MinerFee() async {
        let sources = FakeSources()
        let result = await estimate(.coreToPlatform, sources)
        XCTAssertEqual(result, .fee(5_001 + 2_250, assetLockMinerFee: 2_250))
        XCTAssertEqual(sources.fundingShapes.map(\.inputs), [CoreToPlatformAmountPolicy.addressFundingInputCount])
        XCTAssertEqual(sources.fundingShapes.map(\.outputs), [CoreToPlatformAmountPolicy.addressFundingOutputCount])
    }

    /// The top-up's Platform fee comes out of the asset lock, so the identity receives less; the sender pays only the
    /// lock's L1 miner fee on top of the amount.
    func testCoreToIdentityIsTheL1MinerFeeOnly() async {
        let result = await estimate(.coreToIdentity, FakeSources())
        XCTAssertEqual(result, .fee(2_250, assetLockMinerFee: 2_250))
    }

    func testCoreAssetLockRoutesWithoutAnL1FeeAreUnavailable() async {
        for route in [SendRoute.coreToShielded, .coreToPlatform, .coreToIdentity] {
            let sources = FakeSources()
            sources.coreFeeDuffs = nil
            let result = await estimate(route, sources)
            XCTAssertEqual(result, .unavailable, "\(route)")
        }
    }

    func testOnlyCoreAssetLockRoutesCarryAnAssetLockMinerFee() async {
        for route in allRoutes where ![.coreToShielded, .coreToPlatform, .coreToIdentity].contains(route) {
            let result = await estimate(route, FakeSources())
            XCTAssertEqual(result.assetLockMinerFee, 0, "\(route)")
        }
    }

    func testShieldedToCoreIsTheWithdrawalFloorOfTwoActionsInDuffs() async {
        let sources = FakeSources()
        let result = await estimate(.shieldedToCore, sources)
        XCTAssertEqual(result, .fee(11_001)) // 11_000_003 credits, rounded up
        XCTAssertEqual(sources.shieldedCalls.map(\.kind), [.withdrawal])
        XCTAssertEqual(sources.shieldedCalls.map(\.numActions), [2])
    }

    func testShieldedToShieldedIsTheTransferFloorOfTwoActionsInDuffs() async {
        let sources = FakeSources()
        let result = await estimate(.shieldedToShielded, sources)
        XCTAssertEqual(result, .fee(7_001))
        XCTAssertEqual(sources.shieldedCalls.map(\.kind), [.transfer])
        XCTAssertEqual(sources.shieldedCalls.map(\.numActions), [2])
    }

    func testShieldedToPlatformIsTheUnshieldFloorOfTwoActionsInDuffs() async {
        let sources = FakeSources()
        let result = await estimate(.shieldedToPlatform, sources)
        XCTAssertEqual(result, .fee(9_001))
        XCTAssertEqual(sources.shieldedCalls.map(\.kind), [.unshield])
        XCTAssertEqual(sources.shieldedCalls.map(\.numActions), [2])
    }

    func testShieldedToIdentityIsThePoolTopUpFloorOfTwoActionsInDuffs() async {
        let sources = FakeSources()
        let result = await estimate(.shieldedToIdentity, sources)
        XCTAssertEqual(result, .fee(13_001)) // 13_000_004 credits, rounded up
        XCTAssertEqual(sources.shieldedCalls.map(\.kind), [.identityTopUpFromPool])
        XCTAssertEqual(sources.shieldedCalls.map(\.numActions), [2])
    }

    func testPlatformToCoreIsTheWithdrawalPreflightFeeInDuffs() async {
        let sources = FakeSources()
        let result = await estimate(.platformToCore, sources)
        XCTAssertEqual(result, .fee(3_001)) // 3_000_001 credits, rounded up
        XCTAssertEqual(sources.withdrawalReads, 1)
    }

    func testPlatformToShieldedIsTheShieldTransferFloorOfTwoActionsInDuffs() async {
        let sources = FakeSources()
        let result = await estimate(.platformToShielded, sources)
        XCTAssertEqual(result, .fee(7_001))
        XCTAssertEqual(sources.shieldedCalls.map(\.kind), [.transfer])
        XCTAssertEqual(sources.shieldedCalls.map(\.numActions), [2])
    }

    func testPlatformToPlatformIsTheTransferFeeHeadroomInDuffs() async {
        let result = await estimate(.platformToPlatform, FakeSources())
        XCTAssertEqual(result, .fee(100_000)) // 100_000_000 credits, the Platform transfer headroom
    }

    func testPlatformToIdentityIsTheObservedTopUpFeeInDuffs() async {
        let result = await estimate(.platformToIdentity, FakeSources())
        XCTAssertEqual(result, .fee(IdentityTopUpViewModel.observedTopUpTransitionFeeCredits / 1000))
    }

    func testIdentityToCoreIsTheWithdrawalMinimumInCredits() async {
        let result = await estimate(.identityToCore, FakeSources())
        XCTAssertEqual(result, .fee(IdentityWithdrawViewModel.minimumFeeCredits(target: .transparent)))
    }

    func testIdentityToPlatformIsTheCreditTransferMinimumInCredits() async {
        let result = await estimate(.identityToPlatform, FakeSources())
        XCTAssertEqual(result, .fee(IdentityWithdrawViewModel.minimumFeeCredits(target: .platform)))
    }

    func testIdentityToIdentityIsTheCreditTransferMinimumInCredits() async {
        let result = await estimate(.identityToIdentity, FakeSources())
        XCTAssertEqual(result, .fee(100_000)) // STATE_TRANSITION_MIN_FEES_VERSION1 credit_transfer
    }

    func testEveryRouteGivesAFeeWhenTheEdgeAnswers() async {
        for route in allRoutes {
            let result = await estimate(route, FakeSources())
            guard case .fee(let fee, _) = result else { XCTFail("\(route): expected a fee, got \(result)"); continue }
            XCTAssertGreaterThan(fee, 0, "\(route): a zero fee is never assumed")
        }
    }

    // MARK: - No answer (AC-01b)

    func testEdgeBackedRoutesAreUnavailableNotZeroWhenTheirEdgeFails() async {
        let sources = FakeSources()
        sources.failEverything()
        for route in [SendRoute.coreToCore, .coreToShielded, .coreToPlatform, .shieldedToCore, .shieldedToShielded,
                      .shieldedToPlatform, .shieldedToIdentity, .platformToCore, .platformToShielded] {
            let result = await estimate(route, sources)
            XCTAssertEqual(result, .unavailable, "\(route)")
            XCTAssertNotEqual(result, .fee(0), "\(route)")
        }
    }

    func testOnlyTheFailingEdgeMakesItsRoutesUnavailable() async {
        let sources = FakeSources()
        sources.coreFeeDuffs = nil
        let coreResult = await estimate(.coreToCore, sources)
        let shieldedResult = await estimate(.shieldedToShielded, sources)
        XCTAssertEqual(coreResult, .unavailable)
        XCTAssertEqual(shieldedResult, .fee(7_001))
    }

    func testAMissingShieldedKindIsUnavailableForRoutesThatNeedIt() async {
        let sources = FakeSources()
        sources.shieldedFeeCredits[.unshield] = nil
        let unshield = await estimate(.shieldedToPlatform, sources)
        let transfer = await estimate(.shieldedToShielded, sources)
        XCTAssertEqual(unshield, .unavailable)
        XCTAssertEqual(transfer, .fee(7_001))
    }

    func testAFeeThatOverflowsWhenTheAssetLockCostIsAddedIsUnavailable() async {
        let sources = FakeSources()
        sources.shieldedFeeCredits[.transfer] = UInt64.max
        let result = await estimate(.coreToShielded, sources)
        XCTAssertEqual(result, .unavailable)
    }

    func testRetryAsksTheEdgeAgainAndRecovers() async {
        let sources = FakeSources()
        let estimator = ExternalSendFeeEstimator(sources: sources)
        sources.coreFeeDuffs = nil
        let first = await estimator.estimate(route: .coreToCore, amount: amount)
        XCTAssertEqual(first, .unavailable)
        sources.coreFeeDuffs = 1_800
        let second = await estimator.estimate(route: .coreToCore, amount: amount)
        XCTAssertEqual(second, .fee(1_800))
        XCTAssertEqual(sources.coreAmounts.count, 2, "a failure is never cached")
    }

    func testEachCallReadsTheEdgeAgainSoTheLatestAmountIsEstimated() async {
        let sources = FakeSources()
        let estimator = ExternalSendFeeEstimator(sources: sources)
        _ = await estimator.estimate(route: .coreToCore, amount: 1_000)
        _ = await estimator.estimate(route: .coreToCore, amount: 2_000)
        XCTAssertEqual(sources.coreAmounts, [1_000, 2_000])
    }

    // MARK: - Fixed minimums

    func testIdentityRoutesNeedNoNetworkRead() async {
        let sources = FakeSources()
        for route in [SendRoute.identityToCore, .identityToPlatform, .identityToIdentity, .platformToPlatform] {
            _ = await estimate(route, sources)
        }
        XCTAssertEqual(sources.totalReads, 0)
    }
}

//
//  Created by Bartosz Rozwarski
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

import Foundation

/// Masternode APY estimate, DashSync-free.
///
/// A pure-Swift port of the deterministic block-reward math from the retired
/// `DSChain+DashWallet` category (subsidy curve → masternode payment share →
/// payouts per year / collateral). Consensus constants are compiled in per
/// network (`WalletEnvironment.networkKind`); the chain height comes from
/// SwiftDashSDK's SPV coordinator.
///
/// This is the ESTIMATED figure — same as what the app has effectively shown
/// since M6: the masternode count is the fixed `estimatedMasternodeCount`
/// (the category's live `validMasternodeCount` path read a DashSync
/// masternode list that no longer syncs, so its nil-fallback ran the same
/// fixed-count estimate). TODO(masternode-stats-ffi): replace the fixed count
/// with the live virtual count (regular + 4×evo) once the upstream
/// masternode-list stats FFI lands.
///
/// The difficulty input is a per-network constant rather than a chain-tip
/// read: at every height this calculator can see, the subsidy base CLAMPS —
/// mainnet difficulty is orders of magnitude past the 5-DASH floor, and
/// testnet difficulty stays far below the ~86 threshold where the GPU-era
/// branch would leave the 25-DASH cap — so the constant reproduces the
/// category's output exactly on both networks.
enum MasternodeAPYCalculator {
    private static let blockTargetSpacing = 2.625 * 60
    /// 1000 DASH collateral, in duffs (DashSync's MASTERNODE_COST).
    private static let masternodeCostDuffs: UInt64 = 100_000_000_000
    /// The category's fixed estimate; see the header note on the live count.
    private static let estimatedMasternodeCount: UInt64 = 3800

    /// Per-network consensus constants, copied verbatim from the
    /// `DSChain+DashWallet` category (which read them from DashSync), except
    /// `core20Height` which the category fetched via the
    /// `chain_core20_activation_height` FFI — values verified against Dash
    /// Core `chainparams.cpp` (`consensus.V20Height`).
    private struct Consensus {
        let increaseBlockHeight: UInt64
        let period: UInt64
        let brrHeight: UInt64
        let superblockCycle: UInt64
        let budgetPaymentsStartBlock: UInt64
        let subsidyDecreaseBlockCount: UInt64
        let core20Height: UInt64
        let constantDifficulty: Double
        /// Height floor used before the first SPV tick (see `estimatedAPY`).
        let referenceHeight: UInt64

        static let mainnet = Consensus(
            increaseBlockHeight: 158_000,
            period: 576 * 30,
            brrHeight: 1_374_912,
            superblockCycle: 16_616,
            budgetPaymentsStartBlock: 328_008,
            subsidyDecreaseBlockCount: 210_240,
            core20Height: 1_987_776,
            constantDifficulty: 100_000_000, // any post-ASIC value clamps the base to the 5-DASH floor
            referenceHeight: 1_987_776)

        static let testnet = Consensus(
            increaseBlockHeight: 4030,
            period: 10,
            brrHeight: 387_500,
            superblockCycle: 24,
            budgetPaymentsStartBlock: 4100,
            subsidyDecreaseBlockCount: 210_240,
            core20Height: 905_100,
            constantDifficulty: 1, // any low-diff value clamps the base to the 25-DASH cap
            referenceHeight: 905_100)

        // The category's DevNet arm — used whenever the app runs on a
        // devnet (generic dash defaults; a specific devnet may differ).
        static let devnet = Consensus(
            increaseBlockHeight: 4030,
            period: 10,
            brrHeight: 300,
            superblockCycle: 24,
            budgetPaymentsStartBlock: 4100,
            subsidyDecreaseBlockCount: 210_240,
            core20Height: 300,
            constantDifficulty: 1,
            referenceHeight: 300)

        static func current() -> Consensus {
            switch WalletEnvironment.networkKind {
            case .mainnet: return .mainnet
            case .testnet: return .testnet
            case .devnet: return .devnet
            }
        }
    }

    /// The estimated masternode APY in percent (e.g. 5.8), computed at the
    /// SPV tip. Before the first SPV tick (both published heights still 0)
    /// the per-network v20 activation height stands in — every payment-share
    /// branch is saturated past it, so only the subsidy-decline count can
    /// differ, and the first real tick corrects it.
    static func estimatedAPY() -> Double {
        let consensus = Consensus.current()
        let coordinator = SwiftDashSDKSPVCoordinator.shared
        var height = UInt64(max(coordinator.tipHeight, coordinator.bestPeerHeight))
        if height == 0 {
            height = consensus.referenceHeight
        }
        return apy(atHeight: height,
                   difficulty: consensus.constantDifficulty,
                   masternodeCount: estimatedMasternodeCount,
                   consensus: consensus)
    }

    private static func apy(atHeight height: UInt64,
                            difficulty: Double,
                            masternodeCount: UInt64,
                            consensus: Consensus) -> Double {
        let daysPerYear = 365.242199
        let secondsPerDay: Double = 24 * 60 * 60

        let blockReward = blockInflation(height: height, difficulty: difficulty, consensus: consensus)
        let masternodeReward = masternodePayment(height: height, blockReward: blockReward, consensus: consensus)

        let blocksPerYear = daysPerYear * secondsPerDay / blockTargetSpacing
        let payoutsPerYear = blocksPerYear / Double(masternodeCount)

        return 100.0 * Double(masternodeReward) * payoutsPerYear / Double(masternodeCostDuffs)
    }

    /// Port of `calculateblockInflationWithHeight:nPrevBits:fSuperblockPartOnly:`
    /// with `fSuperblockPartOnly = NO` and the nBits→difficulty conversion
    /// replaced by the constant-difficulty input (see the header note). The
    /// pre-5465 "early ages" and mainnet low-height bug branches are
    /// unreachable at any height this calculator sees and are not ported.
    private static func blockInflation(height: UInt64, difficulty: Double, consensus: Consensus) -> UInt64 {
        let prevHeight = height - 1

        // GPU/ASIC mining era: 2222222/(((x+2600)/9)^2), clamped [5, 25].
        var subsidyBase = Int64(2_222_222.0 / pow((difficulty + 2600.0) / 9.0, 2.0))
        if subsidyBase > 25 {
            subsidyBase = 25
        } else if subsidyBase < 5 {
            subsidyBase = 5
        }

        var subsidy = UInt64(subsidyBase) * 100_000_000
        // Yearly decline of production by ~7.1% per year.
        var i = consensus.subsidyDecreaseBlockCount
        while i <= prevHeight {
            subsidy = subsidy - subsidy / 14
            i += consensus.subsidyDecreaseBlockCount
        }

        let treasuryPart: UInt64 = prevHeight >= consensus.core20Height ? 20 : 10 // parts per 100
        let superblockPart = prevHeight > consensus.budgetPaymentsStartBlock ? (subsidy * treasuryPart) / 100 : 0

        return subsidy - superblockPart
    }

    /// Port of `calculateMasternodePaymentWithHeight:blockReward:`.
    private static func masternodePayment(height: UInt64, blockReward: UInt64, consensus: Consensus) -> UInt64 {
        let periods: [UInt64] = [
            513, 526, 533, 540, 546, 552, 557, 562, 567, 572,
            577, 582, 585, 588, 591, 594, 597, 599, 600,
        ]

        var ret = blockReward / 5

        let increase = consensus.increaseBlockHeight
        let period = consensus.period
        if height > increase { ret += blockReward / 20 }
        if height > increase + period { ret += blockReward / 20 }
        if height > increase + period * 2 { ret += blockReward / 20 }
        if height > increase + period * 3 { ret += blockReward / 40 }
        if height > increase + period * 4 { ret += blockReward / 40 }
        if height > increase + period * 5 { ret += blockReward / 40 }
        if height > increase + period * 6 { ret += blockReward / 40 }
        if height > increase + period * 7 { ret += blockReward / 40 }
        if height > increase + period * 9 { ret += blockReward / 40 }

        if height < consensus.brrHeight {
            // Block Reward Reallocation not activated yet.
            return ret
        }

        // Actual reallocation starts in the cycle after the activation one.
        let reallocStart = consensus.brrHeight - consensus.brrHeight % consensus.superblockCycle + consensus.superblockCycle
        if height < reallocStart {
            return ret
        }

        if height >= consensus.core20Height {
            // Post-v20: block reward is 80% of the subsidy (20% treasury);
            // the MN share is 75% of the block reward (= 60% of the subsidy).
            return blockReward * 3 / 4
        }

        let reallocCycle = consensus.superblockCycle * 3
        let currentPeriod = min((height - reallocStart) / reallocCycle, UInt64(periods.count - 1))
        return (blockReward * periods[Int(currentPeriod)]) / 1000
    }
}

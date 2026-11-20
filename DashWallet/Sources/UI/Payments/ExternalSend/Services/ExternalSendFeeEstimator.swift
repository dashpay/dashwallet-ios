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

import Foundation
import SwiftDashSDK

/// A per-route fee estimate. `fee` is in the unit of the route's source: duffs for Core, Shielded and
/// Platform sources, credits for Identity sources (as `AmountRules` counts them). On the Core asset-lock routes
/// `assetLockMinerFee` is the part of `fee` the lock transaction pays the Core miners; it is 0 on every other
/// route. `unavailable` means the fee could not be worked out; it is never a zero fee.
enum SendFeeEstimate: Equatable {
    case fee(UInt64, assetLockMinerFee: UInt64 = 0)
    case unavailable

    var assetLockMinerFee: UInt64 {
        if case .fee(_, let minerFee) = self { return minerFee }
        return 0
    }
}

@MainActor
protocol SendFeeEstimating {
    func estimate(route: SendRoute, amount: UInt64) async -> SendFeeEstimate
}

extension SendRoute {
    /// The routes whose `ExternalSendFeeEstimator` fee ignores the amount: the Platform withdrawal preflight and the
    /// fixed Platform transfer, top-up and Identity fees. Core, Shielded and the asset-lock routes are left out.
    var hasAmountIndependentFee: Bool {
        switch self {
        case .platformToCore, .platformToPlatform, .platformToIdentity, .identityToCore, .identityToPlatform,
             .identityToIdentity:
            return true
        case .coreToCore, .coreToShielded, .coreToPlatform, .coreToIdentity, .shieldedToCore, .shieldedToShielded,
             .shieldedToPlatform, .shieldedToIdentity, .platformToShielded:
            return false
        }
    }
}

/// The SDK and wallet edge of the estimate. Every method throws when it cannot answer.
protocol SendFeeSourcing: Sendable {
    func coreSendFeeDuffs(amountDuffs: UInt64) async throws -> UInt64
    func shieldedFeeCredits(kind: PlatformWalletManager.ShieldedFeeKind, numActions: Int) async throws -> UInt64
    func addressFundingFeeCredits(inputCount: Int, outputCount: Int) async throws -> UInt64
    func platformWithdrawalFeeCredits() async throws -> UInt64
}

struct ExternalSendFeeEstimator: SendFeeEstimating {
    private static let shieldedActionCount = 2

    let sources: SendFeeSourcing

    nonisolated init(sources: SendFeeSourcing = LiveSendFeeSources()) {
        self.sources = sources
    }

    func estimate(route: SendRoute, amount: UInt64) async -> SendFeeEstimate {
        do {
            switch route {
            case .coreToShielded, .coreToPlatform, .coreToIdentity:
                return try await assetLockEstimate(route: route, amount: amount)
            default:
                guard let fee = try await fee(route: route, amount: amount), fee > 0 else { return .unavailable }
                return .fee(fee)
            }
        } catch {
            return .unavailable
        }
    }

    /// The Platform side's fee plus the L1 miner fee the asset-lock transaction pays on top of the lock. The miner fee
    /// is the pool-sized estimate the old Send reserves for a Max send, so it never under-counts what leaves Core.
    private func assetLockEstimate(route: SendRoute, amount: UInt64) async throws -> SendFeeEstimate {
        guard let platformFee = try await assetLockPlatformFee(route: route) else { return .unavailable }
        let minerFee = try await sources.coreSendFeeDuffs(amountDuffs: amount)
        let (total, overflow) = platformFee.addingReportingOverflow(minerFee)
        guard !overflow, minerFee > 0 else { return .unavailable }
        return .fee(total, assetLockMinerFee: minerFee)
    }

    /// `nil` when the sum of the parts overflows.
    private func fee(route: SendRoute, amount: UInt64) async throws -> UInt64? {
        switch route {
        case .coreToCore:
            return try await sources.coreSendFeeDuffs(amountDuffs: amount)
        case .coreToShielded, .coreToPlatform, .coreToIdentity:
            preconditionFailure("\(route) is estimated by assetLockEstimate")
        case .shieldedToCore, .shieldedToShielded, .shieldedToPlatform, .shieldedToIdentity:
            return try await shieldedSourceFee(route: route)
        case .platformToCore:
            return try await Self.duffs(sources.platformWithdrawalFeeCredits())
        case .platformToShielded:
            return try await Self.duffs(shieldedFee(.transfer))
        case .platformToPlatform:
            return Self.duffs(SendViewModel.platformTransferFeeReserveCredits)
        case .platformToIdentity:
            return Self.duffs(IdentityTopUpViewModel.observedTopUpTransitionFeeCredits)
        case .identityToCore:
            return IdentityWithdrawViewModel.minimumFeeCredits(target: .transparent)
        case .identityToPlatform:
            return IdentityWithdrawViewModel.minimumFeeCredits(target: .platform)
        case .identityToIdentity:
            return IdentityWithdrawViewModel.identityCreditTransferMinimumFeeCredits
        }
    }

    /// What the sender pays the Platform side, in duffs: the Shielded pool fee and the address-funding reserve go into
    /// the lock on top of the amount. An identity top-up pays its Platform fee out of the lock, so the identity
    /// receives less and the sender pays nothing more.
    private func assetLockPlatformFee(route: SendRoute) async throws -> UInt64? {
        switch route {
        case .coreToShielded:
            return try await CoreToShieldedAmountPolicy.poolFeeCredits(addingBaseCostTo: shieldedFee(.transfer))
                .map(CoreToShieldedAmountPolicy.poolFeeDuffs(poolFeeCredits:))
        case .coreToPlatform:
            let credits = try await sources.addressFundingFeeCredits(
                inputCount: CoreToPlatformAmountPolicy.addressFundingInputCount,
                outputCount: CoreToPlatformAmountPolicy.addressFundingOutputCount)
            return CoreToPlatformAmountPolicy.reserveDuffs(reserveCredits: credits)
        case .coreToIdentity:
            return 0
        default:
            preconditionFailure("\(route) is not a Core asset-lock route")
        }
    }

    private func shieldedSourceFee(route: SendRoute) async throws -> UInt64? {
        switch route {
        case .shieldedToCore:
            return try await Self.duffs(shieldedFee(.withdrawal))
        case .shieldedToPlatform:
            return try await Self.duffs(shieldedFee(.unshield))
        case .shieldedToIdentity:
            return try await Self.duffs(shieldedFee(.identityTopUpFromPool))
        default:
            return try await Self.duffs(shieldedFee(.transfer))
        }
    }

    private func shieldedFee(_ kind: PlatformWalletManager.ShieldedFeeKind) async throws -> UInt64 {
        try await sources.shieldedFeeCredits(kind: kind, numActions: Self.shieldedActionCount)
    }

    private static func duffs(_ credits: UInt64) -> UInt64 {
        CoreToShieldedAmountPolicy.poolFeeDuffs(poolFeeCredits: credits)
    }
}

/// The live fee edge: the pool-sized Core fee of the transaction sender, the shielded and address-funding
/// estimates of the running `PlatformWalletManager`, and the Platform withdrawal preflight.
struct LiveSendFeeSources: SendFeeSourcing {
    private struct Unavailable: Error {}

    /// The pool-sized estimate does not depend on the amount; it throws when the spendable accounts cannot be read.
    func coreSendFeeDuffs(amountDuffs: UInt64) async throws -> UInt64 {
        guard let fee = SwiftDashSDKTransactionSender.poolSizedSendFeeDuffs() else { throw Unavailable() }
        return fee
    }

    func shieldedFeeCredits(kind: PlatformWalletManager.ShieldedFeeKind, numActions: Int) async throws -> UInt64 {
        try await MainActor.run {
            guard let manager = SwiftDashSDKHost.shared.manager else { throw Unavailable() }
            return try manager.estimateShieldedFee(kind: kind, numActions: numActions)
        }
    }

    func addressFundingFeeCredits(inputCount: Int, outputCount: Int) async throws -> UInt64 {
        try await MainActor.run {
            guard let manager = SwiftDashSDKHost.shared.manager else { throw Unavailable() }
            return try manager.estimateAddressFundingFee(inputCount: inputCount, outputCount: outputCount)
        }
    }

    func platformWithdrawalFeeCredits() async throws -> UInt64 {
        try await PlatformAddressSyncCoordinator.shared.preflightWithdrawal().estimatedFee
    }
}

//
//  InternalTransferSummaryFigures.swift
//  DashWallet
//

import Foundation
import SwiftDashSDK

/// The numbers and names the confirm sheet's summary card shows, derived from
/// the route.
///
/// Lifted out of the sheet because it is fee math: the SDK is asked to price
/// four of the six routes, and Core → Shielded reconstructs the executed lock
/// value. A SwiftUI `View` is the wrong place for that — it is also the reason
/// none of it could be exercised without rendering a sheet.
///
/// Every value fails closed. An unavailable estimate is `nil`, which the sheet
/// renders as "—" rather than a number it cannot stand behind; `canContinue`
/// has already refused the transfer by then.
@MainActor
enum InternalTransferSummaryFigures {

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// Flat fee estimate (credits) for `route`, computed offline by the SDK
    /// against the latest protocol version, so it matches the fee the SDK will
    /// charge. `nil` when the estimate is unavailable.
    ///
    /// `withdrawalFeeCredits` is only read for `.platformToCore`, where the
    /// preflight has already netted the exact transition fee out of the payout.
    static func networkFeeCredits(
        route: InternalTransferRoute,
        withdrawalFeeCredits: UInt64?
    ) -> UInt64? {
        switch route {
        case .coreToShielded:
            // The lock charges the fee rounded UP to a whole duff — report
            // that, so Amount + Network fee equals Total exactly.
            return CoreToShieldedAmountPolicy.currentPoolFeeDuffs.map { $0 * 1000 }
        case .platformToShielded:
            // Shield (Type 15): base shielded fee. Real metered storage is
            // extra and only knowable on-chain, so this is a lower bound.
            return try? PlatformWalletManager.estimateShieldedFee(kind: .transfer, numActions: 2)
        case .shieldedToCore:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .withdrawal, numActions: 2)
        case .shieldedToPlatform:
            return try? PlatformWalletManager.estimateShieldedFee(kind: .unshield, numActions: 2)
        case .coreToPlatform:
            // Address-funding asset lock: the required processing balance (the
            // same 50k-duff base the Rust side reserves for address funding).
            // The funding ST's metered fee is extra and only knowable
            // on-chain, so this is a lower bound.
            return CoreToShieldedAmountPolicy.assetLockBaseCostCredits
        case .platformToCore:
            return withdrawalFeeCredits
        }
    }

    /// The fee as fiat (e.g. "~ $0.08"), or `nil` when it cannot be priced.
    static func networkFeeFiat(
        route: InternalTransferRoute,
        withdrawalFeeCredits: UInt64?
    ) -> String? {
        networkFeeCredits(
            route: route,
            withdrawalFeeCredits: withdrawalFeeCredits)
            .map(feeFiatString(credits:))
    }

    private static func feeFiatString(credits: UInt64) -> String {
        let dash = Decimal(credits) / creditsPerDash
        return "~ " + CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    // MARK: - Identity destination

    /// Fee estimate for an identity top-up funded from `source`, as fiat.
    /// The number is the top-up policy's own display estimate
    /// (`IdentityTopUpViewModel.estimatedFeeCredits`): the observed
    /// IdentityTopUp transition fee, plus the unshield minimum when the
    /// funding starts in the shielded pool. `nil` when that estimate is
    /// unavailable — the row renders an em dash.
    static func identityTopUpFeeFiat(source: ChainNetwork) -> String? {
        IdentityTopUpViewModel.estimatedFeeCredits(
            source: .init(spending: source))
            .map(feeFiatString(credits:))
    }

    /// The total row for an identity top-up: the amount itself, mirroring
    /// the sibling routes' totals — like Shielded → Platform (whose unshield
    /// this funding shares), the fee is reported in the fee row rather than
    /// inflating the total.
    static func identityTopUpTotal(dashDuffs: Int64) -> String {
        dashDuffs.formattedDashAmount
    }

    /// No fee number for an identity withdrawal. Neither transition it can
    /// run — IdentityCreditWithdrawal or the credit transfer — has an SDK fee
    /// estimator, the same gap `PlatformPaymentIdentityFundingPolicy`
    /// documents. `IdentityWithdrawViewModel.feeHeadroomCredits` is a reserve
    /// held back, deliberately several times the observed fee, so printing it
    /// here would overstate what the transfer costs. The row shows an em dash
    /// instead.
    ///
    /// TODO(SwiftDashSDK): price this once an identity-transition fee
    /// estimate is exposed.
    static let identityWithdrawalFeeFiat: String? = nil

    /// The summary label for the identity endpoint, on whichever side it
    /// sits — matches the payments landing's row title.
    static var identityEndpointName: String {
        InternalTransferViewModel.identityBalanceName
    }

    /// What actually leaves the source balance, formatted.
    ///
    /// Core → Shielded charges the pool fee ON TOP of the amount, so its total
    /// is the executed lock value; every other route's total is the amount
    /// itself. `nil` when the pool fee is unavailable — the row must never show
    /// the un-inflated number.
    static func totalLeavingSource(
        route: InternalTransferRoute,
        dashDuffs: Int64,
        amountDuffsUnsigned: UInt64
    ) -> String? {
        guard route == .coreToShielded else {
            return dashDuffs.formattedDashAmount
        }
        guard let poolFeeCredits = CoreToShieldedAmountPolicy.poolFeeCredits,
              let lockDuffs = CoreToShieldedAmountPolicy.lockValueDuffs(
                  forAmountDuffs: amountDuffsUnsigned,
                  poolFeeCredits: poolFeeCredits),
              let signedLockDuffs = Int64(exactly: lockDuffs)
        else { return nil }

        return signedLockDuffs.formattedDashAmount
    }

    // MARK: - Endpoints

    static func endpoints(
        of route: InternalTransferRoute
    ) -> (from: ChainNetwork, to: ChainNetwork) {
        switch route {
        case .coreToShielded: return (.core, .shielded)
        case .platformToShielded: return (.platform, .shielded)
        case .shieldedToCore: return (.shielded, .core)
        case .shieldedToPlatform: return (.shielded, .platform)
        case .coreToPlatform: return (.core, .platform)
        case .platformToCore: return (.platform, .core)
        }
    }

    /// Full balance names for the summary rows — longer than
    /// `ChainNetwork.balanceName`, which labels a card rather than a sentence.
    static func balanceName(_ network: ChainNetwork) -> String {
        switch network {
        case .core:
            return NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        case .platform:
            return NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")
        case .shielded:
            return NSLocalizedString("Shielded balance", comment: "")
        }
    }
}

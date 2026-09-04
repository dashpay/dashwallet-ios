//
//  InternalTransferSummaryFigures.swift
//  DashWallet
//

import Foundation
import SwiftDashSDK

/// The numbers and names the confirm sheet's summary card shows, derived from
/// the route.
///
/// Lifted out of the sheet because it is fee math: the identity routes ask the
/// SDK to price the transfer, and every figure has to be formatted the same way
/// wherever it came from. A SwiftUI `View` is the wrong place for that — it is
/// also the reason none of it could be exercised without rendering a sheet.
///
/// The balance routes' own fee and total are NOT resolved here: they are
/// `InternalTransferViewModel.confirmNetworkFeeCredits` / `confirmTotalDuffs`,
/// frozen into the submission at Continue so the Total the user confirms is
/// exactly what executes. This type only formats them.
///
/// Every value fails closed. An unavailable estimate is `nil`, which the sheet
/// renders as "—" rather than a number it cannot stand behind; `canContinue`
/// has already refused the transfer by then.
@MainActor
enum InternalTransferSummaryFigures {

    /// Platform credits per DASH (1e11).
    private static let creditsPerDash: Decimal = 100_000_000_000

    /// A frozen fee (credits) as fiat (e.g. "~ $0.08"), or `nil` when the
    /// ViewModel could not price the route.
    static func networkFeeFiat(credits: UInt64?) -> String? {
        credits.map(feeFiatString(credits:))
    }

    /// The fee row's label. Core → Platform pays a Platform-side funding fee
    /// out of its lock rather than an L1 network fee, and says so.
    static func feeRowLabel(route: InternalTransferRoute?) -> String {
        route == .coreToPlatform
            ? NSLocalizedString("Platform fee", comment: "")
            : NSLocalizedString("Network fee", comment: "")
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
    /// The number is `InternalTransferViewModel.confirmTotalDuffs`, frozen at
    /// Continue: both Core-funded asset-lock routes charge their fee on top of
    /// the amount, so their total is the executed lock value rather than the
    /// amount. `nil` when the ViewModel could not resolve it — the row must
    /// never show the un-inflated number.
    static func totalLeavingSource(totalDuffs: Int64?) -> String? {
        totalDuffs?.formattedDashAmount
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

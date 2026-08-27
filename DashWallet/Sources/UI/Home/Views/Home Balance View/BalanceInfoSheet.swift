//
//  BalanceInfoSheet.swift
//  DashWallet
//

import SwiftUI
import DashUIKit

/// Explains one of the three balances — Transparent, Platform, or
/// Shielded — with a short summary and its pros and cons. Presented as a
/// sheet when the user taps a balance row in the home header's breakdown
/// card (the row body; the in/out arrows keep their transfer actions).
struct BalanceInfoSheet: View {
    let network: ChainNetwork
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)

                    Text(info.summary)
                        .font(.subheadline)
                        .foregroundColor(.dash.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    pointsCard(
                        title: NSLocalizedString("Pros", comment: "Balance info sheet section"),
                        points: info.pros,
                        symbol: "checkmark.circle.fill",
                        tint: .green)

                    pointsCard(
                        title: NSLocalizedString("Cons", comment: "Balance info sheet section"),
                        points: info.cons,
                        symbol: "minus.circle.fill",
                        tint: .orange)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashButton(
                text: NSLocalizedString("Got it", comment: ""),
                style: .filled,
                stretch: true,
                action: onDone)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Color.dash.primaryBackground)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: info.iconSystemName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.dash.blue)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.dash.blue.opacity(0.08)))

            Text(info.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)
        }
    }

    private func pointsCard(title: String, points: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.dash.secondaryText)

            ForEach(points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .foregroundColor(tint)
                    Text(point)
                        .font(.subheadline)
                        .foregroundColor(.dash.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(12)
    }

    // MARK: - Content

    private struct BalanceInfo {
        let iconSystemName: String
        let title: String
        let summary: String
        let pros: [String]
        let cons: [String]
    }

    /// Copy stays grounded in what this wallet actually does — the timing
    /// caveats mirror the transfer confirm sheet's tips (10-minute spend
    /// delay, ~2-hour privacy window, withdrawal processing).
    private var info: BalanceInfo {
        switch network {
        case .core:
            return BalanceInfo(
                iconSystemName: "d.circle.fill",
                title: ChainNetwork.core.balanceName,
                summary: NSLocalizedString(
                    "Your main Dash balance on the Core blockchain — what you send and receive with other wallets, exchanges, and merchants.",
                    comment: "Balance info sheet"),
                pros: [
                    NSLocalizedString("Works with every Dash wallet, exchange, and merchant", comment: "Balance info sheet"),
                    NSLocalizedString("Payments confirm in seconds with InstantSend", comment: "Balance info sheet"),
                    NSLocalizedString("Low fees for everyday spending", comment: "Balance info sheet"),
                ],
                cons: [
                    NSLocalizedString("Amounts and addresses are public on the blockchain", comment: "Balance info sheet"),
                    NSLocalizedString("Anyone who knows an address can view its history", comment: "Balance info sheet"),
                ])
        case .platform:
            return BalanceInfo(
                iconSystemName: "creditcard.fill",
                title: NSLocalizedString("Platform", comment: "Dash Platform chain"),
                summary: NSLocalizedString(
                    "A credit balance on Dash Platform used for instant payments between Platform addresses and for features like usernames.",
                    comment: "Balance info sheet"),
                pros: [
                    NSLocalizedString("Transfers to other platform addresses and shielded addresses are instant and final", comment: "Balance info sheet"),
                    NSLocalizedString("Very efficient with low fees", comment: "Balance info sheet"),
                    NSLocalizedString("Almost instantaneous to sync balances", comment: "Balance info sheet"),
                ],
                cons: [
                    NSLocalizedString("Not widely accepted by merchants yet", comment: "Balance info sheet"),
                    NSLocalizedString("Activity is public but not easy to trace", comment: "Balance info sheet"),
                    NSLocalizedString("Transaction history isn't available", comment: "Balance info sheet"),
                ])
        case .shielded:
            return BalanceInfo(
                iconSystemName: "shield.fill",
                title: NSLocalizedString("Shielded", comment: ""),
                summary: NSLocalizedString(
                    "Your private balance. Amounts and addresses are encrypted on-chain, so your holdings and history stay confidential.",
                    comment: "Balance info sheet"),
                pros: [
                    NSLocalizedString("Balances and transfers are not publicly visible", comment: "Balance info sheet"),
                    NSLocalizedString("The most private place to hold your Dash", comment: "Balance info sheet"),
                    NSLocalizedString("Uses one of the most audited and tested zero-knowledge libraries (Orchard)", comment: "Balance info sheet"),
                ],
                cons: [
                    NSLocalizedString("Transfers take longer — privacy proofs take time to build", comment: "Balance info sheet"),
                    NSLocalizedString("Not widely accepted by merchants", comment: "Balance info sheet"),
                    NSLocalizedString("Higher fees around 7 cents (still lower than other blockchains offering similar privacy)", comment: "Balance info sheet"),
                ])
        }
    }
}

#if DEBUG
#Preview("Shielded") {
    BalanceInfoSheet(network: .shielded)
}
#endif

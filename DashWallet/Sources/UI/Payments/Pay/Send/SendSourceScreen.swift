//
//  SendSourceScreen.swift
//  DashWallet
//
//  Step two: which balance the send is funded from.
//

import SwiftUI
import DashUIKit
import SwiftDashSDK
import UIKit

// MARK: - Step 2: amount

/// The source step: which balance funds the send. The address is settled by
/// now and shown read-only above the cards; this screen adds the sync gate.
/// Continue always advances to the amount step — no route skips it.
struct SendSourceScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the address step.
    var onBack: () -> Void
    /// A valid source is chosen → advance to the amount step.
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            })

            // Content

            VStack(alignment: .leading, spacing: 20) {
                SendAddressSummary(viewModel: viewModel)

                sourceCards

                if viewModel.isBlockedBySync {
                    SyncGateNote()
                        .padding(.horizontal, 20)
                }

                Spacer()

                DashButton(
                    text: NSLocalizedString("Continue", comment: ""),
                    style: .filled,
                    stretch: true,
                    isEnabled: viewModel.route != nil && !viewModel.isBlockedBySync,
                    action: onContinue
                )
                .padding(.horizontal, 40)
            }
            .padding(.top, 10)
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - From picker

    @ViewBuilder
    private var sourceCards: some View {
        if let pinned = viewModel.pinnedSource {
            sourceRow(pinned, showsRadio: false)
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.validSources, id: \.self) { network in
                    sourceRow(network)
                }
            }
        }
    }

    private func sourceRow(_ network: ChainNetwork, showsRadio: Bool = true) -> some View {
        let balance: String
        switch network {
        case .core: balance = viewModel.coreBalanceFormatted
        case .platform: balance = viewModel.platformCreditsFormatted
        case .shielded: balance = viewModel.shieldedBalanceFormatted
        }

        return TransferSourceRow(
            iconSystemName: sourceIconName(network),
            caption: NSLocalizedString("From", comment: ""),
            title: sourceTitle(network),
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(balance),
            selected: viewModel.source == network,
            showsRadio: showsRadio,
            action: {
                viewModel.source = network
            }
        )
    }
}

#if DEBUG

#Preview("Pick a source") {
    SendSourceScreen(
        viewModel: .preview(address: "yV1D1ivvSUyKPJnbFmzSTVh1MyZ3JbeVkY", destination: .core),
        onBack: {}, onContinue: {})
        .background(Color.dash.primaryBackground)
}

/// Pinned by the caller (the balance row's own send button) — the picker
/// shows the choice already made rather than re-offering it.
#Preview("Pinned to Shielded") {
    SendSourceScreen(
        viewModel: .preview(
            address: "yV1D1ivvSUyKPJnbFmzSTVh1MyZ3JbeVkY",
            destination: .core,
            source: .shielded,
            pinnedSource: .shielded),
        onBack: {}, onContinue: {})
        .background(Color.dash.primaryBackground)
}

#endif

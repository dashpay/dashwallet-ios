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

/// The amount step for the split external-send flow. The address is already
/// chosen (locked, read-only) — this screen carries the From picker, the
/// sync gate, and the amount keypad, plus the balance/affordability
/// validations. Continue routes exactly as the old single-screen form did:
/// Core → Core into the L1 payment processor, everything else into
/// `SendConfirmSheet`.
struct SendSourceScreen: View {
    @ObservedObject var viewModel: SendViewModel
    /// Pop back to the address step.
    var onBack: () -> Void
    /// A valid source is chosen → advance to the amount step.
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // DashUIKit's bar carries its own height and horizontal
            // insets, so the manual padding the hand-rolled header needed
            // goes with it.
            DashUIKit.NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            }, central: {
                Text(NSLocalizedString("Send", comment: ""))
                    .dashFont(.subheadMedium)
                    .foregroundColor(.dash.primaryText)
            })

            ScrollView {
                VStack(spacing: 14) {
                    SendAddressSummary(viewModel: viewModel)
                        .padding(.top, 12)

                    sourceCards

                    if viewModel.isBlockedBySync {
                        SyncGateNote()
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                style: .filled,
                stretch: true,
                isEnabled: viewModel.route != nil && !viewModel.isBlockedBySync,
                action: onContinue)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - From picker

    @ViewBuilder
    private var sourceCards: some View {
        if let pinned = viewModel.pinnedSource {
            // Balance-row send sheet: the source is the tapped balance,
            // rendered as a fixed card (no radio, not tappable).
            sourceRow(pinned, showsRadio: false)
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.validSources, id: \.self) { network in
                    sourceRow(network)
                }
            }
            .padding(.horizontal, 20)
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
            action: { viewModel.source = network })
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

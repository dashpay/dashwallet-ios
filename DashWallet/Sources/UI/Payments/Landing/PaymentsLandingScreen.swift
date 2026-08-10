//
//  PaymentsLandingScreen.swift
//  DashWallet
//

import DashUIKit
import SwiftUI
import UIKit

struct PaymentsLandingScreen: View {
    @ObservedObject var viewModel: PaymentsLandingViewModel

    var onClose: () -> Void
    var onCopyAddress: () -> Void
    var onShareAddress: () -> Void
    var onSpecifyAmount: () -> Void
    var onScanQR: () -> Void
    var onShieldedBalance: () -> Void
    /// When set, the Internal tab embeds the transfer form directly (the
    /// same screen the balance-row arrows used to present standalone)
    /// instead of the action-row list. Set by the receive and send sheets.
    var embeddedTransferViewModel: InternalTransferViewModel? = nil
    var onTransferCompleted: () -> Void = {}
    /// Set by the balance-row send sheet: the embedded transfer form pins
    /// this balance as its From card (destination picked on the To rows),
    /// instead of the receive sheet's pinned-destination layout.
    var transferSendFrom: ChainNetwork? = nil
    /// The Send tab IS the external-send form — pinned to the tapped
    /// balance as source on the balance-row send sheet, un-pinned (full
    /// From picker) on the full landing.
    var embeddedSendViewModel: SendViewModel
    /// The Send tab's address is valid → advance to the amount step. The host
    /// pushes `ExternalSendAmountScreen` onto the landing's navigation stack.
    var onSendContinue: () -> Void = {}
    /// False for the balance-row receive/send sheets: their grabber + hero
    /// selector are the top chrome — no X close button or title row.
    var showsHeader: Bool = true

    var body: some View {
        // Tighter chrome when a tab embeds a full form (transfer or send) —
        // its amount + cards + keypad need most of the sheet. It shortens the
        // gap BELOW the selector only: sizing the whole stack by it moved the
        // header and the pills too, so switching tabs jumped them 8pt.
        let isEmbeddedForm = (viewModel.activeTab == .internalTransfer && embeddedTransferViewModel != nil)
            || viewModel.activeTab == .send
        VStack(alignment: .center, spacing: 0) {
            if showsHeader {
                header
            }

            PaymentsLandingTabSelector(
                tabs: viewModel.visibleTabs,
                selection: $viewModel.activeTab)
                .padding(.horizontal, 20)
                // The pills carry no container of their own, so they need the
                // gap the boxed control used to get from its own padding and
                // edge — under the header most of all, where the close button
                // sits right above them. Fixed, so it reads the same on every
                // tab.
                .padding(.top, showsHeader ? 20 : 12)
                .padding(.bottom, isEmbeddedForm ? 12 : 20)

            switch viewModel.activeTab {
            case .receive:
                receiveContent
                Spacer()
            case .internalTransfer:
                if let transferViewModel = embeddedTransferViewModel {
                    if let sendFrom = transferSendFrom {
                        // Send sheet: the From card is pinned by the tapped
                        // balance; the To rows pick the destination.
                        InternalTransferScreen(
                            viewModel: transferViewModel,
                            onCompleted: onTransferCompleted,
                            showsHeader: false,
                            sendFrom: sendFrom)
                    } else {
                        InternalTransferScreen(
                            viewModel: transferViewModel,
                            onCompleted: onTransferCompleted,
                            showsHeader: false,
                            receiveInto: viewModel.network)
                            // Keep the pinned route in lockstep with the receive
                            // toggle, so the fixed To card and the executed
                            // transfer can never disagree.
                            .onAppear { transferViewModel.applyReceiveRoute(into: viewModel.network) }
                            .onChange(of: viewModel.network) { network in
                                transferViewModel.applyReceiveRoute(into: network)
                            }
                    }
                } else {
                    internalContent
                    Spacer()
                }
            case .send:
                SendScreen(
                    viewModel: embeddedSendViewModel,
                    onClose: onClose,
                    onScanQR: onScanQR,
                    onContinue: onSendContinue,
                    showsHeader: false)
            }
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.dash.primaryText)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.dash.gray300.opacity(0.3), lineWidth: 1))
            }
            Spacer()
            Text(headerTitle)
                .font(.headline)
                .foregroundColor(.dash.primaryText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    /// The tab's own label — the selector shows the same words on the active
    /// pill, and two copies would be free to drift.
    private var headerTitle: String { viewModel.activeTab.title }

    // MARK: - Tab selector

    // MARK: - Receive

    private var receiveContent: some View {
        VStack(alignment: .center, spacing: 20) {
            ChainNetworkToggle(selection: $viewModel.network, options: ChainNetwork.allCases)
                .padding(.horizontal, 20)

            qrCard

            HStack(spacing: 12) {
                Button(action: onShareAddress) {
                    actionPill(title: NSLocalizedString("Share address", comment: ""))
                }
                .disabled(viewModel.currentAddress == nil)

                Button(action: onSpecifyAmount) {
                    actionPill(title: NSLocalizedString("Specify amount", comment: ""))
                }
                .disabled(viewModel.currentAddress == nil || viewModel.network != .core)
            }
            .padding(.horizontal, 20)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 14) {
            if let address = viewModel.currentAddress,
               let qr = QRCodeGenerator.image(for: address) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(12)
                    .background(Color.dash.white)
                    .cornerRadius(16)

                VStack(spacing: 4) {
                    Text(NSLocalizedString("Your DASH address", comment: ""))
                        .font(.caption)
                        .foregroundColor(Color.dash.secondaryText)
                    Text(address)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.dash.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .onTapGesture { onCopyAddress() }
            } else if viewModel.network == .platform && !viewModel.platformIsReady {
                placeholder(NSLocalizedString("Platform sync starting…", comment: ""))
            } else if viewModel.network == .shielded {
                // Nil only until the shielded sub-wallet binds at startup
                // (the view model retries as the platform stack comes up).
                placeholder(NSLocalizedString("Shielded wallet starting…", comment: ""))
            } else {
                placeholder(NSLocalizedString("No address available", comment: ""))
            }
        }
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            SwiftUI.ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundColor(Color.dash.secondaryText)
        }
        .frame(width: 220, height: 220)
    }

    private func actionPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.dash.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(12)
    }

    // MARK: - Internal

    private var internalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Internal transfer to/from", comment: ""))
                .font(.caption)
                .foregroundColor(Color.dash.secondaryText)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionRow(
                iconSystemName: "shield.fill",
                title: NSLocalizedString("Shielded balance", comment: ""),
                action: onShieldedBalance)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Shared action row

    private func actionRow(
        iconSystemName: String,
        title: String,
        action: (() -> Void)?
    ) -> some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.dash.primaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(12)
        }
        .disabled(action == nil)
    }
}

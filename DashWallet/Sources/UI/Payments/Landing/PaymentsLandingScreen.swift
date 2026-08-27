//
//  PaymentsLandingScreen.swift
//  DashWallet
//

import DashUIKit
import SwiftUI
import UIKit

struct PaymentsLandingScreen: View {
    @ObservedObject var viewModel: PaymentsLandingViewModel
    @Environment(\.colorScheme) private var colorScheme

    var onClose: () -> Void
    var onCopyAddress: () -> Void
    var onShareAddress: () -> Void
    var onSpecifyAmount: () -> Void
    var onViewTransaction: (Data) -> Void
    var onScanQR: () -> Void
    /// The Internal tab's embedded transfer form. The full landing shows it
    /// un-pinned (free From + To pickers); the balance-row receive/send
    /// sheets pin one endpoint via `transferReceivePinned`/`transferSendFrom`.
    var embeddedTransferViewModel: InternalTransferViewModel
    var onTransferCompleted: () -> Void = {}
    /// Set by the balance-row send sheet: the embedded transfer form pins
    /// this balance as its From card (destination picked on the To rows),
    /// instead of the receive sheet's pinned-destination layout.
    var transferSendFrom: ChainNetwork?
    /// True for the balance-row receive sheet: the transfer form pins the
    /// receive toggle's balance as its To card (source picked on the From
    /// rows). False (with `transferSendFrom` nil) = the free-form landing.
    var transferReceivePinned: Bool = false
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
        // its amount + cards + keypad need most of the sheet.
        let isEmbeddedForm = viewModel.activeTab != .receive
        VStack(alignment: .center, spacing: isEmbeddedForm ? 12 : 20) {
            if showsHeader {
                header
            }

            tabSelector
                .padding(.horizontal, 20)
                .padding(.top, showsHeader ? 0 : 12)

            switch viewModel.activeTab {
            case .receive:
                receiveContent
                if viewModel.receipt == nil {
                    Spacer()
                }
            case .internalTransfer:
                if let sendFrom = transferSendFrom {
                    // Send sheet: the From card is pinned by the tapped
                    // balance; the To rows pick the destination.
                    InternalTransferScreen(
                        viewModel: embeddedTransferViewModel,
                        onCompleted: onTransferCompleted,
                        showsHeader: false,
                        sendFrom: sendFrom)
                } else if transferReceivePinned {
                    // The hosting controller keeps the pinned route in
                    // lockstep with the receive toggle (its `$network`
                    // subscription), so the fixed To card and the executed
                    // transfer can never disagree.
                    InternalTransferScreen(
                        viewModel: embeddedTransferViewModel,
                        onCompleted: onTransferCompleted,
                        showsHeader: false,
                        receiveInto: viewModel.network)
                } else {
                    // Full landing: the transfer form itself, free From and
                    // To pickers — no intermediate action-row step.
                    InternalTransferScreen(
                        viewModel: embeddedTransferViewModel,
                        onCompleted: onTransferCompleted,
                        showsHeader: false)
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
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.receipt?.id)
        .sensoryFeedback(.success, trigger: viewModel.receipt?.id)
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

    private var headerTitle: String {
        switch viewModel.activeTab {
        case .receive: return NSLocalizedString("Receive", comment: "")
        case .internalTransfer: return NSLocalizedString("Internal transfer", comment: "")
        case .send: return NSLocalizedString("Send", comment: "")
        }
    }

    // MARK: - Tab selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.visibleTabs) { tab in
                Button(action: { viewModel.activeTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconSystemName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(viewModel.activeTab == tab ? Color.dash.primaryText : Color.dash.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            // Selected pill: a solid white raised card in light mode; a
                            // translucent light fill in dark so the primaryText label stays
                            // legible (pure white would be invisible on the dark selector).
                            // Mirrors the app's SegmentedControl selected-fill treatment.
                            .fill(viewModel.activeTab == tab
                                ? (colorScheme == .dark ? Color.dash.whiteAlpha20 : Color.dash.white)
                                : Color.clear)
                            .shadow(
                                color: viewModel.activeTab == tab
                                    ? Color.dash.shadow : .clear,
                                radius: 2, x: 0, y: 1))
                }
            }
        }
        .padding(4)
        .background(Color.dash.secondaryBackground)
        .cornerRadius(10)
    }

    // MARK: - Receive

    private var receiveContent: some View {
        VStack(alignment: .center, spacing: 20) {
            ChainNetworkToggle(selection: $viewModel.network, options: ChainNetwork.allCases)
                .padding(.horizontal, 20)

            if let receipt = viewModel.receipt {
                receiptCard(receipt)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
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

                if viewModel.isWatchingForReceipt {
                    HStack(spacing: 8) {
                        SwiftUI.ProgressView()
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("Watching for a payment…", comment: "Receive screen activity"))
                            .font(.caption)
                            .foregroundColor(.dash.secondaryText)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func receiptCard(_ receipt: ReceiveReceipt) -> some View {
        VStack(spacing: 16) {
            PaymentSuccessHeader(
                title: NSLocalizedString("Received", comment: "Receive success title"),
                amountDuffs: Int64(clamping: receipt.amountDuffs),
                fiatText: CurrencyExchanger.shared.fiatAmountString(
                    for: receipt.amountDuffs.dashAmount))

            VStack(spacing: 8) {
                receiptInfoRow(
                    title: NSLocalizedString("Balance", comment: "Receive receipt rail"),
                    value: receipt.rail.balanceName)
                receiptInfoRow(
                    title: NSLocalizedString("Status", comment: "Receive receipt status"),
                    value: receipt.statusTitle)
                receiptInfoRow(
                    title: NSLocalizedString("Time", comment: "Receive receipt time"),
                    value: receipt.receivedAt.formatted(date: .omitted, time: .shortened))
                if let memo = receipt.memo, !memo.isEmpty {
                    receiptInfoRow(
                        title: NSLocalizedString("Memo", comment: "Receive receipt memo"),
                        value: memo)
                }
            }
            .padding(14)
            .background(Color.dash.secondaryBackground)
            .cornerRadius(14)
            .padding(.horizontal, 20)

            if viewModel.canViewTransaction, let transactionId = receipt.transactionId {
                Button {
                    onViewTransaction(transactionId)
                } label: {
                    Text(NSLocalizedString("View transaction", comment: "Receive receipt action"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.dash.blue)
                }
            }

            Spacer(minLength: 12)

            ButtonsGroup(
                orientation: .horizontal,
                size: .large,
                positiveButtonText: NSLocalizedString("Done", comment: "Receive receipt action"),
                positiveButtonAction: onClose,
                negativeButtonText: NSLocalizedString("Receive another", comment: "Receive receipt action"),
                negativeButtonAction: viewModel.receiveAnother)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func receiptInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundColor(.dash.secondaryText)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
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

}

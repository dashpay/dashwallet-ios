//
//  PaymentsLandingScreen.swift
//  DashWallet
//

import SwiftUI
import UIKit

struct PaymentsLandingScreen: View {
    @ObservedObject var viewModel: PaymentsLandingViewModel

    var onClose: () -> Void
    var onCopyAddress: () -> Void
    var onShareAddress: () -> Void
    var onSpecifyAmount: () -> Void
    var onImportPrivateKey: () -> Void
    var onScanQR: () -> Void
    var onSendToAddress: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            header

            tabSelector
                .padding(.horizontal, 20)

            Group {
                switch viewModel.activeTab {
                case .receive:
                    receiveContent
                case .internalTransfer:
                    internalContent
                case .send:
                    sendContent
                }
            }

            Spacer()
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
            }
            Spacer()
            Text(headerTitle)
                .font(.headline)
                .foregroundColor(.primaryText)
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
            ForEach(PaymentsLandingTab.allCases) { tab in
                Button(action: { viewModel.activeTab = tab }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconSystemName)
                            .font(.system(size: 16, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(viewModel.activeTab == tab ? .primaryText : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.activeTab == tab ? Color.white : Color.clear)
                            .shadow(
                                color: viewModel.activeTab == tab
                                    ? Color.black.opacity(0.08) : .clear,
                                radius: 2, x: 0, y: 1))
                }
            }
        }
        .padding(4)
        .background(Color.secondaryBackground)
        .cornerRadius(10)
    }

    // MARK: - Receive

    private var receiveContent: some View {
        VStack(alignment: .center, spacing: 20) {
            ChainNetworkToggle(selection: $viewModel.network)
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

            actionRow(
                iconSystemName: "key.fill",
                title: NSLocalizedString("Import private key", comment: ""),
                action: onImportPrivateKey)
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
                    .background(Color.white)
                    .cornerRadius(16)

                VStack(spacing: 4) {
                    Text(NSLocalizedString("Your DASH address", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(address)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .onTapGesture { onCopyAddress() }
            } else if viewModel.network == .platform && !viewModel.platformIsReady {
                placeholder(NSLocalizedString("Platform sync starting…", comment: ""))
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
                .foregroundColor(.secondary)
        }
        .frame(width: 220, height: 220)
    }

    private func actionPill(title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
    }

    // MARK: - Internal

    private var internalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Internal transfer to/from", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionRow(
                iconSystemName: "shield.fill",
                title: NSLocalizedString("Shielded balance", comment: ""),
                action: nil)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Send

    private var sendContent: some View {
        VStack(alignment: .center, spacing: 12) {
            ChainNetworkToggle(selection: $viewModel.network)
                .padding(.horizontal, 20)

            actionRow(
                iconSystemName: "qrcode.viewfinder",
                title: NSLocalizedString("Scan QR", comment: ""),
                action: onScanQR)
                .padding(.horizontal, 20)

            actionRow(
                iconSystemName: "paperplane.fill",
                title: NSLocalizedString("Send to address", comment: ""),
                action: onSendToAddress)
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
                    .foregroundColor(.primaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.secondaryBackground)
            .cornerRadius(12)
        }
        .disabled(action == nil)
    }
}

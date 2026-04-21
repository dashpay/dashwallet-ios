//
//  ReceiveScreen.swift
//  DashWallet
//

import SwiftUI
import UIKit

struct ReceiveScreen: View {
    private let vc: UIViewController

    @StateObject private var viewModel = ReceiveViewModel()
    @State private var showShareSheet = false

    init(vc: UIViewController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            header

            ChainNetworkToggle(selection: $viewModel.network)
                .padding(.horizontal, 20)

            qrCard

            actionRow

            Spacer()
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            if let text = viewModel.currentAddress {
                ShareActivityView(items: [text])
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { vc.dismiss(animated: true) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.gray300.opacity(0.3), lineWidth: 1))
            }
            Spacer()
            Text(NSLocalizedString("Receive", comment: ""))
                .font(.headline)
                .foregroundColor(.primaryText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
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

                Text(address)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .onTapGesture {
                        viewModel.copyCurrentAddressToPasteboard()
                        vc.view.dw_showInfoHUD(
                            withText: NSLocalizedString("Copied", comment: ""),
                            offsetForNavBar: false)
                    }
            } else if viewModel.network == .platform && !viewModel.platformIsReady {
                placeholder(NSLocalizedString("Platform sync starting…", comment: ""))
            } else {
                placeholder(NSLocalizedString("No address available", comment: ""))
            }
        }
        .padding(.horizontal, 20)
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

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.copyCurrentAddressToPasteboard()
                vc.view.dw_showInfoHUD(
                    withText: NSLocalizedString("Copied", comment: ""),
                    offsetForNavBar: false)
            }) {
                actionLabel(
                    iconSystemName: "doc.on.doc",
                    title: NSLocalizedString("Copy", comment: ""))
            }
            .disabled(viewModel.currentAddress == nil)

            Button(action: { showShareSheet = true }) {
                actionLabel(
                    iconSystemName: "square.and.arrow.up",
                    title: NSLocalizedString("Share", comment: ""))
            }
            .disabled(viewModel.currentAddress == nil)

            if viewModel.network == .core {
                Button(action: { pushSpecifyAmount() }) {
                    actionLabel(
                        iconSystemName: "dollarsign.circle",
                        title: NSLocalizedString("Request", comment: ""))
                }
                .disabled(viewModel.currentAddress == nil)
            }
        }
        .padding(.horizontal, 20)
    }

    private func actionLabel(iconSystemName: String, title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
            Text(title)
                .font(.caption)
                .foregroundColor(.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.secondaryBackground)
        .cornerRadius(12)
    }

    private func pushSpecifyAmount() {
        let specify = SpecifyAmountViewController.controller()
        specify.delegate = ReceiveSpecifyAmountRouter.shared
        vc.navigationController?.pushViewController(specify, animated: true)
    }
}

private struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Minimal router so the legacy `SpecifyAmountViewController` can be pushed
/// from SwiftUI without needing a ViewController conforming to its delegate.
final class ReceiveSpecifyAmountRouter: NSObject, SpecifyAmountViewControllerDelegate {
    static let shared = ReceiveSpecifyAmountRouter()

    func specifyAmountViewController(
        _ controller: SpecifyAmountViewController,
        didInput amount: UInt64
    ) {
        controller.navigationController?.popViewController(animated: true)
    }
}

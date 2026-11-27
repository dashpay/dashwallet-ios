//
//  QRScannerView.swift
//  DashWallet
//
//  Full-screen QR scanner: camera preview, scan frame, torch toggle, and
//  a status card driven by QRScannerViewModel (validation states, BIP70
//  progress, and cross-context redirect offers).
//

import AVFoundation
import DashUIKit
import SwiftUI

struct QRScannerView: View {
    @StateObject private var viewModel: QRScannerViewModel
    private let onResult: (QRScanResult) -> Void
    private let onCancel: () -> Void

    @State private var showCameraAlert = false

    private let torchAvailable = AVCaptureDevice.default(for: .video)?.hasTorch ?? false

    init(mode: QRScannerMode,
         readsDashConnect: Bool = false,
         onResult: @escaping (QRScanResult) -> Void,
         onCancel: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: QRScannerViewModel(mode: mode, readsDashConnect: readsDashConnect))
        self.onResult = onResult
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            QRCaptureView(
                onQRCodesDetected: { viewModel.didDetectCodes($0) },
                onCameraUnavailable: { showCameraAlert = true },
                torchOn: $viewModel.torchOn
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { viewModel.cancel() }) {
                        Text(String(localized: "Cancel", comment: ""))
                            .font(.body)
                            .foregroundColor(.dash.whiteText)
                    }

                    Spacer()

                    if torchAvailable {
                        Button(action: { viewModel.torchOn.toggle() }) {
                            Image(systemName: viewModel.torchOn ? "bolt.slash.fill" : "bolt.fill")
                                .foregroundColor(.dash.whiteText)
                                .font(.title3)
                        }
                        .accessibilityLabel(Text(viewModel.torchOn
                            ? String(localized: "Turn off flashlight", comment: "QR scanner")
                            : String(localized: "Turn on flashlight", comment: "QR scanner")))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                RoundedRectangle(cornerRadius: 12)
                    .stroke(frameColor, lineWidth: 2)
                    .frame(width: 250, height: 250)

                Text(String(localized: "Scan QR Code", comment: ""))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.dash.whiteText)
                    .padding(.top, 24)

                statusCard
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer()
                Spacer()
            }
        }
        .background(Color.dash.black.ignoresSafeArea())
        .onAppear {
            viewModel.onResult = onResult
            viewModel.onCancel = onCancel
        }
        .alert(isPresented: $showCameraAlert) {
            Alert(
                title: Text(String(localized: "Camera Unavailable", comment: "")),
                message: Text(String(localized: "Allow camera access in Settings", comment: "")),
                primaryButton: .default(Text(String(localized: "Settings", comment: ""))) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    onCancel()
                },
                secondaryButton: .cancel(Text(String(localized: "Cancel", comment: ""))) {
                    onCancel()
                }
            )
        }
    }

    private var frameColor: Color {
        switch viewModel.status {
        case .searching:
            return Color.dash.white.opacity(0.6)
        case .connecting, .valid, .offer:
            return Color.dash.green
        case .invalid:
            return Color.dash.red
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch viewModel.status {
        case .searching, .valid:
            EmptyView()

        case .connecting:
            card {
                SwiftUI.ProgressView()
                    .padding(.bottom, 8)
                Text(String(localized: "Please Wait", comment: ""))
                    .font(.title3)
                    .foregroundColor(.dash.primaryText)
                Text(String(localized: "Connecting to payment server", comment: ""))
                    .font(.body)
                    .foregroundColor(.dash.secondaryText)
            }

        case .invalid(let title, let message):
            card {
                Text(title)
                    .font(.title3)
                    .foregroundColor(.dash.primaryText)
                Text(message ?? String(localized: "Please try scanning again", comment: ""))
                    .font(.body)
                    .foregroundColor(.dash.secondaryText)
            }

        case .offer(_, let message, let actionTitle):
            card {
                Text(message)
                    .font(.body)
                    .foregroundColor(.dash.primaryText)
                HStack(spacing: 12) {
                    offerButton(String(localized: "Keep Scanning", comment: "QR scanner"),
                                background: .dash.secondaryBackground,
                                foreground: .dash.primaryText) {
                        viewModel.declineOffer()
                    }
                    offerButton(actionTitle,
                                background: .dash.blue,
                                foreground: .dash.whiteText) {
                        viewModel.acceptOffer()
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func offerButton(_ title: String,
                             background: Color,
                             foreground: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(background)
                .foregroundColor(foreground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 4) {
            content()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.dash.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

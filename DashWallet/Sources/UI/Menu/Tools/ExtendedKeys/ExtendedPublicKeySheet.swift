//
//  ExtendedPublicKeySheet.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import UIKit

// MARK: - ExtendedPublicKeySheetViewModel

class ExtendedPublicKeySheetViewModel: ObservableObject {
    @Published var keyValue: String = ""
    @Published var qrImage: UIImage? = nil

    init() {
        loadKey()
    }

    private func loadKey() {
        let model = ExtendedPublicKeysModel()
        guard let firstPath = model.derivationPaths.first else { return }
        keyValue = firstPath.item.value
        qrImage = generateQRCode(from: keyValue)
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard !string.isEmpty,
              let filter = CIFilter(name: "CIQRCodeGenerator"),
              let data = string.data(using: .utf8) else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        let scale = 180.0 / outputImage.extent.width
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ExtendedPublicKeySheet

struct ExtendedPublicKeySheet: View {
    @StateObject private var viewModel = ExtendedPublicKeySheetViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isCopied = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Grabber
            VStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.gray300.opacity(0.5))
                    .frame(width: 36, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 18)

            // Close button
            NavBarClose {
                dismiss()
            }

            // QR code
            Group {
                if let qrImage = viewModel.qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray300.opacity(0.2))
                        .frame(width: 180, height: 180)
                }
            }
            .padding(.vertical, 30)

            // Title + tappable key text
            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("Extended public key (BIP44)", comment: ""))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: {
                    guard !viewModel.keyValue.isEmpty else { return }
                    UIPasteboard.general.string = viewModel.keyValue
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isCopied = false
                    }
                }) {
                    Text(viewModel.keyValue.isEmpty
                         ? NSLocalizedString("Not available", comment: "")
                         : viewModel.keyValue)
                        .font(.system(size: 15))
                        .foregroundColor(.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
                .overlay(
                    Group {
                        if isCopied {
                            Text(NSLocalizedString("Copied", comment: ""))
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(copiedBackground)
                                .foregroundColor(.whiteText)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                )
            }
            .padding(.horizontal, 60)
            .padding(.top, 20)
            .padding(.bottom, 32)

            Spacer()

            // Share key button
            DashButton(
                text: NSLocalizedString("Share key", comment: ""),
                style: .tintedBlue,
                action: { showShareSheet = true }
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 20)
        }
        .background(Color.secondaryBackground)
        .sheet(isPresented: $showShareSheet) {
            if !viewModel.keyValue.isEmpty {
                ShareSheet(items: [viewModel.keyValue])
            }
        }
    }

    @ViewBuilder
    private var copiedBackground: some View {
        if colorScheme == .dark {
            ZStack {
                BackgroundBlurView()
                Color.whiteAlpha15
            }
        } else {
            Color.black.opacity(0.8)
        }
    }
}

// MARK: - Preview

#Preview {
    ExtendedPublicKeySheet()
}

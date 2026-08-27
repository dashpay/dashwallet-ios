//
//  GenericQRScannerView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import DashUIKit

/// Full-screen SwiftUI QR scanner with camera preview, scan frame, and torch toggle.
struct GenericQRScannerView: View {
    var onQRCodeScanned: ((String) -> Void)?
    var onCancel: (() -> Void)?

    @State private var torchOn = false
    @State private var showCameraAlert = false

    var body: some View {
        ZStack {
            QRCaptureView(
                onQRCodeScanned: { value in
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #if DEBUG
                    DWLogger.log("Maya QR Scanner: Scanned value: \(value)")
                    #endif
                    onQRCodeScanned?(value)
                },
                onCameraUnavailable: {
                    showCameraAlert = true
                },
                torchOn: $torchOn
            )
            .ignoresSafeArea()

            // Overlay controls
            VStack {
                // Top bar: Cancel + Torch
                HStack {
                    Button(action: { onCancel?() }) {
                        Text(NSLocalizedString("Cancel", comment: ""))
                            .font(.system(size: 17))
                            .foregroundColor(Color.dash.whiteText)
                    }

                    Spacer()

                    Button(action: { torchOn.toggle() }) {
                        Image(systemName: torchOn ? "bolt.slash.fill" : "bolt.fill")
                            .foregroundColor(Color.dash.whiteText)
                            .font(.system(size: 20))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Scan frame
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.dash.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 250, height: 250)

                // Instruction label
                Text(NSLocalizedString("Scan QR Code", comment: "Dash DEX"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.dash.whiteText)
                    .padding(.top, 24)

                Spacer()
                Spacer()
            }
        }
        .background(Color.dash.black.ignoresSafeArea())
        .alert(isPresented: $showCameraAlert) {
            Alert(
                title: Text(NSLocalizedString("Camera Unavailable", comment: "")),
                message: Text(NSLocalizedString("Camera is required to scan QR codes.", comment: "")),
                dismissButton: .default(Text(NSLocalizedString("OK", comment: ""))) {
                    onCancel?()
                }
            )
        }
    }
}

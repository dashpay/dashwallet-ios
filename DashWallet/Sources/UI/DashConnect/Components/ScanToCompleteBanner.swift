//
//  ScanToCompleteBanner.swift
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

import DashUIKit
import SwiftUI

/// Prompt attached to an approved connection: approval alone does not log the
/// user in, and the same button accepts either the follow-up `dash-st:` QR or
/// a fresh `dash-key:` QR for the same app.
struct ScanToCompleteBanner: View {
    let onScanQR: () -> Void
    let onMockScan: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                DashIcon.SystemMessage.infoRectSmall.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .frame(width: 30, height: 30, alignment: .center)

            HStack(alignment: .top, spacing: 20) {
                Text(
                    NSLocalizedString("Scan the QR code to complete the login process", comment: "DashConnect")
                )
                .dashFont(.subhead)
                .foregroundColor(Color.dash.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

                ScanQRButton(size: .small, onScanQR: onScanQR, onMockScan: onMockScan)
            }
            .padding(.vertical, 5)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.dash.blueAlpha5)
        .cornerRadius(20)
    }
}

#Preview {
    ScanToCompleteBanner(onScanQR: {}, onMockScan: {})
        .padding()
        .background(Color.primaryBackground)
}

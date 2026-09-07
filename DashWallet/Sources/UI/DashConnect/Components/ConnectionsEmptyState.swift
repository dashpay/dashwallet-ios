//
//  ConnectionsEmptyState.swift
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

/// Shown when the feature is available but nothing is connected yet. Explains
/// what a connection is for, then offers the only way to make one.
struct ConnectionsEmptyState: View {
    let onScanQR: () -> Void
    let onMockScan: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 40) {
                VStack(spacing: 20) {
                    HStack(spacing: 0) {
                        Image("dashconnect-empty")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                    }
                    .frame(width: 80, height: 80)

                    VStack(spacing: 4) {
                        Text(NSLocalizedString("No apps connected yet", comment: "DashConnect"))
                            .dashFont(.title3Medium)
                            .foregroundColor(Color.dash.primaryText)

                        Text(
                            NSLocalizedString(
                                "Connect your DashPay username to apps on the Dash network to sign in without passwords or accounts",
                                comment: "DashConnect"
                            )
                        )
                        .dashFont(.subhead)
                        .foregroundColor(Color.dash.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                }

                ScanQRButton(onScanQR: onScanQR, onMockScan: onMockScan)
                    .padding(.horizontal, 60)
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConnectionsEmptyState(onScanQR: {}, onMockScan: {})
        .background(Color.primaryBackground)
}

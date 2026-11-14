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

/// The page with nothing to list: either nothing is connected yet, and it
/// offers the only way to make a connection, or the wallet has no username,
/// and it offers to create one first.
struct ConnectionsEmptyState: View {
    enum Kind {
        case noApps(onScanQR: () -> Void, onMockScan: () -> Void)
        /// `onCreateUsername` is `nil` where username creation cannot be
        /// reached from here: the button is left out.
        case noUsername(onCreateUsername: (() -> Void)?)
    }

    let kind: Kind

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
                    .accessibilityHidden(true)

                    VStack(spacing: 4) {
                        Text(title)
                            .dashFont(.title3Medium)
                            .foregroundColor(Color.dash.primaryText)

                        Text(message)
                            .dashFont(.subhead)
                            .foregroundColor(Color.dash.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                }

                action
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch kind {
        case .noApps:
            return NSLocalizedString("No apps connected yet", comment: "DashConnect")
        case .noUsername:
            return NSLocalizedString("Sign in to apps without passwords", comment: "DashConnect: no username")
        }
    }

    private var message: String {
        switch kind {
        case .noApps:
            return NSLocalizedString(
                "Connect your DashPay username to apps on the Dash network to sign in without passwords or accounts",
                comment: "DashConnect")
        case .noUsername:
            return NSLocalizedString(
                "Apps on the Dash network use your Platform identity instead of accounts and passwords",
                comment: "DashConnect: no username")
        }
    }

    @ViewBuilder
    private var action: some View {
        switch kind {
        case let .noApps(onScanQR, onMockScan):
            ScanQRButton(onScanQR: onScanQR, onMockScan: onMockScan)
                .padding(.horizontal, 60)
        case let .noUsername(onCreateUsername):
            if let onCreateUsername {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Create username", comment: ""),
                    fillsWidth: true, size: .large, style: .filledBlue, action: onCreateUsername)
                    .frame(maxWidth: 200)
            }
        }
    }
}

#Preview("No apps") {
    ConnectionsEmptyState(kind: .noApps(onScanQR: {}, onMockScan: {}))
        .background(Color.primaryBackground)
}

#Preview("No username") {
    ConnectionsEmptyState(kind: .noUsername(onCreateUsername: {}))
        .background(Color.primaryBackground)
}

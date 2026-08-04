//
//  ConnectionRow.swift
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

/// One connected app: its name and url, the current status, and — once the
/// connection is live — the switch that lets this wallet forget it.
///
/// An approved connection is not usable yet, so the row carries the prompt to
/// finish the login underneath itself rather than leaving the list to know
/// which rows need it.
struct ConnectionRow: View {
    let connection: DAppConnection
    let onPrimaryAction: () -> Void
    let onMockScan: () -> Void
    let onDisconnect: () -> Void

    private enum Layout {
        /// `SwitchView` is a fixed 64×28 from the design system and sets that
        /// width internally, so an outer `.frame` cannot shrink it — it would
        /// only change the space reserved while the control kept overflowing.
        /// Scaling is the only way to make it smaller from the outside; the
        /// design ratio is preserved.
        static let switchScale: CGFloat = 0.75
        static let switchWidth: CGFloat = 64 * switchScale
        static let switchHeight: CGFloat = 28 * switchScale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                identity

                ConnectionStatusBadge(status: connection.status, updatedAt: connection.updatedAt)
                    .fixedSize(horizontal: true, vertical: false)

                if connection.status == .active {
                    activeSwitch
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            if connection.status == .approved {
                ScanToCompleteBanner(onScanQR: onPrimaryAction, onMockScan: onMockScan)
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(connection.name)
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.primaryText)
                .lineLimit(1)

            if !connection.url.isEmpty {
                Text(connection.url)
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Always reads as on: the row only shows it for an active connection, and
    /// only the off direction is reachable from here. Turning it off locally
    /// downgrades the connection back to `.approved`; it does not sign the user
    /// out of the app, because the wallet has no channel to end that session.
    private var activeSwitch: some View {
        ZStack {
            SwitchView(isOn: .constant(true))
                .allowsHitTesting(false)
                .scaleEffect(Layout.switchScale)
        }
        .frame(width: Layout.switchWidth, height: Layout.switchHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDisconnect)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(NSLocalizedString("Disconnect", comment: "DashConnect")))
    }
}

#Preview {
    VStack(spacing: 2) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionRow(
                connection: DAppConnection(
                    id: status.rawValue,
                    name: "A Very Long Application Name Indeed",
                    url: "https://example.org",
                    status: status,
                    updatedAt: Date(timeIntervalSince1970: 1_754_232_520)
                ),
                onPrimaryAction: {},
                onMockScan: {},
                onDisconnect: {}
            )
        }
    }
    .padding()
    .background(Color.primaryBackground)
}

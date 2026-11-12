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

/// One connected app: its name and url, the current status, and the switch
/// that turns it off.
struct ConnectionRow: View {
    let connection: DAppConnection
    let onDisconnect: () -> Void
    /// Takes a Refused row off the list: no PIN, nothing written to Platform.
    let onRemove: () -> Void

    /// What this row offers, read from the state-to-actions table (ADR-0019).
    static func actions(for status: ConnectionStatus) -> Set<AppConnect.RowAction> {
        AppConnect.StateActions.row(for: status).actions
    }

    private enum Layout {
        /// `SwitchView` is a fixed 64×28 from the design system and sets that
        /// width internally, so an outer `.frame` cannot shrink it — it would
        /// only change the space reserved while the control kept overflowing.
        /// Scaling is the only way to make it smaller from the outside; the
        /// design ratio is preserved.
        static let switchScale: CGFloat = 0.75
        static let switchWidth: CGFloat = 64 * switchScale
        static let switchHeight: CGFloat = 28 * switchScale
        /// The scaled switch draws at 48×21, and the tap gesture lives on that
        /// shape alone — under the 44pt minimum. The hit area is grown around
        /// the control without changing what is drawn.
        static let minimumTouchTarget: CGFloat = 44
    }

    var body: some View {
        HStack(spacing: 12) {
            identity

            ConnectionStatusBadge(status: connection.status, updatedAt: connection.updatedAt)
                .fixedSize(horizontal: true, vertical: false)

            let actions = Self.actions(for: connection.status)

            // A confirming connection may get its keys yet: turning it off
            // makes sure it never does.
            if actions.contains(.disconnect) {
                activeSwitch
            }

            if actions.contains(.remove) {
                removeButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var removeButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Remove", comment: "DashConnect: takes a refused connection off the list"),
            size: .small, style: .tintedGray, action: onRemove)
            .fixedSize()
            .accessibilityLabel(Text(NSLocalizedString("Remove", comment: "DashConnect: takes a refused connection off the list")))
    }

    /// Always reads as on: only the off direction is reachable from here.
    /// Turning it off turns the app's keys off on the identity and removes
    /// the row (see `DashConnectDataSource.disconnect`).
    private var activeSwitch: some View {
        ZStack {
            SwitchView(isOn: .constant(true))
                .allowsHitTesting(false)
                .scaleEffect(Layout.switchScale)
        }
        .frame(width: Layout.switchWidth, height: Layout.switchHeight)
        .frame(minWidth: Layout.minimumTouchTarget, minHeight: Layout.minimumTouchTarget)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDisconnect)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(NSLocalizedString("Disconnect", comment: "DashConnect")))
    }
}

private func previewConnection(_ status: ConnectionStatus, name: String = "A Very Long Application Name Indeed") -> DAppConnection {
    DAppConnection(
        id: status.rawValue,
        name: name,
        url: "https://example.org",
        status: status,
        updatedAt: Date(timeIntervalSince1970: 1_754_232_520)
    )
}

#Preview("All statuses") {
    VStack(spacing: 2) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionRow(connection: previewConnection(status), onDisconnect: {}, onRemove: {})
        }
    }
    .padding()
    .background(Color.primaryBackground)
}

#Preview("Refused") {
    ConnectionRow(connection: previewConnection(.refused), onDisconnect: {}, onRemove: {})
        .padding()
        .background(Color.primaryBackground)
}

#Preview("Active, long name") {
    ConnectionRow(
        connection: previewConnection(.active, name: String(repeating: "Extremely Long Application Name ", count: 4)),
        onDisconnect: {}, onRemove: {})
        .padding()
        .background(Color.primaryBackground)
}

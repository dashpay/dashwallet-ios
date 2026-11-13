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

/// One app on the Connections page: its name and website, which open the
/// connection's sheet, and the action its status allows (ADR-0019).
/// Disconnect opens the sheet too, which asks first; Remove takes a Refused
/// row off the list without a PIN.
struct ConnectionRow: View {
    let item: ConnectionSheetItem
    let onOpen: () -> Void
    let onDisconnect: () -> Void
    let onRemove: () -> Void

    /// What a row offers, read from the state-to-actions table.
    static func actions(for status: ConnectionStatus) -> Set<AppConnect.RowAction> {
        AppConnect.StateActions.row(for: status).actions
    }

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .dashFont(.callout)
                        .foregroundStyle(Color.dash.primaryText)
                        .lineLimit(1)

                    if !item.url.isEmpty {
                        Text(item.url)
                            .dashFont(.caption1)
                            .foregroundStyle(Color.dash.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            action
        }
        .padding(.trailing, 14)
    }

    @ViewBuilder
    private var action: some View {
        let actions = Self.actions(for: item.status)
        if actions.contains(.disconnect) {
            disconnectButton
        } else if actions.contains(.remove) {
            removeButton
        }
    }

    private var disconnectButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Disconnect", comment: "DashConnect"),
            size: .small, style: .tintedGray, action: onDisconnect)
            .fixedSize()
            .accessibilityLabel(Text(String(
                format: NSLocalizedString(
                    "Disconnect %@", comment: "DashConnect: accessibility, a row's button; the app's name"),
                item.name)))
    }

    private var removeButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Remove", comment: "DashConnect: takes a refused connection off the list"),
            size: .small, style: .tintedGray, action: onRemove)
            .fixedSize()
            .accessibilityLabel(Text(NSLocalizedString("Remove", comment: "DashConnect: takes a refused connection off the list")))
    }
}

#Preview("Statuses") {
    VStack(spacing: 2) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionRow(
                item: ConnectionSheetItem(
                    id: status.rawValue, name: "Example App", url: "example.org", status: status, connection: nil),
                onOpen: {}, onDisconnect: {}, onRemove: {})
        }
    }
    .background(Color.dash.secondaryBackground)
}

#Preview("Long name, no website") {
    ConnectionRow(
        item: ConnectionSheetItem(
            id: "long", name: "A Very Long Application Name That Does Not Fit On One Line", url: "",
            status: .active, connection: nil),
        onOpen: {}, onDisconnect: {}, onRemove: {})
    .background(Color.dash.secondaryBackground)
}

#Preview("Refused") {
    ConnectionRow(
        item: ConnectionSheetItem(id: "refused", name: "Example App", url: "example.org", status: .refused, connection: nil),
        onOpen: {}, onDisconnect: {}, onRemove: {})
    .background(Color.dash.secondaryBackground)
}

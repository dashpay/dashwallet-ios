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
/// row off the list without a PIN; Reconnect opens the scanner for a new
/// request.
struct ConnectionRow: View {
    let item: ConnectionSheetItem
    let onOpen: () -> Void
    let onDisconnect: () -> Void
    let onRemove: () -> Void
    let onReconnect: () -> Void

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

    /// One button: Reconnect where the table allows it (a disconnected app,
    /// and an expired one as in Figma, whose sheet offers Disconnect too),
    /// else Disconnect, else Remove.
    @ViewBuilder
    private var action: some View {
        let actions = Self.actions(for: item.status)
        if actions.contains(.reconnect) {
            DashUIKit.DashButton(
                text: NSLocalizedString("Reconnect", comment: "DashConnect connection sheet"),
                size: .small, style: .tintedBlue, action: onReconnect)
                .fixedSize()
                .accessibilityLabel(Text(String(
                    format: NSLocalizedString(
                        "Reconnect %@", comment: "DashConnect: accessibility, a row's button; the app's name"),
                    item.name)))
        } else if actions.contains(.disconnect) {
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

private func previewItem(
    _ id: String, name: String = "Example App", url: String = "example.org", _ status: ConnectionStatus
) -> ConnectionSheetItem {
    ConnectionSheetItem(id: id, name: name, url: url, status: status, connection: nil, entry: nil, scope: nil)
}

#Preview("Statuses") {
    VStack(spacing: 2) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionRow(item: previewItem("\(status)", status), onOpen: {}, onDisconnect: {}, onRemove: {}, onReconnect: {})
        }
    }
    .background(Color.dash.secondaryBackground)
}

#Preview("Long name, no website") {
    ConnectionRow(
        item: previewItem("long", name: "A Very Long Application Name That Does Not Fit On One Line", url: "", .active),
        onOpen: {}, onDisconnect: {}, onRemove: {}, onReconnect: {})
    .background(Color.dash.secondaryBackground)
}

#Preview("Refused") {
    ConnectionRow(item: previewItem("refused", .refused), onOpen: {}, onDisconnect: {}, onRemove: {}, onReconnect: {})
    .background(Color.dash.secondaryBackground)
}

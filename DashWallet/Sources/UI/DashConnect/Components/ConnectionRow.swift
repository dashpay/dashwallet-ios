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
/// connection's sheet, and the action that fits its status. Disconnect opens
/// the sheet too, which asks first.
struct ConnectionRow: View {
    let item: ConnectionSheetItem
    let onOpen: () -> Void
    let onDisconnect: () -> Void

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

    /// Every connection offers a disconnect: the app's keys may be on in
    /// each status.
    private var action: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Disconnect", comment: "DashConnect"),
            size: .small, style: .tintedGray, action: onDisconnect)
            .fixedSize()
            .accessibilityLabel(Text(String(
                format: NSLocalizedString(
                    "Disconnect %@", comment: "DashConnect: accessibility, a row's button; the app's name"),
                item.name)))
    }
}

#Preview("Statuses") {
    VStack(spacing: 2) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionRow(
                item: ConnectionSheetItem(
                    id: status.rawValue, name: "Example App", url: "example.org", status: status, connection: nil),
                onOpen: {}, onDisconnect: {})
        }
    }
    .background(Color.dash.secondaryBackground)
}

#Preview("Long name, no website") {
    ConnectionRow(
        item: ConnectionSheetItem(
            id: "long", name: "A Very Long Application Name That Does Not Fit On One Line", url: "",
            status: .active, connection: nil),
        onOpen: {}, onDisconnect: {})
    .background(Color.dash.secondaryBackground)
}

//
//  ConnectionsList.swift
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

/// The apps of one tab of the Connections page, in one card.
struct ConnectionsList: View {
    let items: [ConnectionSheetItem]
    let onOpen: (ConnectionSheetItem) -> Void
    let onDisconnect: (ConnectionSheetItem) -> Void
    let onRemove: (ConnectionSheetItem) -> Void
    let onReconnect: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(items) { item in
                ConnectionRow(
                    item: item, onOpen: { onOpen(item) },
                    onDisconnect: { onDisconnect(item) },
                    onRemove: { onRemove(item) },
                    onReconnect: onReconnect)
            }
        }
        .modifier(MenuViewModifier())
    }
}

#Preview("Several apps") {
    ConnectionsList(
        items: ConnectionStatus.allCases.map { status in
            ConnectionSheetItem(
                id: "\(status)", name: "Example App \(status)", url: "example.org", status: status,
                connection: nil, entry: nil, scope: nil)
        },
        onOpen: { _ in }, onDisconnect: { _ in }, onRemove: { _ in }, onReconnect: {})
    .padding(20)
    .background(Color.primaryBackground)
}

#Preview("One app") {
    ConnectionsList(
        items: [ConnectionSheetItem(
            id: "one", name: "Yappr", url: "yap.pr", status: .active, connection: nil, entry: nil, scope: nil)],
        onOpen: { _ in }, onDisconnect: { _ in }, onRemove: { _ in }, onReconnect: {})
    .padding(20)
    .background(Color.primaryBackground)
}

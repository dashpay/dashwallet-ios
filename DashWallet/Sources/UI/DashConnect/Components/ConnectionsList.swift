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

/// The populated state: every connection stacked in one card. Rows carry their
/// own status-specific content, so this only owns the card chrome and scroll.
struct ConnectionsList: View {
    let connections: [DAppConnection]
    let onScanQR: () -> Void
    let onMockScan: () -> Void
    let onDisconnect: (DAppConnection) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(connections) { connection in
                    ConnectionRow(
                        connection: connection,
                        onPrimaryAction: onScanQR,
                        onMockScan: onMockScan,
                        onDisconnect: { onDisconnect(connection) }
                    )
                }
            }
            .modifier(MenuViewModifier())
        }
    }
}

#Preview {
    ConnectionsList(
        connections: ConnectionStatus.allCases.map { status in
            DAppConnection(
                id: status.rawValue,
                name: "Example App",
                url: "https://example.org",
                status: status,
                updatedAt: Date()
            )
        },
        onScanQR: {},
        onMockScan: {},
        onDisconnect: { _ in }
    )
    .padding(20)
    .background(Color.primaryBackground)
}

//
//  ConnectionStatusBadge.swift
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

/// The status column of a connection row: a coloured dot with the status name,
/// above the moment that status was last reached.
struct ConnectionStatusBadge: View {
    let status: ConnectionStatus
    let updatedAt: Date

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM yyyy, H:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)

                Text(title)
                    .dashFont(.footnote)
                    .foregroundColor(Color.dash.primaryText)
                    .lineLimit(1)
            }

            Text(Self.dateFormatter.string(from: updatedAt))
                .dashFont(.footnote)
                .foregroundColor(Color.dash.tertiaryText)
                .lineLimit(1)
        }
    }

    /// Green only once the connection is live; the only other state is
    /// `approved`, which reads as neutral blue while it waits for the next scan.
    private var dotColor: Color {
        status == .active ? Color.dash.green : Color.dash.blue
    }

    private var title: String {
        switch status {
        case .approved:
            return NSLocalizedString("Approved", comment: "DashConnect")
        case .active:
            return NSLocalizedString("Active", comment: "DashConnect")
        }
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 16) {
        ForEach(ConnectionStatus.allCases, id: \.self) { status in
            ConnectionStatusBadge(
                status: status,
                updatedAt: Date(timeIntervalSince1970: 1_754_232_520)
            )
        }
    }
    .padding()
    .background(Color.primaryBackground)
}

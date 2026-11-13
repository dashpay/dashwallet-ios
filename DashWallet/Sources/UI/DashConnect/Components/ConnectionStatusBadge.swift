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
                    .fill(Self.dotColor(for: status))
                    .frame(width: 8, height: 8)

                Text(Self.label(for: status))
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

    /// The dot colour of a status, from the state-to-actions table (ADR-0019):
    /// green once live, orange while waiting or when the app never got its
    /// keys, red when refused, grey for a connection that is over or lapsed.
    static func dotColor(for status: ConnectionStatus) -> Color {
        switch AppConnect.StateActions.row(for: status).badge {
        case .green: return Color.dash.green
        case .orange: return Color.dash.orange
        case .red: return Color.dash.red
        case .grey: return Color.dash.gray500
        }
    }

    /// The localized status name: the table's text key, never the raw value.
    static func label(for status: ConnectionStatus) -> String {
        switch status {
        case .confirming:
            return NSLocalizedString("Confirming", comment: "DashConnect: an approval whose identity update may still land")
        case .active:
            return NSLocalizedString("Active", comment: "DashConnect")
        case .undelivered:
            return NSLocalizedString("Not delivered", comment: "DashConnect: keys are on the identity, but the app never got its response")
        case .refused:
            return NSLocalizedString("Refused", comment: "DashConnect: status of a request the wallet turned down")
        case .expired:
            return NSLocalizedString("Expired", comment: "DashConnect: status of a connection whose access time ended")
        case .disconnected:
            return NSLocalizedString("Disconnected (connection status)", comment: "DashConnect: the status badge of a connection whose keys are all turned off")
        }
    }
}

#Preview("All statuses") {
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

#Preview("Refused") {
    ConnectionStatusBadge(status: .refused, updatedAt: Date(timeIntervalSince1970: 1_754_232_520))
        .padding()
        .background(Color.primaryBackground)
}

#Preview("Expired") {
    ConnectionStatusBadge(status: .expired, updatedAt: Date(timeIntervalSince1970: 1_754_232_520))
        .padding()
        .background(Color.primaryBackground)
}

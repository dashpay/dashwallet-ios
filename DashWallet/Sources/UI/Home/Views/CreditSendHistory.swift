//
//  Created by Roman Chornyi
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
//  Outgoing Platform-address and identity credit sends in the home history:
//  the list item projected from `CreditSendRecord`, and the detail sheet a
//  tapped row opens. See `CreditSendActivityStore.swift` for what is recorded.
//

import DashUIKit
import Foundation
import SwiftUI

// MARK: - List item

struct CreditSendActivityItem: Identifiable, Equatable {
    let recordId: Int64
    let send: CreditSend
    let isPending: Bool
    /// The destination is one of the wallet's own addresses or identities: a transfer of own funds, not a send.
    let isOwnDestination: Bool
    let date: Date

    init(record: CreditSendRecord, isOwnDestination: Bool) {
        recordId = record.id
        send = record.send
        isPending = record.status == .pending
        self.isOwnDestination = isOwnDestination
        date = record.sentAt
    }

    var id: String { "credit-send-\(recordId)" }

    var title: String {
        isOwnDestination
            ? String(localized: "Internal Transfer", comment: "Transaction within the wallet, transfer of own funds")
            : String(localized: "Sent", comment: "")
    }

    /// Row pill: where the money went, shortened, for a send; none for an own transfer, whose icon pair names the
    /// route.
    var detailsText: String? {
        isOwnDestination ? nil : ShieldedActivityItem.shortAddress(send.destination)
    }

    var trailingStatusText: String? {
        isPending ? String(localized: "Pending", comment: "") : nil
    }

    /// The source balance's symbol, as on the Internal transfer cards.
    var sourceSymbol: String {
        switch send.source {
        case .platform: return "creditcard.fill"
        case .identity: return "person.crop.circle.fill"
        }
    }

    /// Corner badge: the own destination's symbol, or the sent arrow.
    var secondarySymbol: String {
        guard isOwnDestination else { return "arrow.up" }
        switch send.destinationKind {
        case .core: return "d.circle.fill"
        case .platform: return "creditcard.fill"
        case .identity: return "person.crop.circle.fill"
        }
    }

    /// Negative for a send; an own transfer moved funds and keeps no sign.
    var signedDashAmount: Int64 {
        let magnitude = Int64(clamping: send.amountDuffs)
        return isOwnDestination ? magnitude : -magnitude
    }

    var fiatAmount: String {
        CurrencyExchanger.shared.fiatAmountString(for: send.amountDuffs.dashAmount)
    }

    var shortTimeString: String {
        DWDateFormatter.sharedInstance.timeOnly(from: date)
    }

    var sourceName: String {
        switch send.source {
        case .platform:
            return String(
                localized: "Your Platform balance", comment: "Shielded activity: source/destination of an internal move")
        case .identity:
            return String(localized: "Your identity", comment: "")
        }
    }

    /// The destination as the detail sheet names it: the own balance, or the recipient in full.
    var destinationName: String {
        guard isOwnDestination else { return send.destination }
        switch send.destinationKind {
        case .core:
            return String(
                localized: "Your Transparent balance", comment: "Shielded activity: source/destination of an internal move")
        case .platform:
            return String(
                localized: "Your Platform balance", comment: "Shielded activity: source/destination of an internal move")
        case .identity:
            return String(localized: "Your identity", comment: "")
        }
    }
}

// MARK: - Detail sheet

/// Read-only detail for one recorded Platform or identity send.
struct CreditSendActivityDetailsView: View {
    let item: CreditSendActivityItem

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: item.sourceSymbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.dash.blue)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.dash.blue.opacity(0.08)))
                    .accessibilityHidden(true)
                Image(systemName: item.secondarySymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.dash.blue))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
            .padding(.top, 24)

            Text(item.title)
                .font(.headline)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 12)

            DashAmount(amount: item.signedDashAmount, font: .title2, showDirection: !item.isOwnDestination)
                .padding(.top, 4)
            Text(item.fiatAmount)
                .font(.footnote)
                .foregroundColor(.dash.tertiaryText)
                .padding(.top, 2)

            VStack(spacing: 0) {
                infoRow(String(localized: "From", comment: ""), item.sourceName)
                if item.isOwnDestination {
                    infoRow(String(localized: "To", comment: ""), item.destinationName)
                } else {
                    copyableRow(String(localized: "To", comment: ""), item.destinationName)
                }
                if let status = item.trailingStatusText {
                    infoRow(String(localized: "Status", comment: "Transaction details"), status)
                }
                infoRow(
                    String(localized: "Date", comment: ""),
                    DWDateFormatter.sharedInstance.longString(from: item.date))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.dash.tertiaryText)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(.dash.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func copyableRow(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(.dash.tertiaryText)
                Spacer()
                Text(value.prefix(8) + "…" + value.suffix(8))
                    .font(.footnote)
                    .monospaced()
                    .foregroundColor(.dash.primaryText)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.dash.blue)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

private func previewItem(
    source: CreditSendSource, kind: CreditSendDestinationKind, destination: String, own: Bool,
    status: CreditSendStatus = .sent, amountDuffs: UInt64 = 1_000_000
) -> CreditSendActivityItem {
    CreditSendActivityItem(
        record: CreditSendRecord(
            id: 1, operationId: "preview", walletId: Data(repeating: 1, count: 32), networkRaw: 1,
            send: CreditSend(source: source, destinationKind: kind, destination: destination, amountDuffs: amountDuffs),
            status: status, sentAt: Date(timeIntervalSince1970: 1_800_000_000)),
        isOwnDestination: own)
}

#Preview("Sent to a Platform address") {
    CreditSendActivityDetailsView(item: previewItem(
        source: .platform, kind: .platform, destination: "tdash1krma5z0gmqlwsr8c7n8ac8c3g2xk9ns0ue2k9yh", own: false))
}

#Preview("Sent to an identity, pending") {
    CreditSendActivityDetailsView(item: previewItem(
        source: .identity, kind: .identity, destination: "8kSGh4JiXHrswkG5ckapT6zkJ3qrH1V9X2ELYrQo4Jdy",
        own: false, status: .pending))
}

#Preview("Internal transfer to Core") {
    CreditSendActivityDetailsView(item: previewItem(
        source: .platform, kind: .core, destination: "yP8A3cbdxRtLRduy5mXDsBnJtMzHWs6ZXr", own: true))
}

#Preview("Large amount") {
    CreditSendActivityDetailsView(item: previewItem(
        source: .identity, kind: .core, destination: "yP8A3cbdxRtLRduy5mXDsBnJtMzHWs6ZXr", own: false,
        amountDuffs: 2_100_000_000_000_000))
}

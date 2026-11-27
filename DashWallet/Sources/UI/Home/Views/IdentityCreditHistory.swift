//
//  IdentityCreditHistory.swift
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
//  Credits someone else sent to the Current identity, in the home history: the list item projected from
//  `IdentityCreditActivityRecord` and the detail sheet a tapped row opens (ADR-0017).
//

import DashUIKit
import Foundation
import SwiftUI

// MARK: - List item

struct IdentityCreditActivityItem: Identifiable, Equatable {
    let recordId: Int64
    /// The identity's username, or its shortened id when it has none.
    let identityName: String
    let amountDuffs: Int64
    let balanceAfterDuffs: Int64
    let date: Date

    init(record: IdentityCreditActivityRecord, identityName: String) {
        recordId = record.id
        self.identityName = identityName
        amountDuffs = record.amountDuffs
        balanceAfterDuffs = record.balanceAfterDuffs
        date = record.observedAt
    }

    var id: String { "identity-credit-\(recordId)" }

    var title: String {
        String(localized: "Received", comment: "")
    }

    /// Row pill: the identity that received the credits.
    var detailsText: String {
        identityName
    }

    var signedDashAmount: Int64 {
        amountDuffs
    }

    var fiatAmount: String {
        CurrencyExchanger.shared.fiatAmountString(for: UInt64(max(0, amountDuffs)).dashAmount)
    }

    var shortTimeString: String {
        DWDateFormatter.sharedInstance.timeOnly(from: date)
    }
}

// MARK: - Detail sheet

/// Read-only detail for credits received by the identity. Platform reports the balance, not the sender, and the date
/// is when the wallet read the balance.
struct IdentityCreditActivityDetailsView: View {
    let item: IdentityCreditActivityItem

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.dash.blue)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.dash.blue.opacity(0.08)))
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.dash.blue))
                    .offset(x: 4, y: 4)
            }
            .padding(.top, 24)

            Text(item.title)
                .font(.headline)
                .foregroundColor(.dash.primaryText)
                .padding(.top, 12)

            DashAmount(amount: item.signedDashAmount, font: .title2, showDirection: true)
                .padding(.top, 4)
            Text(item.fiatAmount)
                .font(.footnote)
                .foregroundColor(.dash.tertiaryText)
                .padding(.top, 2)

            VStack(spacing: 0) {
                infoRow(String(localized: "Type", comment: ""), String(localized: "Identity", comment: ""))
                infoRow(String(localized: "To", comment: ""), item.identityName)
                HStack(alignment: .firstTextBaseline) {
                    Text(String(localized: "Balance after", comment: "Platform address payment detail"))
                        .font(.footnote)
                        .foregroundColor(.dash.tertiaryText)
                    Spacer()
                    DashAmount(amount: item.balanceAfterDuffs, font: .footnote, showDirection: false)
                }
                .padding(.vertical, 10)
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

            // swiftlint:disable:next line_length
            Text(String(localized: "Platform doesn't identify who sent identity credits. They were recorded when the wallet noticed the balance change — they may have arrived earlier.", comment: "Identity credits received detail"))
                .font(.caption)
                .foregroundColor(.dash.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 16)

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
}

// MARK: - Previews

private func identityCreditSample(
    name: String, amountDuffs: Int64, balanceAfterDuffs: Int64
) -> IdentityCreditActivityItem {
    IdentityCreditActivityItem(
        record: IdentityCreditActivityRecord(
            id: 1, walletId: Data(repeating: 0x01, count: 32), networkRaw: 1,
            identityId: Data(repeating: 0x02, count: 32), amountDuffs: amountDuffs,
            balanceAfterDuffs: balanceAfterDuffs, observedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        identityName: name)
}

#Preview("Received") {
    IdentityCreditActivityDetailsView(
        item: identityCreditSample(name: "alice", amountDuffs: 1_042_000, balanceAfterDuffs: 5_000_000))
}

#Preview("Long name, large amount") {
    IdentityCreditActivityDetailsView(
        item: identityCreditSample(
            name: "a-very-long-username-that-wraps-0123456789", amountDuffs: 2_100_000_000_000_000,
            balanceAfterDuffs: 2_100_000_000_000_000))
}

#Preview("No username") {
    IdentityCreditActivityDetailsView(
        item: identityCreditSample(name: "8kSGh4…QoJdy", amountDuffs: 1, balanceAfterDuffs: 1))
}

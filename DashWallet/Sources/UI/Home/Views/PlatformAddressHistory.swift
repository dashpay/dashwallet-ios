//
//  PlatformAddressHistory.swift
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
//  Observed incoming Platform-address payments in the home history:
//  the list item projected from `PlatformAddressActivityRecord`, and
//  the detail sheet a tapped row opens. See
//  `PlatformAddressActivityStore.swift` for what gets recorded (and
//  the honest limits of observation-time attribution).
//

import Foundation
import SwiftUI

// MARK: - List item

struct PlatformAddressActivityItem: Identifiable {
    let recordId: Int64
    let address: String
    let amountDuffs: Int64
    let balanceAfterDuffs: Int64
    let date: Date

    init(record: PlatformAddressActivityRecord) {
        recordId = record.id
        address = record.address
        amountDuffs = record.amountDuffs
        balanceAfterDuffs = record.balanceAfterDuffs
        date = record.observedAt
    }

    var id: String { "platform-activity-\(recordId)" }

    var title: String {
        NSLocalizedString("Received", comment: "")
    }

    /// Row pill: the receiving address, shortened — mirrors the external
    /// shielded rows.
    var detailsText: String {
        String(address.prefix(6)) + "…" + String(address.suffix(6))
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

/// Read-only detail for one observed Platform-address payment. There is
/// deliberately little to show: Platform payments carry no sender, and
/// the timestamp is when the wallet observed the balance change.
struct PlatformAddressActivityDetailsView: View {
    let item: PlatformAddressActivityItem

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.dashBlue)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.dashBlue.opacity(0.08)))
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.dashBlue))
                    .offset(x: 4, y: 4)
            }
            .padding(.top, 24)

            Text(item.title)
                .font(.headline)
                .foregroundColor(.primaryText)
                .padding(.top, 12)

            DashAmount(amount: item.signedDashAmount, font: .title2, showDirection: true)
                .padding(.top, 4)
            Text(item.fiatAmount)
                .font(.footnote)
                .foregroundColor(.tertiaryText)
                .padding(.top, 2)

            VStack(spacing: 0) {
                infoRow(
                    NSLocalizedString("Type", comment: ""),
                    NSLocalizedString("Platform", comment: ""))
                copyableRow(NSLocalizedString("To", comment: ""), item.address)
                HStack(alignment: .firstTextBaseline) {
                    Text(NSLocalizedString("Balance after", comment: "Platform address payment detail"))
                        .font(.footnote)
                        .foregroundColor(.tertiaryText)
                    Spacer()
                    DashAmount(amount: item.balanceAfterDuffs, font: .footnote, showDirection: false)
                }
                .padding(.vertical, 10)
                infoRow(
                    NSLocalizedString("Date", comment: ""),
                    DWDateFormatter.sharedInstance.longString(from: item.date))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Text(NSLocalizedString("Platform payments don't identify the sender. This payment was recorded when the wallet noticed the balance change — it may have arrived earlier.", comment: "Platform address payment detail"))
                .font(.caption)
                .foregroundColor(.tertiaryText)
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
                .foregroundColor(.tertiaryText)
            Spacer()
            Text(value)
                .font(.footnote)
                .foregroundColor(.primaryText)
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
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text(value.prefix(8) + "…" + value.suffix(8))
                    .font(.footnote)
                    .monospaced()
                    .foregroundColor(.primaryText)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.dashBlue)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

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

import SwiftUI
import DashUIKit

/// The confirm sheet's four-row summary: where the money leaves, where it
/// lands, what the network charges, and what the source is out in total.
///
/// Strings in, rows out. Which transfer produced them — a balance route or
/// either direction of an identity transfer — is `TransferConfirmSummary`'s
/// problem, so the card can be looked at on its own in the canvas, including
/// the em-dash states that are otherwise only reachable without a wallet.
struct TransferSummaryCard: View {
    let from: String
    let to: String
    /// The fee row's label travels with its value: what a transfer is charged
    /// for is not the same on every route.
    let networkFeeLabel: String
    let networkFee: String
    let total: String

    init(summary: TransferConfirmSummary) {
        self.init(
            from: summary.from,
            to: summary.to,
            networkFeeLabel: summary.networkFeeLabel,
            networkFee: summary.networkFee,
            total: summary.total)
    }

    init(
        from: String,
        to: String,
        networkFeeLabel: String = NSLocalizedString("Network fee", comment: ""),
        networkFee: String,
        total: String
    ) {
        self.from = from
        self.to = to
        self.networkFeeLabel = networkFeeLabel
        self.networkFee = networkFee
        self.total = total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(label: NSLocalizedString("From", comment: ""), value: from)
            row(label: NSLocalizedString("To", comment: ""), value: to)
            row(label: networkFeeLabel, value: networkFee)
            row(label: NSLocalizedString("Total", comment: ""), value: total)
        }
        .modifier(MenuViewModifier())
    }

    /// `MenuItem` with the value as its text accessory — the same pairing the
    /// design system uses for a "Network fee" row. Note this puts the label on
    /// the prominent line and the value on the muted one, which is the
    /// system's convention and the reverse of what this card drew by hand.
    private func row(label: String, value: String) -> some View {
        DashUIKit.MenuItem(title: label, accessory: .text(value))
    }
}

#if DEBUG

private func summaryCardSample(
    from: String = "Transparent balance",
    to: String = "Shielded balance",
    networkFee: String = "~ $0.08",
    total: String = "0.5 DASH"
) -> some View {
    TransferSummaryCard(from: from, to: to, networkFee: networkFee, total: total)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Balance route") {
    summaryCardSample()
}

/// Either identity direction: one endpoint is the identity rather than a
/// balance, and the withdrawal has no fee estimate to print.
@available(iOS 17, *)
#Preview("To Identity") {
    summaryCardSample(from: "Shielded balance", to: "Identity")
}

@available(iOS 17, *)
#Preview("From Identity") {
    summaryCardSample(
        from: "Identity",
        to: "Transparent balance",
        networkFee: TransferConfirmSummary.unavailable)
}

/// Every figure unavailable — what the card shows when the SDK cannot price
/// the transfer.
@available(iOS 17, *)
#Preview("Nothing to show") {
    summaryCardSample(
        from: TransferConfirmSummary.unavailable,
        to: TransferConfirmSummary.unavailable,
        networkFee: TransferConfirmSummary.unavailable,
        total: TransferConfirmSummary.unavailable)
}

#endif

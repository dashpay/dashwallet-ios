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

import Foundation

/// The four rows of the confirm sheet's summary card, resolved for whichever
/// of the three transfers is being confirmed.
///
/// The sheet takes a balance route, an identity top-up or an identity
/// withdrawal, and exactly one is ever set. Each row used to pick between them
/// on its own, so the same three-way branch was written out four times and a
/// fourth transfer kind would have to find all four. Resolving them together
/// puts that decision in one place — and makes the "exactly one" assumption
/// something a reader can check at a glance rather than infer.
///
/// Every figure fails closed: an unavailable estimate becomes an em dash
/// rather than a number the sheet cannot stand behind. `canContinue` has
/// already refused the transfer by the time that could matter.
@MainActor
struct TransferConfirmSummary {
    /// Placeholder for a figure that cannot be produced.
    static let unavailable = "—"

    let from: String
    let to: String
    let networkFee: String
    let total: String

    init(
        route: InternalTransferRoute?,
        identityTopUp: IdentityTopUpTransfer?,
        identityWithdrawal: IdentityWithdrawalTransfer?,
        dashDuffs: Int64,
        amountDuffsUnsigned: UInt64,
        withdrawalFeeCredits: UInt64?
    ) {
        let identityName = InternalTransferSummaryFigures.identityEndpointName

        if let identityTopUp {
            from = InternalTransferSummaryFigures.balanceName(identityTopUp.source)
            to = identityName
            networkFee = InternalTransferSummaryFigures.identityTopUpFeeFiat(
                source: identityTopUp.source) ?? Self.unavailable
            total = InternalTransferSummaryFigures.identityTopUpTotal(dashDuffs: dashDuffs)
            return
        }

        if let identityWithdrawal {
            from = identityName
            to = InternalTransferSummaryFigures.balanceName(identityWithdrawal.target.network)
            networkFee = InternalTransferSummaryFigures.identityWithdrawalFeeFiat ?? Self.unavailable
            total = InternalTransferSummaryFigures.identityTopUpTotal(dashDuffs: dashDuffs)
            return
        }

        guard let route else {
            from = Self.unavailable
            to = Self.unavailable
            networkFee = Self.unavailable
            total = Self.unavailable
            return
        }

        let endpoints = InternalTransferSummaryFigures.endpoints(of: route)
        from = InternalTransferSummaryFigures.balanceName(endpoints.from)
        to = InternalTransferSummaryFigures.balanceName(endpoints.to)
        networkFee = InternalTransferSummaryFigures.networkFeeFiat(
            route: route,
            withdrawalFeeCredits: withdrawalFeeCredits) ?? Self.unavailable
        total = InternalTransferSummaryFigures.totalLeavingSource(
            route: route,
            dashDuffs: dashDuffs,
            amountDuffsUnsigned: amountDuffsUnsigned) ?? Self.unavailable
    }
}

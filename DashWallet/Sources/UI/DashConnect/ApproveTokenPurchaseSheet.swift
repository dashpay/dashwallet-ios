//
//  ApproveTokenPurchaseSheet.swift
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

/// Asks the user to approve a token purchase a dApp handed the wallet via a
/// `dash-st:` payload. Everything shown here comes from the wallet's own
/// parse of that payload; on approve the purchase is rebuilt and signed by
/// the wallet — the incoming bytes themselves are never signed.
struct ApproveTokenPurchaseSheet: View {
    let request: DashConnectTokenPurchaseRequest
    var isLoading: Bool = false
    /// Why the last approve attempt failed. Shown here rather than as a
    /// screen alert: an alert on the presenting screen cannot appear over
    /// this sheet, so the user would otherwise see nothing at all.
    var errorText: String?
    var onApprove: () -> Void
    var onDeny: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray300Alpha50)
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 20)

            // The detail rows grow with Dynamic Type; without a scroll
            // container the actions can be pushed below the bottom of the
            // sheet, leaving the user unable to approve or deny. The actions
            // stay pinned under the scroll area.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("Approve token purchase?", comment: "DashConnect token purchase"))
                            .font(.title2)
                            .foregroundColor(.primaryText)

                        Text(resolvedSubtitle)
                            .font(.subhead)
                            .foregroundColor(.secondaryText)
                    }

                    detailBox {
                        DashConnectDetailRow(
                            label: NSLocalizedString("Tokens", comment: "DashConnect token purchase"),
                            value: tokenCountText
                        )
                        DashConnectDetailRow(
                            label: NSLocalizedString("Token ID", comment: "DashConnect token purchase"),
                            value: DashConnectIdentifierFormatting.truncateMiddle(request.tokenId.toBase58String())
                        )
                        DashConnectDetailRow(
                            label: NSLocalizedString("Total price", comment: "DashConnect token purchase"),
                            value: request.totalPriceDash.formattedDashAmount
                        )
                    }

                    detailBox {
                        if let walletUsername = request.walletUsername {
                            DashConnectDetailRow(
                                label: NSLocalizedString("Username", comment: "DashConnect"),
                                value: walletUsername
                            )
                        }
                        DashConnectDetailRow(
                            label: NSLocalizedString("Identity", comment: "DashConnect"),
                            value: DashConnectIdentifierFormatting.truncateMiddle(request.walletIdentityId)
                        )
                    }

                    Text(NSLocalizedString(
                        "Approving pays the total price from this identity's Platform credits.",
                        comment: "DashConnect token purchase"
                    ))
                    .font(.footnote)
                    .foregroundColor(.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }

            VStack(spacing: 8) {
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundColor(Color.dash.errorText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)
                }

                DashButton(
                    text: NSLocalizedString("Approve", comment: "DashConnect"),
                    style: .filledBlue,
                    size: .large,
                    stretch: true,
                    isEnabled: !isLoading,
                    isLoading: isLoading,
                    action: onApprove
                )

                DashButton(
                    text: NSLocalizedString("Deny", comment: "DashConnect"),
                    style: .tintedBlue,
                    size: .large,
                    stretch: true,
                    isEnabled: !isLoading,
                    action: onDeny
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color.primaryBackground)
    }

    /// The requesting app's stored name when a connection for the purchase's
    /// contract exists locally; the contract id otherwise, so the user always
    /// sees which contract the purchase belongs to.
    private var resolvedSubtitle: String {
        if let appName = request.appName?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty {
            return appName
        }
        return String(
            format: NSLocalizedString("Contract %@", comment: "DashConnect token purchase"),
            DashConnectIdentifierFormatting.truncateMiddle(request.dataContractId.toBase58String())
        )
    }

    private var tokenCountText: String {
        Decimal(request.tokenCount).string
    }

    private func detailBox(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 4) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray300, lineWidth: 1.5)
        )
    }
}

// MARK: - Previews

/// Ungated like `MockDashConnectDataSource`'s samples: `#Preview` bodies
/// compile in every configuration, so preview fixtures cannot be DEBUG-only.
private let sampleTokenPurchaseRequest = DashConnectTokenPurchaseRequest(
    appName: "Yappr",
    ownerId: Data(repeating: 0x11, count: 32),
    dataContractId: Data(repeating: 0xcd, count: 32),
    tokenId: Data(repeating: 0xab, count: 32),
    tokenContractPosition: 0,
    tokenCount: 100,
    totalAgreedPriceCredits: 50_000_000_000,
    walletUsername: "dashuser",
    walletIdentityId: "5DbLwAxEWR695MsqP4KybNQD5n7CUDWydJYNg63FzUo8"
)

#Preview("Token Purchase") {
    ApproveTokenPurchaseSheet(
        request: sampleTokenPurchaseRequest,
        onApprove: {},
        onDeny: {}
    )
}

#Preview("Token Purchase Loading") {
    ApproveTokenPurchaseSheet(
        request: sampleTokenPurchaseRequest,
        isLoading: true,
        onApprove: {},
        onDeny: {}
    )
}

#Preview("Token Purchase Error") {
    ApproveTokenPurchaseSheet(
        request: sampleTokenPurchaseRequest,
        errorText: "Could not complete the DashConnect request: no CRITICAL authentication key.",
        onApprove: {},
        onDeny: {}
    )
}

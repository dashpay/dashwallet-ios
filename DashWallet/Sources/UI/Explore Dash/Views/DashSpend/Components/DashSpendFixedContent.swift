//
//  Created by Roman Chornyi
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

struct DashSpendFixedContent: View {
    @ObservedObject var viewModel: DashSpendPayViewModel
    @Binding var quantities: [Decimal: Int]
    let onAction: () -> Void

    private var total: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let sum = quantities.reduce(Decimal(0)) { $0 + $1.key * Decimal($1.value) }
        return formatter.string(from: NSDecimalNumber(decimal: sum)) ?? "0"
    }

    private var denominations: [Decimal] {
        viewModel.denominations.map { Decimal($0) }
    }

    private var actionEnabled: Bool {
        !quantities.isEmpty &&
        viewModel.error == nil &&
        !viewModel.isLoading &&
        !viewModel.isProcessingPayment
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                DashSpendPayIntro(
                    merchantIconUrl: viewModel.merchantIconUrl,
                    merchantTitle: viewModel.merchantTitle,
                    isMixing: viewModel.isMixing,
                    dashBalance: viewModel.isMixing ? viewModel.coinJoinBalance : viewModel.walletBalance
                )

                DashSpendAmountView(
                    currencySymbol: viewModel.currencySymbol,
                    amount: total
                )
                .frame(height: 85)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 10)

            DashSpendMultiplePanel(
                denominations: denominations,
                quantities: $quantities,
                actionEnabled: actionEnabled,
                inProgress: viewModel.isProcessingPayment,
                error: viewModel.error,
                showCost: !quantities.isEmpty && viewModel.error == nil,
                costMessage: viewModel.costMessage,
                inventoryLimits: viewModel.denominationInventory.reduce(into: [:]) { $0[Decimal($1.key)] = $1.value },
                onContinue: onAction,
                onReset: { quantities.removeAll() }
            )
            .onChange(of: quantities) { newQuantities in
                let total = newQuantities.reduce(Decimal(0)) { $0 + $1.key * Decimal($1.value) }
                viewModel.updateTotalAmount(total, quantities: newQuantities)
            }
        }
    }
}

#Preview {
    DashSpendFixedContentPreview()
        .background(Color.primaryBackground)
}

private struct DashSpendFixedContentPreview: View {
    @State private var quantities: [Decimal: Int] = [:]

    var body: some View {
        DashSpendFixedContent(
            viewModel: FixedPreviewViewModel(),
            quantities: $quantities,
            onAction: {}
        )
    }
}

private class FixedPreviewViewModel: DashSpendPayViewModel {
    override var isMixing: Bool { false }
    override func subscribeToUpdates() {}
    override func unsubscribeFromAll() {}

    init() {
        let merchant = ExplorePointOfUse(
            id: 2, name: "Domino's",
            category: .merchant(ExplorePointOfUse.Merchant(
                merchantId: "dominos-123", paymentMethod: .giftCard, type: .online,
                deeplink: nil, savingsBasisPoints: 500, denominationsType: "fixed",
                denominations: [5, 25, 50, 100], redeemType: "online",
                giftCardProviders: [ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                    providerId: "ctx", savingsPercentage: 500,
                    denominationsType: "fixed", sourceId: nil
                )]
            )),
            active: true, city: nil, territory: nil,
            address1: nil, address2: nil, address3: nil, address4: nil,
            latitude: nil, longitude: nil, website: nil, phone: nil,
            logoLocation: nil, coverImage: nil, source: "ctx"
        )
        super.init(merchant: merchant, provider: .ctx)
        merchantTitle = "Domino's"
        denominations = [5, 25, 50]
    }
}

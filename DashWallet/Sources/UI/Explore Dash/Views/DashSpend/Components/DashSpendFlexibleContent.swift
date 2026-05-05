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

enum DashSpendMode: CaseIterable, Hashable {
    case single
    case multiple

    var localizedTitle: String {
        switch self {
        case .single: return NSLocalizedString("Single", comment: "DashSpend")
        case .multiple: return NSLocalizedString("Multiple", comment: "DashSpend")
        }
    }
}

struct DashSpendFlexibleContent: View {
    @ObservedObject var viewModel: DashSpendPayViewModel
    @Binding var quantities: [Decimal: Int]
    let onAction: () -> Void

    @State private var segmentSelection: DashSpendMode = .single
    @State private var goingForward: Bool = true
    private let multipleMaxAmount: Decimal = PiggyCardsConstants.maxOrderAmount

    private var multipleTotal: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: multipleTotalAmount)) ?? "0"
    }

    private var multipleTotalAmount: Decimal {
        quantities.reduce(Decimal(0)) { $0 + $1.key * Decimal($1.value) }
    }

    private var multipleShowCost: Bool {
        guard !quantities.isEmpty, viewModel.error == nil else { return false }
        guard viewModel.hasValidLimits else { return false }
        return multipleTotalAmount >= viewModel.minimumAmount && multipleTotalAmount <= multipleMaxAmount
    }

    private var multipleActionEnabled: Bool {
        !quantities.isEmpty &&
        viewModel.error == nil &&
        !viewModel.isLoading &&
        multipleTotalAmount >= viewModel.minimumAmount &&
        multipleTotalAmount <= multipleMaxAmount
    }

    private var multipleDenominations: [Decimal] {
        let minimum = max(Decimal(5), viewModel.minimumAmount)
        let maximum = min(Decimal(500), viewModel.maximumAmount)
        guard minimum > 0, maximum >= minimum else { return [] }

        return buildMultipleDenominations(minimum: minimum, maximum: maximum, targetCount: 4)
    }

    private func buildMultipleDenominations(minimum: Decimal, maximum: Decimal, targetCount: Int) -> [Decimal] {
        var uniqueValues: [Decimal] = []
        var seen: Set<Decimal> = []

        func appendIfUnique(_ rawValue: Decimal) {
            let clamped = min(max(rawValue, minimum), maximum)
            let rounded = roundedToCents(clamped)
            guard !seen.contains(rounded) else { return }
            seen.insert(rounded)
            uniqueValues.append(rounded)
        }

        // Keep the 4-point design as the primary shape.
        [minimum, minimum * 2, maximum / 2, maximum].forEach(appendIfUnique)

        // Fill missing slots deterministically when collisions happen.
        if uniqueValues.count < targetCount {
            let span = maximum - minimum
            let fallbackValues: [Decimal] = [
                minimum + span / 4,
                minimum + span / 3,
                minimum + span * 2 / 3,
                minimum + span * 3 / 4,
                minimum + 1,
                maximum - 1
            ]

            for value in fallbackValues {
                appendIfUnique(value)
                if uniqueValues.count == targetCount { break }
            }
        }

        // Last-resort filler for very narrow ranges (e.g. min == max).
        if uniqueValues.count < targetCount {
            var probe = minimum
            while uniqueValues.count < targetCount {
                appendIfUnique(probe)
                probe += 0.01
                if probe > maximum { break }
            }
        }

        return Array(uniqueValues.prefix(targetCount))
    }

    private func roundedToCents(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }

    var body: some View {
        if viewModel.supportsMultipleMode {
            multiModeBody
        } else {
            singleModeBody
        }
    }

    // CTX: simple single-panel layout, no multiple mode state involved
    private var singleModeBody: some View {
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
                    amount: viewModel.input
                )
                .frame(height: 85)
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)

            DashSpendSinglePanel(
                isLoading: viewModel.isLoading,
                hasValidLimits: viewModel.hasValidLimits,
                isFixedDenomination: false,
                denominations: [],
                selectedDenomination: nil,
                actionEnabled: viewModel.error == nil && !viewModel.isLoading,
                inProgress: viewModel.isProcessingPayment,
                input: $viewModel.input,
                showLimits: viewModel.showLimits,
                error: viewModel.error,
                minimumLimitMessage: viewModel.minimumLimitMessage,
                maximumLimitMessage: viewModel.maximumLimitMessage,
                amount: viewModel.amount,
                minimumAmount: viewModel.minimumAmount,
                maximumAmount: viewModel.maximumAmount,
                showCost: viewModel.showCost,
                costMessage: viewModel.costMessage,
                onDenominationSelected: { _ in },
                onAction: onAction
            )
            .ignoresSafeArea(.all, edges: .bottom)
        }
    }

    // PiggyCards: SegmentedControl + Single/Multiple panels with animation
    private var multiModeBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                DashSpendPayIntro(
                    merchantIconUrl: viewModel.merchantIconUrl,
                    merchantTitle: viewModel.merchantTitle,
                    isMixing: viewModel.isMixing,
                    dashBalance: viewModel.isMixing ? viewModel.coinJoinBalance : viewModel.walletBalance
                )
                SegmentedControl(
                    options: DashSpendMode.allCases,
                    selection: Binding(
                        get: { segmentSelection },
                        set: { newValue in
                            guard newValue != segmentSelection else { return }
                            goingForward = newValue == .multiple
                            withAnimation(.easeInOut(duration: 0.3)) {
                                segmentSelection = newValue
                            }
                            if newValue == .single {
                                // Restore single-mode amount-driven validation after returning
                                // from multiple mode where total is derived from quantities.
                                viewModel.updateTotalAmount(viewModel.input.decimal() ?? 0)
                            }
                        }
                    ),
                    label: \.localizedTitle
                )
                DashSpendAmountView(
                    currencySymbol: viewModel.currencySymbol,
                    amount: segmentSelection == .multiple ? multipleTotal : viewModel.input
                )
                .frame(height: 85)
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)

            if segmentSelection == .single {
                DashSpendSinglePanel(
                    isLoading: viewModel.isLoading,
                    hasValidLimits: viewModel.hasValidLimits,
                    isFixedDenomination: false,
                    denominations: [],
                    selectedDenomination: nil,
                    actionEnabled: viewModel.error == nil && !viewModel.isLoading,
                    inProgress: viewModel.isProcessingPayment,
                    input: $viewModel.input,
                    showLimits: viewModel.showLimits,
                    error: viewModel.error,
                    minimumLimitMessage: viewModel.minimumLimitMessage,
                    maximumLimitMessage: viewModel.maximumLimitMessage,
                    amount: viewModel.amount,
                    minimumAmount: viewModel.minimumAmount,
                    maximumAmount: viewModel.maximumAmount,
                    showCost: viewModel.showCost,
                    costMessage: viewModel.costMessage,
                    onDenominationSelected: { _ in },
                    onAction: onAction
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: goingForward ? 50 : -50)),
                    removal: .opacity.combined(with: .offset(x: goingForward ? -50 : 50))
                ))
                .ignoresSafeArea(.all, edges: .bottom)
            } else {
                DashSpendMultiplePanel(
                    denominations: multipleDenominations,
                    quantities: $quantities,
                    actionEnabled: multipleActionEnabled,
                    inProgress: false,
                    error: viewModel.error,
                    showCost: multipleShowCost,
                    costMessage: viewModel.costMessage,
                    inventoryLimits: [:],
                    onContinue: onAction,
                    onReset: { quantities.removeAll() }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: goingForward ? 50 : -50)),
                    removal: .opacity.combined(with: .offset(x: goingForward ? -50 : 50))
                ))
                .ignoresSafeArea(.all, edges: .bottom)
                .onChange(of: quantities) { newQuantities in
                    let total = newQuantities.reduce(Decimal(0)) { $0 + $1.key * Decimal($1.value) }
                    viewModel.updateTotalAmount(total)
                }
                .onAppear {
                    viewModel.updateTotalAmount(multipleTotalAmount)
                }
            }
        }
    }
}

#Preview("Single / Keyboard") {
    DashSpendFlexibleContentPreview()
        .background(Color.primaryBackground)
}

private struct DashSpendFlexibleContentPreview: View {
    @State private var quantities: [Decimal: Int] = [:]

    var body: some View {
        DashSpendFlexibleContent(
            viewModel: FlexiblePreviewViewModel(),
            quantities: $quantities,
            onAction: {}
        )
    }
}

private class FlexiblePreviewViewModel: DashSpendPayViewModel {
    override var isMixing: Bool { false }
    override func subscribeToUpdates() {}
    override func unsubscribeFromAll() {}

    init() {
        let merchant = ExplorePointOfUse(
            id: 1, name: "Amazon",
            category: .merchant(ExplorePointOfUse.Merchant(
                merchantId: "amazon-123", paymentMethod: .giftCard, type: .online,
                deeplink: nil, savingsBasisPoints: 1000, denominationsType: "range",
                denominations: [], redeemType: "online",
                giftCardProviders: [ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                    providerId: "ctx", savingsPercentage: 1000,
                    denominationsType: "range", sourceId: nil
                )]
            )),
            active: true, city: nil, territory: nil,
            address1: nil, address2: nil, address3: nil, address4: nil,
            latitude: nil, longitude: nil, website: nil, phone: nil,
            logoLocation: nil, coverImage: nil, source: "ctx"
        )
        super.init(merchant: merchant, provider: .ctx)
        merchantTitle = "Amazon"
        minimumAmount = 5
        maximumAmount = 100
    }
}

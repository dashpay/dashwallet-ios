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

import DashUIKit
import SwiftUI

extension View {
    func bottomPanelStyle() -> some View {
        self
            .padding(.horizontal, 20)
            .background(Color.secondaryBackground)
//            .padding(.bottom, 30)
            .cornerRadius(20)
    }
}

struct DashSpendSinglePanel: View {
    let isLoading: Bool
    let hasValidLimits: Bool
    let isFixedDenomination: Bool
    let denominations: [Int]
    let selectedDenomination: Int?
    let actionEnabled: Bool
    let inProgress: Bool
    @Binding var input: String
    let showLimits: Bool
    let error: (any Error)?
    let minimumLimitMessage: String
    let maximumLimitMessage: String
    let amount: Decimal
    let minimumAmount: Decimal
    let maximumAmount: Decimal
    let showCost: Bool
    let costMessage: String
    let onDenominationSelected: (Int) -> Void
    let onAction: () -> Void

    var body: some View {
        if isFixedDenomination {
            if isLoading && denominations.isEmpty {
                loadingView
            } else {
                denominationsView
            }
        } else {
            keyboardView
        }
    }

    @ViewBuilder
    private var costMessageView: some View {
        if showCost {
            Text(costMessage)
                .font(.subhead)
                .foregroundColor(Color.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var limitsView: some View {
        if let error = error {
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(Color.systemRed)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
        } else if hasValidLimits {
            HStack {
                Text(minimumLimitMessage)
                    .font(.caption)
                    .foregroundColor(amount > 0 && amount < minimumAmount ? Color.systemRed : Color.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(maximumLimitMessage)
                    .font(.caption)
                    .foregroundColor(amount > maximumAmount ? Color.systemRed : Color.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 12)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("Loading gift card options...", comment: "DashSpend"))
                .font(.subhead)
                .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var denominationsView: some View {
        MerchantDenominations(
            denominations: denominations,
            selectedDenomination: selectedDenomination,
            actionEnabled: selectedDenomination != nil && actionEnabled,
            onDenominationSelected: onDenominationSelected,
            actionHandler: onAction
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .bottomPanelStyle()
    }

    private var keyboardView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                limitsView

                costMessageView
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            NumericKeyboardView(
                value: $input,
                showDecimalSeparator: true,
                actionButtonText: NSLocalizedString("Continue", comment: ""),
                actionEnabled: actionEnabled && !showLimits && hasValidLimits,
                inProgress: inProgress,
                actionHandler: onAction
            )
            .frame(maxWidth: .infinity)
            .bottomPanelStyle()
            .background(Color.secondaryBackground, ignoresSafeAreaEdges: .bottom)
        }

    }
}

#Preview("Keyboard") {
    DashSpendSinglePanelKeyboardPreview()
}

#Preview("Fixed denominations") {
    DashSpendSinglePanelDenominationsPreview()
}

#Preview("Loading") {
    DashSpendSinglePanel(
        isLoading: true,
        hasValidLimits: false,
        isFixedDenomination: false,
        denominations: [],
        selectedDenomination: nil,
        actionEnabled: false,
        inProgress: false,
        input: .constant(""),
        showLimits: false,
        error: nil,
        minimumLimitMessage: "",
        maximumLimitMessage: "",
        amount: 0,
        minimumAmount: 0,
        maximumAmount: 0,
        showCost: false,
        costMessage: "",
        onDenominationSelected: { _ in },
        onAction: {}
    )
}

private struct DashSpendSinglePanelKeyboardPreview: View {
    @State private var input = "0"

    var body: some View {
        DashSpendSinglePanel(
            isLoading: false,
            hasValidLimits: true,
            isFixedDenomination: false,
            denominations: [],
            selectedDenomination: nil,
            actionEnabled: true,
            inProgress: false,
            input: $input,
            showLimits: true,
            error: nil,
            minimumLimitMessage: "Min $5",
            maximumLimitMessage: "Max $100",
            amount: 0,
            minimumAmount: 5,
            maximumAmount: 100,
            showCost: true,
            costMessage: "You are buying a $50 gift card for $45.00 (10% discount)",
            onDenominationSelected: { _ in },
            onAction: {}
        )
        .background(Color.primaryBackground)
    }
}

private struct DashSpendSinglePanelDenominationsPreview: View {
    @State private var selected: Int? = nil

    var body: some View {
        DashSpendSinglePanel(
            isLoading: false,
            hasValidLimits: true,
            isFixedDenomination: true,
            denominations: [5, 10, 25, 50, 100],
            selectedDenomination: selected,
            actionEnabled: selected != nil,
            inProgress: false,
            input: .constant(""),
            showLimits: false,
            error: nil,
            minimumLimitMessage: "",
            maximumLimitMessage: "",
            amount: 0,
            minimumAmount: 0,
            maximumAmount: 0,
            showCost: false,
            costMessage: "",
            onDenominationSelected: { selected = $0 },
            onAction: {}
        )
        .background(Color.primaryBackground)
    }
}

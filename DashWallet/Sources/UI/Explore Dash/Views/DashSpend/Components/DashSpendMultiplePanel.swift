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

struct DashSpendMultiplePanel: View {
    let denominations: [Decimal]
    @Binding var quantities: [Decimal: Int]
    let actionEnabled: Bool
    let inProgress: Bool
    let error: (any Error)?
    let showCost: Bool
    let costMessage: String
    let inventoryLimits: [Decimal: Int]
    let onContinue: () -> Void
    let onReset: () -> Void

    private var inventoryWarning: String? {
        for (denomination, count) in quantities where count > 0 {
            if let limit = inventoryLimits[denomination], count >= limit {
                return String(
                    format: NSLocalizedString("Merchant has only %d cards available", comment: "DashSpend"),
                    limit
                )
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                DenominationCard(
                    denominations: denominations,
                    quantities: $quantities,
                    inventoryLimits: inventoryLimits,
                    onReset: onReset
                )

                if let warning = inventoryWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 10/255, green: 11/255, blue: 13/255).opacity(0.7))
                        .cornerRadius(10)
                        .offset(y: 20)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                if let error = error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(Color.systemRed)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                } else if showCost {
                    Text(costMessage)
                        .font(.subhead)
                        .foregroundColor(Color.primaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                DashButton(
                    text: NSLocalizedString("Continue", comment: "DashSpend"),
                    isEnabled: actionEnabled,
                    isLoading: inProgress,
                    action: onContinue
                )
                .padding(.horizontal, 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
}

private struct DenominationCard: View {
    let denominations: [Decimal]
    @Binding var quantities: [Decimal: Int]
    let inventoryLimits: [Decimal: Int]
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(denominations, id: \.self) { denomination in
                DashSpendDenominationRow(
                    denomination: denomination,
                    count: Binding(
                        get: { quantities[denomination] ?? 0 },
                        set: { newValue in
                            if newValue > 0 {
                                quantities[denomination] = newValue
                            } else {
                                quantities.removeValue(forKey: denomination)
                            }
                        }
                    ),
                    inventoryLimit: inventoryLimits[denomination]
                )
            }

            if !quantities.isEmpty {
                HStack {
                    Spacer()
                    DashButton(
                        text: NSLocalizedString("Reset", comment: "DashSpend"),
                        size: .extraSmall,
                        action: onReset
                    )
                    .overrideForegroundColor(.primaryText)
                    .overrideBackgroundColor(.gray300Alpha10)
                    .frame(maxWidth: 126, alignment: .trailing)
                }
            }
        }
        .padding(20)
        .background(Color.secondaryBackground)
        .cornerRadius(20)
    }
}

#Preview {
    DashSpendMultiplePanelPreview()
}

private struct DashSpendMultiplePanelPreview: View {
    @State private var quantities: [Decimal: Int] = [:]

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()

            DashSpendMultiplePanel(
                denominations: [5, 10, 50, 100],
                quantities: $quantities,
                actionEnabled: !quantities.isEmpty,
                inProgress: false,
                error: quantities.isEmpty ? DashSpendError.customError("You can buy up to $2,500 in gift cards per order") : nil,
                showCost: !quantities.isEmpty,
                costMessage: "You are buying a $150 gift cards for $135.00 (10% discount)",
                inventoryLimits: [50: 3],
                onContinue: {},
                onReset: { quantities.removeAll() }
            )
        }
    }
}

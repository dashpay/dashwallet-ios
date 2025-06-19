//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

struct MerchantDenominations: View {
    let denominations: [Int]
    let currency: String = "USD"
    @Binding var selectedDenomination: Int?
    let canContinue: Bool = true
    let onDenominationSelected: (Int) -> Void = { _ in }
    let onContinue: () -> Void = { }
    
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 76, maximum: 120), spacing: 16)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("Select amount", comment: "DashSpend denomination selection"))
                .font(.h5Bold)
                .foregroundColor(.primaryText)
            
            Text(NSLocalizedString("Select fixed amount", comment: "DashSpend denomination selection subtitle"))
                .font(.body2)
                .foregroundColor(.secondaryText)
                .padding(.top, 4)
            
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(denominations, id: \.self) { denomination in
                    DenominationChip(
                        denomination: denomination,
                        isSelected: denomination == selectedDenomination,
                        formattedValue: numberFormatter.string(from: NSNumber(value: denomination)) ?? "\(denomination)",
                        onTap: {
                            onDenominationSelected(denomination)
                        }
                    )
                }
            }
            .padding(.top, 20)
            
            DashButton(
                text: NSLocalizedString("Continue", comment: ""),
                style: .filled,
                size: .large,
                stretch: true,
                isEnabled: selectedDenomination != nil && selectedDenomination != 0 && canContinue,
                action: onContinue
            )
            .padding(.top, 20)
        }
    }
}

private struct DenominationChip: View {
    let denomination: Int
    let isSelected: Bool
    let formattedValue: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(formattedValue)
                .font(.subtitle1)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(width: 76, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? Color.dashBlue.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isSelected ? Color.dashBlue : Color.gray400,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

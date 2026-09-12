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

struct DashAmount: View {
    var amount: Int64
    var font: Font = .footnote
    var dashSymbolFactor: CGFloat = 1
    var showDirection = true
    
    var body: some View {
        if amount == Int64.max || amount == Int64.min {
            Text(NSLocalizedString("Not available", comment: ""))
                .font(font)
                .fontWeight(.medium)
        } else {
            let formattedAbsAmount = abs(amount).formattedDashAmount
            let directionSymbol = directionSymbol(of: amount)
            let cleanedAbsAmount = cleanAmount(formattedAbsAmount)

            // Dash symbol always trails the number (e.g. "0.06791 Ð"), consistently across the app.
            HStack(spacing: 0) {
                if showDirection {
                    Text(directionSymbol)
                        .font(font)
                        .fontWeight(.medium)
                }

                Text(cleanedAbsAmount)
                    .font(font)
                    .fontWeight(.medium)
                    .lineLimit(1)

                DashSymbol()
                    .padding(.leading, 2)
            }
            // The currency symbol is an image, so the stack is collapsed into a
            // single element with a spoken label; child-by-child, VoiceOver
            // reads the digits and then the image asset name, never "Dash".
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spokenAmount(cleanedAbsAmount)))
        }
    }
    
    @ViewBuilder
    private func DashSymbol() -> some View {
        Image("icon_dash_currency")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: font.pointSize * dashSymbolFactor, height: font.pointSize * dashSymbolFactor)
    }

    private func directionSymbol(of dashAmount: Int64) -> String {
        if dashAmount > 0 {
            return "+"
        } else if dashAmount < 0 {
            return "-"
        } else {
            return ""
        }
    }
    
    /// The VoiceOver utterance for the rendered row: the same formatted number
    /// that is displayed, followed by the currency name. The "+"/"-" glyphs
    /// become spoken words only when `showDirection` renders them, so the
    /// utterance always matches what is visible.
    private func spokenAmount(_ cleanedAbsAmount: String) -> String {
        // "Dash" is the currency's proper name and is deliberately left
        // unlocalized, matching the wordmark label in HomeBalanceView.
        let unsignedAmount = "\(cleanedAbsAmount.trimmingCharacters(in: .whitespaces)) Dash"

        guard showDirection else {
            return unsignedAmount
        }

        if amount > 0 {
            return String(
                format: NSLocalizedString("Plus %@", comment: "VoiceOver-only label for an incoming amount; %@ is the amount with its currency, e.g. 'Plus 0.05 Dash'"),
                unsignedAmount)
        } else if amount < 0 {
            return String(
                format: NSLocalizedString("Minus %@", comment: "VoiceOver-only label for an outgoing amount; %@ is the amount with its currency, e.g. 'Minus 0.05 Dash'"),
                unsignedAmount)
        } else {
            return unsignedAmount
        }
    }

    private func cleanAmount(_ amount: String) -> String {
        var result = amount
        
        if let dashSymbolRange = result.range(of: kDashCurrency) {
            result.removeSubrange(dashSymbolRange)
        }
        
        return result
    }
}

/// Shared visual hierarchy for completed sends and attended receives. Keeping
/// the success icon, amount renderer, typography, and spacing in one place
/// prevents the two halves of a payment from drifting apart visually.
struct PaymentSuccessHeader: View {
    let title: String
    let amountDuffs: Int64
    let fiatText: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundColor(.green)
                .padding(.top, 24)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.dash.primaryText)

            DashAmount(
                amount: amountDuffs,
                font: .title,
                dashSymbolFactor: 0.7,
                showDirection: false)

            Text(fiatText)
                .font(.subheadline)
                .foregroundColor(.dash.secondaryText)
        }
    }
}

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
    
    var body: some View {
        if amount == Int64.max || amount == Int64.min {
            Text(NSLocalizedString("Not available", comment: ""))
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundColor(.primaryText)
        } else {
            let formattedAbsAmount = abs(amount).formattedDashAmount
            let dashSymbolLast = formattedAbsAmount.first!.isNumber
            let directionSymbol = directionSymbol(of: amount)
            let cleanedAbsAmount = cleanAmount(formattedAbsAmount)
            
            HStack(spacing: 0) {
                Text(directionSymbol)
                    .fontWeight(.medium)
                
                if !dashSymbolLast {
                    DashSymbol()
                        .padding(.leading, 2)
                }
                
                Text(cleanedAbsAmount)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .padding(.leading, 2)
                
                if dashSymbolLast {
                    DashSymbol()
                }
            }
            .font(font)
            .foregroundColor(.primaryText)
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
    
    private func cleanAmount(_ amount: String) -> String {
        var result = amount
        
        if let dashSymbolRange = result.range(of: DASH) {
            result.removeSubrange(dashSymbolRange)
        }
        
        return result
    }
}

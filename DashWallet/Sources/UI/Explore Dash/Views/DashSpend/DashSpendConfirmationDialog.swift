//  
//  Created by Andrei Ashikhmin
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
import SDWebImageSwiftUI

struct DashSpendConfirmationDialog: View {
    let amount: String
    let merchantName: String
    let merchantIconUrl: String
    let originalPrice: Decimal
    let discount: Decimal
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.presentationMode) private var presentationMode
    
    private let fiatFormatter = NumberFormatter.fiatFormatter(currencyCode: kDefaultCurrencyCode)
    
    var body: some View {
        VStack(spacing: 40) {
            HStack {
                Text(fiatFormatter.currencySymbol + amount)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.primaryText)
            }
            
            // Details
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(NSLocalizedString("From", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Image("image.explore.dash.wts.dash")
                        .resizable()
                        .frame(width: 24, height: 24)
                            
                    Text(NSLocalizedString("Dash Wallet", comment: "DashSpend"))
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack(spacing: 8) {
                    Text(NSLocalizedString("To", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    WebImage(url: URL(string: merchantIconUrl))
                        .resizable()
                        .indicator(.activity)
                        .transition(.fade(duration: 0.3))
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                            
                    Text(merchantName)
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack {
                    Text(NSLocalizedString("Gift card total", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Text(fiatFormatter.string(from: NSDecimalNumber(decimal: originalPrice)) ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack {
                    Text(NSLocalizedString("Discount", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                        
                    Text(PercentageFormatter.format(percent: NSDecimalNumber(decimal: discount * 100).doubleValue))
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
                    
                HStack {
                    Text(NSLocalizedString("You pay", comment: "DashSpend"))
                        .font(.body2)
                        .fontWeight(.medium)
                        .foregroundColor(.tertiaryText)
                        
                    Spacer()
                    
                    Text(fiatFormatter.string(from: NSDecimalNumber(decimal: originalPrice * (1 - discount))) ?? "")
                        .font(.body2)
                        .foregroundColor(.primaryText)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)
            }
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: Color.shadow, radius: 10, x: 0, y: 5)
            
            HStack(spacing: 20) {
                Button(action: onCancel) {
                    Text(NSLocalizedString("Cancel", comment: "DashSpend"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                }
                .background(Color(UIColor.systemGray5))
                .cornerRadius(12)
                    
                Button(action: onConfirm) {
                    Text(NSLocalizedString("Confirm", comment: "DashSpend"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.dashBlue)
                .cornerRadius(12)
            }
        }
        .padding(.top, 15)
        .padding(.horizontal, 20)
        .edgesIgnoringSafeArea(.bottom)
    }
}

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

typealias TransactionPreview = MenuItem

struct MenuItem: View {
    var title: String
    var subtitle: String? = nil
    var details: String? = nil
    var topText: String? = nil
    var icon: IconName? = nil
    var secondaryIcon: IconName? = nil
    var showInfo: Bool = false
    var showChevron: Bool = false
    var dashAmount: Int64? = nil
    var isToggled: Binding<Bool>? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                ZStack(alignment: .leading) {
                    Icon(name: icon)
                        .frame(width: 28, height: 28)
                        .padding(0)
                    
                    if let secondaryIcon = secondaryIcon {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Icon(name: secondaryIcon)
                                    .padding(2)
                                    .frame(width: 18, height: 18)
                                    .background(Color.secondaryBackground)
                                    .clipShape(.circle)
                                    .offset(x: 2, y: 2)
                            }
                        }
                    }
                }
                .frame(width: 36, height: 36)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                if let topText = topText {
                    Text(topText)
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundColor(.tertiaryText)
                        .padding(.leading, 4)
                        .padding(.bottom, 2)
                }
                
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineSpacing(3)
                        .foregroundColor(.primaryText)
                    
                    if showInfo {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.gray300)
                            .imageScale(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundColor(.tertiaryText)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
                    
                if let details = details {
                    Text(details)
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundColor(.tertiaryText)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            if let isToggled = isToggled {
                Toggle(isOn: isToggled) { }
                    .frame(maxWidth: 60)
            }
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundColor(Color.gray)
                    .padding(.trailing, 10)
            } else {
                VStack(alignment: .trailing) {
                    if let dashAmount = dashAmount {
                        DashAmount(amount: dashAmount)
                        
                        if dashAmount != 0 {
                            FormattedFiatText(from: dashAmount)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66)
        .onTapGesture {
            action?()
        }
    }
    
    @ViewBuilder
    private func FormattedFiatText(from dashAmount: Int64) -> some View {
        let text = (try? CurrencyExchanger.shared.convertDash(amount: abs(dashAmount.dashAmount), to: App.fiatCurrency).formattedFiatAmount) ?? NSLocalizedString("Not available", comment: "")
        
        Text(text)
            .font(.caption)
            .foregroundColor(.secondaryText)
    }
}


#Preview {
    MenuItem(
        title: "Title",
        subtitle: "Easily stake Dash and earn passive income with a few simple steps",
        icon: .system("faceid"),
        showInfo: true,
        isToggled: .constant(true)
    )
}

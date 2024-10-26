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
    @State var subtitleView: AnyView? = nil
    var details: String? = nil
    var topText: String? = nil
    var icon: IconName? = nil
    var secondaryIcon: IconName? = nil
    var showInfo: Bool = false
    var showChevron: Bool = false
    var badgeText: String? = nil
    var dashAmount: Int64? = nil
    var overrideFiatAmount: String? = nil
    var showToggle: Bool = false
    @State var isToggled: Bool = false
    var action: (() -> Void)? = nil

    init(title: String,
         subtitle: String? = nil,
         details: String? = nil,
         topText: String? = nil,
         icon: IconName? = nil,
         secondaryIcon: IconName? = nil,
         showInfo: Bool = false,
         showChevron: Bool = false,
         badgeText: String? = nil,
         dashAmount: Int64? = nil,
         overrideFiatAmount: String? = nil,
         showToggle: Bool = false,
         isToggled: Bool = false,
         action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            subtitleView: subtitle.map {
                AnyView(
                    Text($0)
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundColor(.tertiaryText)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                )
            },
            details: details,
            topText: topText,
            icon: icon,
            secondaryIcon: secondaryIcon,
            showInfo: showInfo,
            showChevron: showChevron,
            badgeText: badgeText,
            dashAmount: dashAmount,
            overrideFiatAmount: overrideFiatAmount,
            showToggle: showToggle,
            isToggled: isToggled,
            action: action
        )
    }

    init(title: String,
         subtitleView: AnyView? = nil,
         details: String? = nil,
         topText: String? = nil,
         icon: IconName? = nil,
         secondaryIcon: IconName? = nil,
         showInfo: Bool = false,
         showChevron: Bool = false,
         badgeText: String? = nil,
         dashAmount: Int64? = nil,
         overrideFiatAmount: String? = nil,
         showToggle: Bool = false,
         isToggled: Bool = false,
         action: (() -> Void)? = nil
    ) {
        self.title = title
        self._subtitleView = State(initialValue: subtitleView)
        self.details = details
        self.topText = topText
        self.icon = icon
        self.secondaryIcon = secondaryIcon
        self.showInfo = showInfo
        self.showChevron = showChevron
        self.dashAmount = dashAmount
        self.badgeText = badgeText
        self.overrideFiatAmount = overrideFiatAmount
        self._isToggled = State(initialValue: isToggled)
        self.showToggle = showToggle
        self.action = action
    }
    
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

                    Spacer()

                    if let badgeText = badgeText {
                        Text(badgeText)
                            .font(.caption)
                            .foregroundColor(.systemYellow)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.systemYellow.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                
                if let subtitle = subtitleView {
                    subtitle
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

            if showToggle {
                Toggle(isOn: $isToggled) { }
                    .tint(Color.dashBlue)
                    .scaleEffect(0.75)
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
                        
                        if dashAmount != 0 && dashAmount != Int64.max && dashAmount != Int64.min {
                            if let overriden = overrideFiatAmount {
                                Text(overriden)
                                    .font(.caption)
                                    .foregroundColor(.secondaryText)
                            } else {
                                FormattedFiatText(from: dashAmount)
                            }
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66)
        .onTapGesture {
            if showToggle {
                isToggled.toggle()
            }
            
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
        showToggle: true,
        isToggled: true
    )
}

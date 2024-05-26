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
    var icon: IconName? = nil
    var secondaryIcon: IconName? = nil
    var showInfo: Bool = false
    var showChevron: Bool = false
    var dashAmount: String? = nil
    var fiatAmount: String? = nil
    var isToggled: Binding<Bool>? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                ZStack {
                    Icon(name: icon)
                        .frame(width: 26, height: 26)
                        .alignmentGuide(.leading) { _ in 0 }
                        .alignmentGuide(.top) { d in d[.top] }
                    
                    if let secondaryIcon = secondaryIcon {
                        Icon(name: secondaryIcon)
                            .frame(width: 15, height: 15)
                            .alignmentGuide(.trailing) { _ in 0 }
                            .alignmentGuide(.bottom) { _ in 0 }
                    }
                }
                .frame(width: 42, height: 42)
            }
            
            VStack(alignment: .leading, spacing: 0) {
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
            .padding(.leading, 2)
                
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, 2)
                    .padding(.top, 2)
            }
                    
            if let details = details {
                Text(details)
                    .font(.caption)
                    .lineSpacing(3)
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, 8)
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
                VStack {
                    if let dashAmount = dashAmount {
                        Text(dashAmount)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.primaryText)
                    }
                    
                    if let fiatAmount = fiatAmount {
                        Text(fiatAmount)
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66)
        .onTapGesture {
            action?()
        }
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

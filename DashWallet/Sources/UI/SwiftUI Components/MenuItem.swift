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

struct MenuItem: View {
    var title: String
    var subtitle: String? = nil
    var details: String? = nil
    var icon: IconName? = nil
    var showInfo: Bool = false
    var showChevron: Bool = false
    var isToggled: Binding<Bool>? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Icon(name: icon)
                    .frame(width: 36, height: 36)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Font.system(size: 14).weight(.medium))
                        .lineSpacing(3)
                        .foregroundColor(.primaryText)
                    
                    if showInfo {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.gray300)
                            .imageScale(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
                
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(Font.system(size: 12))
                    .lineSpacing(3)
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, 8)
                    .padding(.top, 2)
            }
                    
            if let details = details {
                Text(details)
                    .font(Font.system(size: 12))
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
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(Color.background)
        .cornerRadius(8)
        .shadow(color: .shadow, radius: 10, x: 0, y: 5)
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

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

struct MenuItemModel: Identifiable {
    let id = UUID()
    
    var title: String
    var subtitle: String? = nil
    var details: String? = nil
    var icon: Icon? = nil
    var showInfo: Bool = false
    var showChevron: Bool = false
    var isToggled: Binding<Bool>? = nil
    var action: (() -> Void)?
}

enum Icon {
    case system(name: String)
    case custom(name: String)
}

struct MenuItem: View {
    var model: MenuItemModel
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = model.icon {
                ZStack {
                    switch icon {
                    case .system(let name):
                        Image(systemName: name).imageScale(.large)
                    case .custom(let name):
                        Image(name).imageScale(.large)
                    }
                }
                .frame(width: 36, height: 36)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(Font.system(size: 14).weight(.medium))
                        .foregroundColor(.primaryText)
                    
                    if model.showInfo {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.gray300)
                            .imageScale(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
                
            if let subtitle = model.subtitle {
                Text(subtitle)
                    .font(Font.system(size: 12))
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, 8)
                    .padding(.top, 2)
            }
                    
            if let details = model.details {
                Text(details)
                    .font(Font.system(size: 12))
                    .foregroundColor(.tertiaryText)
                    .padding(.leading, 8)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            if let isToggled = model.isToggled {
                Toggle(isOn: isToggled) { }
                    .frame(maxWidth: 60)
            }
            
            if model.showChevron {
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
            model.action?()
        }
    }
}


struct MenuItem_Previews: PreviewProvider {
    static var previews: some View {
        MenuItem(
            model: MenuItemModel(
                title: "Title",
                subtitle: "Easily stake Dash and earn passive income with a few simple steps",
                icon: .system(name: "faceid"),
                showInfo: true,
                isToggled: .constant(true)
            )
        )
    }
}

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

class MenuItemModel: Identifiable, Equatable {
    let id = UUID()
    
    var title: String
    var subtitle: String? = nil
    var details: String? = nil
    var icon: IconName? = nil
    var showInfo: Bool = false
    var showChevron: Bool = false
    var showToggle: Bool = false
    @State var isToggled: Bool = false
    var action: (() -> Void)? = nil
    
    init(title: String, subtitle: String? = nil, details: String? = nil, icon: IconName? = nil, showInfo: Bool = false, showChevron: Bool = false, showToggle: Bool = false, isToggled: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.icon = icon
        self.showInfo = showInfo
        self.showChevron = showChevron
        self.showToggle = showToggle
        self.isToggled = isToggled
        self.action = action
    }
    
    static func == (lhs: MenuItemModel, rhs: MenuItemModel) -> Bool {
        lhs.id == rhs.id
    }
}

class CoinJoinMenuItemModel: MenuItemModel {
    var mixingPercentage: String
    var dashAmount: String

    init(title: String, mixingPercentage: String, dashAmount: String, action: (() -> Void)? = nil) {
        self.mixingPercentage = mixingPercentage
        self.dashAmount = dashAmount
        super.init(title: title, action: action)
    }
}

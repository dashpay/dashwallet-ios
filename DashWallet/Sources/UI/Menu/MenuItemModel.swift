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

class MenuItemModel: Identifiable, Equatable, Hashable {
    let id = UUID()
    
    var title: String
    var subtitle: String? = nil
    var details: String? = nil
    var icon: IconName? = nil
    var showInfo: Bool = false
    var showToggle: Bool = false
    @State var isToggled: Bool = false
    var action: (() -> Void)? = nil
    
    init(title: String, subtitle: String? = nil, details: String? = nil, icon: IconName? = nil, showInfo: Bool = false, showToggle: Bool = false, isToggled: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.icon = icon
        self.showInfo = showInfo
        self.showToggle = showToggle
        self._isToggled = State<Bool>.init(initialValue: isToggled)
        self.action = action
    }
    
    static func == (lhs: MenuItemModel, rhs: MenuItemModel) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class CoinJoinMenuItemModel: MenuItemModel {
    @State var isOn: Bool
    @State var state: MixingStatus
    @State var progress: Double
    @State var mixed: Double
    @State var total: Double

    init(title: String, isOn: Bool, state: MixingStatus, progress: Double, mixed: Double, total: Double, action: (() -> Void)? = nil) {
        self.isOn = isOn
        self.state = state
        self.progress = progress
        self.mixed = mixed
        self.total = total
        super.init(title: title, action: action)
    }

    var description: String {
        return "CoinJoinMenuItemModel(title: \(title), isOn: \(isOn), state: \(state), progress: \(progress), mixed: \(mixed), total: \(total))"
    }
}

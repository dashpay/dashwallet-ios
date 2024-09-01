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

struct MenuItemModel: Identifiable, Equatable {
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
    
    static func == (lhs: MenuItemModel, rhs: MenuItemModel) -> Bool {
        lhs.id == rhs.id
    }
}

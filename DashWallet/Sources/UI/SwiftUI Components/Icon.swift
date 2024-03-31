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

enum IconName {
    case system(_ name: String)
    case custom(_ name: String)
}

struct Icon: View {
    let name: IconName
    
    var body: some View {
        switch name {
        case .system(let name):
            Image(systemName: name).imageScale(.large)
        case .custom(let name):
            Image(name).imageScale(.large)
        }
    }
}

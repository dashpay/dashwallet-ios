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

enum IconName: Equatable {
    case system(_ name: String)
    case custom(_ name: String, maxHeight: CGFloat? = nil)
    case image(_ uiImage: UIImage, effect: ImageEffect = .none)
    
    static func == (lhs: IconName, rhs: IconName) -> Bool {
        switch (lhs, rhs) {
        case (.system(let lhsName), .system(let rhsName)):
            return lhsName == rhsName
        case (.custom(let lhsName, let lhsHeight), .custom(let rhsName, let rhsHeight)):
            return lhsName == rhsName && lhsHeight == rhsHeight
        case (.image(_, let lhsEffect), .image(_, let rhsEffect)):
            return lhsEffect == rhsEffect
        default:
            return false
        }
    }
}

enum ImageEffect: Equatable {
    case none
    case rounded
}

struct Icon: View {
    let name: IconName
    
    var body: some View {
        switch name {
        case .system(let name):
            if #available(iOS 16.0, *) {
                Image(systemName: name)
                    .imageScale(.medium)
                    .fontWeight(.semibold)
            } else {
                Image(systemName: name)
                    .imageScale(.medium)
            }
        case .custom(let name, let height):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: height)
        case .image(let uiImage, let effect):
            if effect == .rounded {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(Circle())
            } else {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

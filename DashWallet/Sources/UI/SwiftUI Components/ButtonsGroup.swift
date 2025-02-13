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

struct ButtonsGroup: View {
    enum Style {
        case regular
        case danger
    }
    
    var orientation: Axis = .vertical
    var style: Style = .regular
    var size: DashButton.Size = .medium
    var positiveActionEnabled: Bool = true
    var positiveButtonText: String? = nil
    var positiveButtonAction: (() -> Void)? = nil
    var negativeButtonText: String? = nil
    var negativeButtonAction: (() -> Void)? = nil
    
    var positiveButton: DashButton? {
        if let text = positiveButtonText {
            return DashButton(
                text: text,
                style: negativeButtonText == nil ? .plain : .filled,
                size: size,
                isEnabled: positiveActionEnabled,
                action: { positiveButtonAction?() }
            )
        }
        
        return nil
    }
    
    var negativeButton: DashButton? {
        if let text = negativeButtonText {
            return DashButton(
                text: text,
                style: .plain,
                size: size,
                action: { negativeButtonAction?() }
            )
        }
        
        return nil
    }
    
    var body: some View {
        if orientation == .vertical {
            VStack(spacing: 6) {
                positiveButton
                    .overrideBackgroundColor(style == .regular ? .dashBlue : .buttonRed)
                    .overrideForegroundColor(negativeButtonText == nil ? .dashBlue : .white)
                negativeButton
                    .overrideForegroundColor(positiveButtonText == nil ? .dashBlue : .primaryText)
            }
        } else {
            HStack(spacing: 6) {
                negativeButton
                    .frame(maxWidth: .infinity)
                    .overrideForegroundColor(positiveButtonText == nil ? .dashBlue : .primaryText)
                positiveButton
                    .frame(maxWidth: .infinity)
                    .overrideBackgroundColor(style == .regular ? .dashBlue : .buttonRed)
                    .overrideForegroundColor(negativeButtonText == nil ? .dashBlue : .white)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

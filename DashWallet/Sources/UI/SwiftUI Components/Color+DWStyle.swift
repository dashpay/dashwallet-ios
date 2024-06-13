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

extension Color {
    static var primaryText: Color {
        Color("Label")
    }
    
    static var secondaryText: Color {
        Color("SecondaryTextColor")
    }
    
    static var tertiaryText: Color {
        Color("TertiaryTextColor")
    }
    
    static var dashBlue: Color {
        Color("DashBlueColor")
    }
    
    static var buttonRed: Color {
        Color("ButtonRedColor")
    }
    
    static var systemRed: Color {
        Color("SystemRedColor")
    }
    
    static var systemYellow: Color {
        Color("SystemYellowColor")
    }
    
    static var gray300: Color {
        Color("Gray300")
    }
    
    static var background: Color {
        Color("BackgroundColor")
    }
    
    static var secondaryBackground: Color {
        Color("SecondaryBackgroundColor")
    }
    
    static var shadow: Color {
        Color(red: 0.72, green: 0.76, blue: 0.8).opacity(0.1)
    }
}

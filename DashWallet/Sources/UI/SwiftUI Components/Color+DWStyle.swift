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
    
    static var navigationBarColor: Color {
        Color("DashNavigationBarBlueColor")
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
    
//    #FFC043
    
    static var gray300: Color {
        Color("Gray300")
    }
    
    static var gray400: Color {
        return Color("Gray400")
    }
    
    static var gray500: Color {
        Color("Gray500")
    }
    
    static var gray50: Color {
        Color("Gray50")
    }
    
    // Background and secondary background are mismatched in the assests.
    // The correct values per the design:
    // Primary background: #F7F7F7
    // Secondary background: #FFFFFF
    static var primaryBackground: Color {
        Color("SecondaryBackgroundColor")
    }
    
    static var secondaryBackground: Color {
        Color("BackgroundColor")
    }
    
    static var shadow: Color {
         Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.5) // TODO
            default:
                return UIColor(red: 0.72, green: 0.76, blue: 0.8, alpha: 0.1)
            }
        })
    }
}

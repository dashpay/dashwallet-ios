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
import UIKit

extension Color {
    
// Text
    
    static var primaryText: Color {
        Color("Label")
    }
    
    static var secondaryText: Color {
        Color("SecondaryTextColor")
    }
    
    static var tertiaryText: Color {
        Color("TertiaryTextColor")
    }
    
// System

    static var blue: Color {
        Color("Blue")
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
    
// Black

    static var blackAlpha5: Color {
        Color("BlackAlpha5")
    }

    static var blackAlpha40: Color {
        Color("BlackAlpha40")
    }

// Gray

    static var gray50: Color {
        Color("Gray50")
    }
    
    static var gray100: Color {
        Color("Gray100")
    }
    
    static var gray200: Color {
        Color("Gray200")
    }
    
    static var gray300: Color {
        Color("Gray300")
    }

    static var gray300Alpha90: Color {
        Color("Gray300Alpha90")
    }

    static var gray300Alpha80: Color {
        Color("Gray300Alpha80")
    }

    static var gray300Alpha70: Color {
        Color("Gray300Alpha70")
    }

    static var gray300Alpha60: Color {
        Color("Gray300Alpha60")
    }

    static var gray300Alpha50: Color {
        Color("Gray300Alpha50")
    }

    static var gray300Alpha40: Color {
        Color("Gray300Alpha40")
    }

    static var gray300Alpha30: Color {
        Color("Gray300Alpha30")
    }

    static var gray300Alpha20: Color {
        Color("Gray300Alpha20")
    }

    static var gray300Alpha10: Color {
        Color("Gray300Alpha10")
    }

    static var gray300Alpha5: Color {
        Color("Gray300Alpha5")
    }

    static var gray400: Color {
        Color("Gray400")
    }
    
    static var gray500: Color {
        Color("Gray500")
    }

// White

    static var white: Color {
        Color("White")
    }

    static var whiteAlpha90: Color {
        Color("WhiteAlpha90")
    }

    static var whiteAlpha80: Color {
        Color("WhiteAlpha80")
    }

    static var whiteAlpha70: Color {
        Color("WhiteAlpha70")
    }

    static var whiteAlpha60: Color {
        Color("WhiteAlpha60")
    }

    static var whiteAlpha50: Color {
        Color("WhiteAlpha50")
    }

    static var whiteAlpha40: Color {
        Color("WhiteAlpha40")
    }

    static var whiteAlpha30: Color {
        Color("WhiteAlpha30")
    }

    static var whiteAlpha20: Color {
        Color("WhiteAlpha20")
    }

    static var whiteAlpha15: Color {
        Color("WhiteAlpha15")
    }

    static var whiteAlpha10: Color {
        Color("WhiteAlpha10")
    }

    static var whiteAlpha5: Color {
        Color("WhiteAlpha5")
    }

    static var transparent: Color {
        Color("Transparent")
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

    // Alias for secondaryBackground for backwards compatibility
    static var background: Color {
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

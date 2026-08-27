//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

import Foundation

enum GiftCardProvider: CaseIterable {
    case ctx
    #if PIGGYCARDS_ENABLED
    case piggyCards
    #endif

    var displayName: String {
        switch self {
        case .ctx:
            return "CTX"
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            return "PiggyCards"
        #endif
        }
    }

    var logoName: String {
        switch self {
        case .ctx:
            return "ctx.logo"
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            return "piggycards.logo"
        #endif
        }
    }

    var termsUrl: String {
        switch self {
        case .ctx:
            return CTXConstants.termsAndConditionsUrl
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            return "https://piggy.cards/index.php?route=information/information&information_id=5"
        #endif
        }
    }

    var supportEmail: String {
        switch self {
        case .ctx:
            return CTXConstants.supportEmail
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            return PiggyCardsConstants.supportEmail
        #endif
        }
    }
}

//  
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

enum PointOfUseListFilters: String {
    case sortAZ
    case sortZA
    case sortDistance
    case paymentTypeDash
    case paymentTypeGiftCard
    case radius1
    case radius5
    case radius20
    case radius50
    case location
    case locationService
    case reset
    
    var cellIdentifier: String {
        switch self {
        case .reset: return "FilterItemResetCell"
        case .location, .locationService: return "FilterItemDisclosureCell"
        default: return "FilterItemSelectableCell"
        }
    }
    
    var image: String? {
        switch self {
        case .paymentTypeDash:
            return "image.explore.dash.wts.payment.dash"
        case .paymentTypeGiftCard:
            return "image.explore.dash.wts.payment.gift-card"
        default: return nil
        }
    }
    
    var title: String {
        switch self {
            
        case .sortAZ:
            return NSLocalizedString("Name: from A to Z", comment: "Explore Dash: Filters")
        case .sortZA:
            return NSLocalizedString("Name: from Z to A", comment: "Explore Dash: Filters")
        case .paymentTypeDash:
            return NSLocalizedString("Dash", comment: "Explore Dash: Filters")
        case .paymentTypeGiftCard:
            return NSLocalizedString("Gift Card", comment: "Explore Dash: Filters")
        case .radius1:
            return NSLocalizedString("1 mile", comment: "Explore Dash: Filters")
        case .radius5:
            return NSLocalizedString("5 miles", comment: "Explore Dash: Filters")
        case .radius20:
            return NSLocalizedString("20 miles", comment: "Explore Dash: Filters")
        case .radius50:
            return NSLocalizedString("50 miles", comment: "Explore Dash: Filters")
        case .location:
            return NSLocalizedString("Current location", comment: "Explore Dash: Filters")
        case .locationService:
            return NSLocalizedString("Allowed", comment: "Explore Dash: Filters")
        case .reset:
            return NSLocalizedString("Reset Filters", comment: "Explore Dash: Filters")
        case .sortDistance:
            return NSLocalizedString("Distance", comment: "Explore Dash: Filters")
        }
    }
}

class PointOfUseListFiltersModel {
    
}

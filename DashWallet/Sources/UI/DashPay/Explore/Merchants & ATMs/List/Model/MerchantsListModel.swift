//  
//  Created by Pavel Tikhonenko
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
import CoreLocation

enum MerchantsListSegment: Int {
    case online = 0
    case nearby
    case all
    
    static func ==(lhs: PointOfUseListSegment, rhs: MerchantsListSegment) -> Bool {
        return lhs.tag == rhs.rawValue
    }
    
    var pointOfUseListSegment: PointOfUseListSegment {
        switch self {
        case .online:
            return .init(tag: rawValue, title: title, showMap: false, showLocationServiceSettings: false, showReversedLocation: false)
        case .nearby:
            return .init(tag: rawValue, title: title, showMap: true, showLocationServiceSettings: true, showReversedLocation: true)
        case .all:
            return .init(tag: rawValue, title: title, showMap: true, showLocationServiceSettings: false, showReversedLocation: false)
        }
    }
}

extension MerchantsListSegment {
    var title: String {
        switch self {
        case .online:
            return NSLocalizedString("Online", comment: "Online")
        case .nearby:
            return NSLocalizedString("Nearby", comment: "Nearby")
        case .all:
            return NSLocalizedString("All", comment: "All")
        }
    }
}

class MerchantsListModel: PointOfUseListModel {
    private let onlineMerchantsDataProvider: OnlineMerchantsDataProvider
    private let nearbyMerchantsDataProvider: NearbyMerchantsDataProvider
    private let allMerchantsDataProvider: AllMerchantsDataProvider
    
    override var hasNextPage: Bool {
        return currentDataProvider?.hasNextPage ?? false
    }
    
    override var currentDataProvider: PointOfUseDataProvider? {
        switch currentSegment.tag {
        case MerchantsListSegment.online.rawValue:
            return onlineMerchantsDataProvider
        case MerchantsListSegment.nearby.rawValue:
            return nearbyMerchantsDataProvider
        case MerchantsListSegment.all.rawValue:
            return allMerchantsDataProvider
        default:
            return nil
        }
    }
        
    override init() {
        
        onlineMerchantsDataProvider = OnlineMerchantsDataProvider()
        nearbyMerchantsDataProvider = NearbyMerchantsDataProvider()
        allMerchantsDataProvider = AllMerchantsDataProvider()
        
        super.init()
        
        let newSegments = [MerchantsListSegment.online.pointOfUseListSegment, MerchantsListSegment.nearby.pointOfUseListSegment, MerchantsListSegment.all.pointOfUseListSegment]
        segments = newSegments
        
        
        if DWLocationManager.shared.isAuthorized {
            currentSegment = newSegments[MerchantsListSegment.nearby.rawValue]
        }else{
            currentSegment = newSegments.first!
        }
    }
}


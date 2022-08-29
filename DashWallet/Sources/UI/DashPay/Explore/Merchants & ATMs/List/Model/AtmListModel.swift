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

enum AtmListSegmnets: Int {
    case all = 0
    case buy
    case sell
    case buyAndSell
    
    static func ==(lhs: PointOfUseListSegment, rhs: AtmListSegmnets) -> Bool {
        return lhs.tag == rhs.rawValue
    }
    
    var pointOfUseListSegment: PointOfUseListSegment {
        return .init(tag: self.rawValue, title: title, showMap: true, showLocationServiceSettings: false, showReversedLocation: true)
    }
}

extension AtmListSegmnets {
    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("All", comment: "all")
        case .buy:
            return NSLocalizedString("Buy", comment: "buy")
        case .sell:
            return NSLocalizedString("Sell", comment: "Sell")
        case .buyAndSell:
            return NSLocalizedString("Buy/Sell", comment: "Buy/Sell")
        }
    }
}

class AtmListModel: PointOfUseListModel {
    private let allDataProvider: AllAtmsDataProvider
    private let buyDataProvider: BuyAtmsDataProvider
    private let buySellDataProvider: BuyAndSellAtmsDataProvider
    
    override var hasNextPage: Bool {
        return currentDataProvider?.hasNextPage ?? false
    }
    
    override var currentDataProvider: PointOfUseDataProvider? {
        switch currentSegment.tag {
        case AtmListSegmnets.all.rawValue:
            return allDataProvider
        case AtmListSegmnets.buy.rawValue:
            return buyDataProvider
        case AtmListSegmnets.sell.rawValue:
            return buySellDataProvider
        case AtmListSegmnets.buyAndSell.rawValue:
            return buySellDataProvider
        default:
            return nil
        }
    }
        
    override init() {
        
        allDataProvider = AllAtmsDataProvider()
        buyDataProvider = BuyAtmsDataProvider()
        buySellDataProvider = BuyAndSellAtmsDataProvider()
        
        super.init()
        
        let newSegments = [AtmListSegmnets.all.pointOfUseListSegment, AtmListSegmnets.buy.pointOfUseListSegment, AtmListSegmnets.sell.pointOfUseListSegment, AtmListSegmnets.buyAndSell.pointOfUseListSegment]
        
        segments = newSegments
        currentSegment = newSegments.first!
    }
}


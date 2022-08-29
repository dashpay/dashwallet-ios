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

enum AtmListSegmnets: Int {
    case all = 0
    case buy
    case sell
    case buyAndSell
    
    static func ==(lhs: PointOfUseListSegment, rhs: AtmListSegmnets) -> Bool {
        return lhs.tag == rhs.rawValue
    }
    
    var pointOfUseListSegment: PointOfUseListSegment {
        return .init(tag: self.rawValue, title: title, showMap: true, showLocationServiceSettings: false, showReversedLocation: true, dataProvider: dataProvider)
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
    
    var dataProvider: PointOfUseDataProvider {
        switch self {
        case .all:
            return AllAtmsDataProvider()
        case .buy:
            return BuyAtmsDataProvider()
        case .sell:
            return BuyAndSellAtmsDataProvider()
        case .buyAndSell:
            return BuyAndSellAtmsDataProvider()
        }
    }
}

@objc class AtmListViewController: PointOfUseListViewController {
    override func configureModel() {
        model = PointOfUseListModel(segments: [AtmListSegmnets.all.pointOfUseListSegment, AtmListSegmnets.buy.pointOfUseListSegment, AtmListSegmnets.sell.pointOfUseListSegment, AtmListSegmnets.buyAndSell.pointOfUseListSegment])
    }
    
    override func configureHierarchy() {
        self.title = NSLocalizedString("ATMs", comment: "");
        self.view.backgroundColor = .dw_background()
        
        //let infoButton: UIButton = UIButton(type: .infoLight)
        //infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        //self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: infoButton)
        
        super.configureHierarchy()
    }

}

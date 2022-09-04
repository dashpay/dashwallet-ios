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

class MerchantAllLocationsModel {
    var merchantsDidChange: (([ExplorePointOfUse]) -> Void)?
    
    let merchant: ExplorePointOfUse
    var cachedMerchants: [ExplorePointOfUse] = []
    
    init(merchant: ExplorePointOfUse) {
        self.merchant = merchant
    }
    
    func fetchMerchants(in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?) {
        //TODO: fix it
//        ExploreDash.shared.allLocations(for: merchant, in: bounds, userPoint: userPoint) { [weak self] result in
//            switch result {
//            case .success(let page):
//                self?.cachedMerchants = page.items
//                DispatchQueue.main.async {
//                    self?.merchantsDidChange?(page.items)
//                }
//                break
//            case .failure(let error):
//                break //TODO: handler failure
//            }
//        }
    }
}

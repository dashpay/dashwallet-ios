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
import MapKit

class ExploreDashWhereToSpendModel {
    var cachedOnlineMerchants: [Merchant] = []
    var cachedNearbyMerchants: [Merchant] = []
    var cachedAllMerchants: [Merchant] { return cachedNearbyMerchants + cachedOnlineMerchants }
    
    var onlineSearchResult: [Merchant] = []
    var nearbySearchResult: [Merchant] = []
    
    var cachedOnlineMerchantsDidChange: (() -> Void)?
    var cachedNearbyMerchantsDidChange: (() -> Void)?

    var searchResultDidChange: (() -> Void)?
    
    var lastQuery: String?
    var isFetching: Bool = false
    
    init() {
        preFetchMerchants()
    }
    
    func preFetchMerchants() {
        cachedOnlineMerchants += ExploreDash.shared.allOnlineMerchants().items
    }
    
    func resetSearchResults() {
        onlineSearchResult = []
        nearbySearchResult = []
    }
    
    func fetchMerchants(in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?) {
        ExploreDash.shared.merchants(in: bounds, userPoint: userPoint) { [weak self] result in
            switch result {
            case .success(let page):
                self?.cachedNearbyMerchants = page.items
                break
            case .failure(let error):
                break //TODO: handler failure
            }
            
            DispatchQueue.main.async {
                self?.cachedNearbyMerchantsDidChange?()
            }
        }
    }
}

extension ExploreDashWhereToSpendModel
{
    func merchants(for segment: ExploreWhereToSpendSegment) -> [Merchant] {
        switch segment {
        case .online:
            return cachedOnlineMerchants
        case .nearby:
            return cachedNearbyMerchants
        case .all:
            return cachedAllMerchants
        }
    }
    
    func searchOnline(query: String) {
        onlineSearchResult = ExploreDash.shared.searchOnlineMerchants(query: query).items
        searchResultDidChange?()
    }
    
    func searchMerchants(by query: String, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?) {
        ExploreDash.shared.searchMerchants(by: query, in: bounds, userPoint: userPoint) { [weak self] result in
            switch result {
            case .success(let page):
                self?.nearbySearchResult = page.items
                break
            case .failure(let error):
                break //TODO: handler failure
            }
            
            DispatchQueue.main.async {
                self?.searchResultDidChange?()
            }
        }
    }
}

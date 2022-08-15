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
    var onlineMerchantsDidChange: (() -> Void)?
    
    var cachedOnlineMerchants: [Merchant] = []
    var lastOnlineMerchantsPage: PaginationResult<Merchant>?
    
    var nearbyMerchantsDidChange: (() -> Void)?
    var nearbyLastSearchMerchants: [Merchant] = []
    
    var cachedNearbyMerchants: [Merchant] = []
    var cachedNearbyMerchantsPage: PaginationResult<Merchant>?
    
    var allMerchantsDidChange: (() -> Void)?
    var allMerchantsNextPageFetched: (() -> Void)?
    
    var cachedAllMerchants: [Merchant] = []
    var cachedAllMerchantsSearchMerchants: [Merchant] = []
    var cachedAllMerchantsPage: PaginationResult<Merchant>?
    
    var hasNextPage: Bool {
        guard let page = cachedAllMerchantsPage else { return false }
        return page.items.count == pageLimit
    }
    
    var lastQuery: String?
    
    var isFetching: Bool = false
    
    init() {
        preFetchMerchants()
    }
    
    func preFetchMerchants() {
        lastOnlineMerchantsPage = ExploreDash.shared.allOnlineMerchants()
        cachedOnlineMerchants += lastOnlineMerchantsPage?.items ?? []
        onlineMerchantsDidChange?()
        
        fetchMerchants(query: nil, offset: 0)
    }
    
    func fetchMerchants(query: String?, offset: Int = 0) {
        if (query != lastQuery) {
            cachedAllMerchants = []
            cachedAllMerchantsPage = nil
        }
        
        lastQuery = query
        ExploreDash.shared.merchants(query: lastQuery, userPoint: DWLocationManager.shared.currentLocation?.coordinate, offset: offset) { [weak self] result in
            switch result {
            case .success(let page):
                self?.cachedAllMerchants += page.items
                self?.cachedAllMerchantsPage = page
                break
            case .failure(let error):
                break //TODO: handler failure
            }
            
            self?.isFetching = false
            DispatchQueue.main.async {
                self?.allMerchantsDidChange?()
            }
        }
    }
    
    func fetchNextPage() {
        guard let page = cachedAllMerchantsPage, !isFetching else { return }
        
        isFetching = true
        fetchMerchants(query: lastQuery, offset: page.offset)
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
                self?.nearbyMerchantsDidChange?()
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
    
    func search(query: String, for segment: ExploreWhereToSpendSegment) -> [Merchant] {
        return ExploreDash.shared.searchOnlineMerchants(query: query).items
    }
    
    func searchMerchants(by query: String, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?) {
        ExploreDash.shared.searchMerchants(by: query, in: bounds, userPoint: userPoint) { [weak self] result in
            switch result {
            case .success(let page):
                self?.nearbyLastSearchMerchants = page.items
                break
            case .failure(let error):
                break //TODO: handler failure
            }
            
            DispatchQueue.main.async {
                self?.nearbyMerchantsDidChange?()
            }
        }
    }
    
    func searchMerchants(by query: String, userPoint: CLLocationCoordinate2D?) {
        ExploreDash.shared.merchants(query: query, userPoint: userPoint, offset: 0) { [weak self] result in
            switch result {
            case .success(let page):
                self?.nearbyLastSearchMerchants = page.items
                break
            case .failure(let error):
                break //TODO: handler failure
            }
            
            DispatchQueue.main.async {
                self?.nearbyMerchantsDidChange?()
            }
        }
    }
}

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

class ExploreDashWhereToSpendModel {
    var onlineMerchantsDidChange: (() -> Void)?
    
    var cachedOnlineMerchants: [Merchant] = []
    var lastOnlineMerchantsPage: PaginationResult<Merchant>?
    
    var cachedNearbyMerchants: [Merchant] = []
    var cachedNearbyMerchantsPage: PaginationResult<Merchant>?
    
    var cachedAllMerchants: [Merchant] = []
    var cachedAllMerchantsPage: PaginationResult<Merchant>?
    
    init() {
        fetchMerchants()
    }
    
    func fetchMerchants() {
        lastOnlineMerchantsPage = ExploreDash.shared.allOnlineMerchants()
        cachedOnlineMerchants += lastOnlineMerchantsPage?.items ?? []
        
        onlineMerchantsDidChange?()
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
}

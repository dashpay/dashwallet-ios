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

class MerchantsDataProvider {
    var items: [Merchant] = []
    var currentPage: PaginationResult<Merchant>?
    var hasNextPage: Bool {
        //TODO: get total amount first
        return !items.isEmpty && currentPage?.items.count == pageLimit
    }
    
    internal let dataSource: MerchantDAO
    
    //To support paging we need to keep query and last user point
    internal var lastQuery: String?
    internal var lastUserPoint: CLLocationCoordinate2D?
    
    init(dataSource: MerchantDAO) {
        self.dataSource = dataSource
    }
    
    func nextPage(completion: @escaping (Swift.Result<[Merchant], Error>) -> Void) {
        //NOTE: must be overriden 
    }
}

class AllMerchantsDataProvider: NearbyMerchantsDataProvider {
    override func fetch(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        dataSource.allMerchants(by: query, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
}

class NearbyMerchantsDataProvider: MerchantsDataProvider {
    internal var lastBounds: ExploreMapBounds!
    
    func merchants(query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[Merchant], Error>) -> Void) {
        
        if lastBounds == bounds && lastQuery == query && !items.isEmpty {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userPoint
        lastBounds = bounds
        
        fetch(by: query, in: bounds, userPoint: userPoint, offset: 0) { [weak self] result in
            switch result {
            case .success(let page):
                self?.currentPage = page
                self?.items = page.items
                completion(.success(page.items))
                break
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[Merchant], Error>) -> Void) {
        let offset: Int
        
        if let pageOffset = currentPage?.offset {
            offset = pageOffset + pageLimit
        }else{
            offset = 0
        }
        
        fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint, offset: offset) { [weak self] result in
            switch result {
            case .success(let page):
                self?.currentPage = page
                self?.items += page.items
                completion(.success(page.items))
                break
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    internal func fetch(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        dataSource.nearbyMerchants(by: query, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
}

class OnlineMerchantsDataProvider: MerchantsDataProvider {
    func merchants(query: String?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[Merchant], Error>) -> Void) {
        if lastQuery == query && !items.isEmpty {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userPoint
        
        fetch(by: query, onlineOnly: false, userPoint: userPoint, offset: 0) { [weak self] result in
            switch result {
            case .success(let page):
                self?.currentPage = page
                self?.items = page.items
                completion(.success(page.items))
                break
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[Merchant], Error>) -> Void) {
        let offset: Int
        
        if let pageOffset = currentPage?.offset {
            offset = pageOffset + pageLimit
        }else{
            offset = 0
        }
        
        fetch(by: lastQuery, onlineOnly: false, userPoint: lastUserPoint, offset: offset) { [weak self] result in
            switch result {
            case .success(let page):
                self?.currentPage = page
                self?.items += page.items
                completion(.success(page.items))
                break
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func fetch(by query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        dataSource.onlineMerchants(query: query, onlineOnly: false, userPoint: userPoint, offset: offset, completion: completion)
    }
}

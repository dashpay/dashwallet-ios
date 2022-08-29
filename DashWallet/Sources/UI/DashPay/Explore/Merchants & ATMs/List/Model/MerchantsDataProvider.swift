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

//protocol PointOfUseDataProvider {
//    func merchants(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[Merchant], Error>) -> Void) {
//        //NOTE: must be overriden
//    }
//}
class MerchantsDataProvider {
    var items: [ExplorePointOfUse] = []
    var currentPage: PaginationResult<ExplorePointOfUse>?
    var hasNextPage: Bool {
        //TODO: get total amount first
        return !items.isEmpty && currentPage?.items.count == pageLimit
    }
    
    
    var nextOffset: Int {
        let offset: Int
        
        if let pageOffset = currentPage?.offset {
            offset = pageOffset + pageLimit
        }else{
            offset = 0
        }
        
        return offset
    }
    
    internal let dataSource: ExploreDash
    
    //To support paging we need to keep query and last user point
    internal var lastQuery: String?
    internal var lastUserPoint: CLLocationCoordinate2D?
    
    init() {
        self.dataSource = ExploreDash.shared
    }
    
    func merchants(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        //NOTE: must be overriden
    }
    
    
    func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        //NOTE: must be overriden 
    }
    
    internal func handle(result: Swift.Result<PaginationResult<ExplorePointOfUse>, Error>, appending: Bool = false, completion: (Result<[ExplorePointOfUse], Error>) -> Void) {
        switch result {
        case .success(let page):
            currentPage = page
            
            if appending {
                items += page.items
            }else{
                items = page.items
            }
            
            completion(.success(page.items))
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

class AllMerchantsDataProvider: NearbyMerchantsDataProvider {
    override func merchants(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        
        if DWLocationManager.shared.isPermissionDenied {
            fetch(by: query, offset: 0) { [weak self] result in
                self?.handle(result: result, completion: completion)
            }
        }else if let bounds = bounds {
            super.merchants(query: query, in: bounds, userPoint: userPoint, completion: completion)
        }else{
            items = []
            currentPage = nil
            completion(.success(items))
        }
    }
    
    override func nextPage(completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        if DWLocationManager.shared.isPermissionDenied {
            
            fetch(by: lastQuery, offset: nextOffset) { [weak self] result in
                self?.handle(result: result, completion: completion)
                
            }
        }else{
            super.nextPage(completion: completion)
        }
    }
    
    func fetch(by query: String?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.allMerchants(by: query, offset: offset, completion: completion)
    }
    
    override func fetch(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.allMerchants(by: query, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
}

class NearbyMerchantsDataProvider: MerchantsDataProvider {
    internal var lastBounds: ExploreMapBounds!
    
    override func merchants(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        
        guard let bounds = bounds, let userLocation = userPoint, DWLocationManager.shared.isAuthorized else {
            items = []
            currentPage = nil
            completion(.success(items))
            return
        }
        
        if lastBounds == bounds && lastQuery == query && !items.isEmpty {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userPoint
        lastBounds = bounds
        
        fetch(by: query, in: bounds, userPoint: userLocation, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }
    
    internal func fetch(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.nearbyMerchants(by: query, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
}

class OnlineMerchantsDataProvider: MerchantsDataProvider {
    override func merchants(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        if lastQuery == query && !items.isEmpty {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userPoint
        
        fetch(by: query, onlineOnly: false, userPoint: userPoint, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, onlineOnly: false, userPoint: lastUserPoint, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }
    
    private func fetch(by query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.onlineMerchants(query: query, onlineOnly: false, userPoint: userPoint, offset: offset, completion: completion)
    }
}

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

class AllMerchantsDataProvider: NearbyMerchantsDataProvider {
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        
        if DWLocationManager.shared.isPermissionDenied || DWLocationManager.shared.needsAuthorization {
            fetch(by: query, in: nil, userPoint: nil, with: filters, offset: 0) { [weak self] result in
                self?.handle(result: result, completion: completion)
            }
        }else if let bounds = bounds {
            fetch(by: query, in: bounds, userPoint: userPoint, with: filters, offset: 0) { [weak self] result in
                self?.handle(result: result, completion: completion)
            }
            
        }else{
            items = []
            currentPage = nil
            completion(.success(items))
        }
    }
    
    override func nextPage(completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        if DWLocationManager.shared.isPermissionDenied {

            fetch(by: lastQuery, in: nil, userPoint: nil, with: lastFilters, offset: nextOffset) { [weak self] result in
                self?.handle(result: result, completion: completion)
            }
        }else{
            super.nextPage(completion: completion)
        }
    }
        
    override func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.allMerchants(by: query, in: bounds, userPoint: userPoint, paymentMethods: filters?.merchantPaymentTypes, sortBy: filters?.sortBy, territory: filters?.territory, offset: offset, completion: completion)
    }
}

class NearbyMerchantsDataProvider: PointOfUseDataProvider {
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        
        guard let bounds = bounds, let userLocation = userPoint, DWLocationManager.shared.isAuthorized else {
            items = []
            currentPage = nil
            completion(.success(items))
            return
        }
        
        if lastBounds == bounds && lastQuery == query && !items.isEmpty && lastFilters == filters {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userPoint
        lastBounds = bounds
        lastFilters = filters
        
        fetch(by: query, in: bounds, userPoint: userLocation, with: filters, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, in: lastBounds!, userPoint: lastUserPoint, with: lastFilters, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }
    
    internal func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.nearbyMerchants(by: query, in: bounds, userPoint: userPoint, paymentMethods: filters?.merchantPaymentTypes, sortBy: filters?.sortBy, territory: filters?.territory, offset: offset, completion: completion)
    }
}

class OnlineMerchantsDataProvider: PointOfUseDataProvider {
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        if lastQuery == query && !items.isEmpty && lastFilters == filters {
            completion(.success(items))
            return
        }
        
        lastQuery = query
        lastUserPoint = userPoint
        lastFilters = filters
        
        fetch(by: query, onlineOnly: false, userPoint: userPoint, with: filters, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }
    
    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, onlineOnly: false, userPoint: lastUserPoint, with: lastFilters, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }
    
    private func fetch(by query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, offset: Int, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.onlineMerchants(query: query, onlineOnly: false, paymentMethods: filters?.merchantPaymentTypes, userPoint: userPoint, offset: offset, completion: completion)
    }
}

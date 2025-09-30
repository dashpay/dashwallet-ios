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

import CoreLocation
import Foundation

// MARK: - AllMerchantsDataProvider

class AllMerchantsDataProvider: NearbyMerchantsDataProvider {
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        lastQuery = query
        lastUserPoint = userPoint
        lastBounds = bounds
        lastFilters = filters

        // ALL TAB: Never filter by bounds or location - show ALL merchants regardless of location
        // Don't pass userPoint to avoid the in-memory grouping path (which filters out online merchants)
        fetch(by: query, in: nil, userPoint: nil, with: filters, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }

    override func nextPage(completion: @escaping (Result<[ExplorePointOfUse], Error>) -> Void) {
        // ALL TAB: Never filter by bounds or location - show ALL merchants
        // Don't pass userPoint to avoid the in-memory grouping path
        fetch(by: lastQuery, in: nil, userPoint: nil, with: lastFilters, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }

    override func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?, offset: Int,
                        completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.allMerchants(by: query, in: bounds, userPoint: userPoint, paymentMethods: filters?.merchantPaymentTypes,
                                sortBy: filters?.sortBy, territory: filters?.territory, denominationType: filters?.denominationType,
                                offset: offset) { result in
            completion(result)
        }
    }
}

// MARK: - NearbyMerchantsDataProvider

class NearbyMerchantsDataProvider: PointOfUseDataProvider {
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        guard let bounds, let userLocation = userPoint, DWLocationManager.shared.isAuthorized else {
            print("🔍 NEARBY: No bounds/location/auth - returning empty")
            items = []
            currentPage = nil
            completion(.success(items))
            return
        }

        print("🔍 NEARBY: Checking cache...")
        print("🔍 NEARBY: lastBounds == bounds? \(String(describing: lastBounds == bounds))")
        print("🔍 NEARBY: lastQuery == query? \(lastQuery == query)")
        print("🔍 NEARBY: !items.isEmpty? \(!items.isEmpty)")
        print("🔍 NEARBY: lastFilters == filters? \(String(describing: lastFilters == filters))")

        if lastBounds == bounds && lastQuery == query && !items.isEmpty && lastFilters == filters {
            print("🔍 NEARBY: Cache hit - returning \(items.count) cached items")
            completion(.success(items))
            return
        }

        print("🔍 NEARBY: Cache miss - fetching new data")
        print("🔍 NEARBY: Bounds - NE=(\(bounds.neCoordinate.latitude), \(bounds.neCoordinate.longitude)), SW=(\(bounds.swCoordinate.latitude), \(bounds.swCoordinate.longitude))")
        print("🔍 NEARBY: User location = \(userLocation.latitude), \(userLocation.longitude)")
        lastQuery = query
        lastUserPoint = userPoint
        lastBounds = bounds
        lastFilters = filters

        fetch(by: query, in: bounds, userPoint: userLocation, with: filters, offset: 0) { [weak self] result in
            switch result {
            case .success(let page):
                print("🔍 NEARBY: Fetch succeeded - got \(page.items.count) items")
                if let firstItem = page.items.first {
                    print("🔍 NEARBY: First merchant: \(firstItem.name)")
                }
            case .failure(let error):
                print("🔍 NEARBY: Fetch failed - \(error)")
            }
            self?.handle(result: result, completion: completion)
        }
    }

    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, in: lastBounds!, userPoint: lastUserPoint, with: lastFilters,
              offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }

    internal func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?, offset: Int,
                        completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.nearbyMerchants(by: query, in: bounds, userPoint: userPoint, paymentMethods: filters?.merchantPaymentTypes, sortBy: filters?.sortBy, territory: filters?.territory, denominationType: filters?.denominationType, offset: offset) { result in
            completion(result)
        }
    }
}

// MARK: - OnlineMerchantsDataProvider

class OnlineMerchantsDataProvider: PointOfUseDataProvider {
    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        if lastQuery == query && !items.isEmpty && lastFilters == filters {
            completion(.success(items))
            return
        }

        lastQuery = query
        lastUserPoint = userPoint
        lastFilters = filters

        fetch(by: query, onlineOnly: true, userPoint: userPoint, with: filters, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }

    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, onlineOnly: true, userPoint: lastUserPoint, with: lastFilters,
              offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }

    private func fetch(by query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?,
                       with filters: PointOfUseListFilters?, offset: Int,
                       completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.onlineMerchants(query: query, onlineOnly: onlineOnly, paymentMethods: filters?.merchantPaymentTypes,
                                   sortBy: filters?.sortBy, userPoint: userPoint, denominationType: filters?.denominationType, offset: offset) { result in
            completion(result)
        }
    }
}

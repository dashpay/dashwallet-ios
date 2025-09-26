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

class AllMerchantLocationsDataProvider: PointOfUseDataProvider {
    private let pointOfUse: ExplorePointOfUse

    init(pointOfUse: ExplorePointOfUse) {
        self.pointOfUse = pointOfUse
        super.init()
    }

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: CALLED")
        print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: bounds=\(String(describing: bounds))")
        print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: userPoint=\(String(describing: userPoint))")
        print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: filters.radius=\(String(describing: filters?.radius))")
        print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: needsAuth=\(DWLocationManager.shared.needsAuthorization), isAuth=\(DWLocationManager.shared.isAuthorized), isPermissionDenied=\(DWLocationManager.shared.isPermissionDenied)")

        var bounds = bounds
        var userPoint = userPoint

        // Special handling for infinite radius (All tab showing all locations)
        // When filters.radius is nil AND bounds is nil, treat as "show all locations" request
        let isShowAllLocationsRequest = bounds == nil && filters?.radius == nil
        print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: isShowAllLocationsRequest=\(isShowAllLocationsRequest)")

        if isShowAllLocationsRequest {
            print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: Show all locations mode - setting bounds to nil")
            bounds = nil
            // Keep userPoint for distance sorting if filters require it
            if filters?.sortBy == .distance {
                print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: Keeping userPoint for distance sorting")
            } else {
                print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: Setting userPoint to nil (no distance sorting)")
                userPoint = nil
            }
        } else {
            // Original logic for other cases
            let allowNilBounds = bounds == nil && userPoint == nil
            print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: allowNilBounds=\(allowNilBounds)")

            if DWLocationManager.shared.needsAuthorization || (DWLocationManager.shared.isAuthorized && !allowNilBounds && (bounds == nil || userPoint == nil)) {
                print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: RETURNING EMPTY - authorization or bounds issue")
                items = []
                currentPage = nil
                completion(.success(items))
                return
            } else if DWLocationManager.shared.isPermissionDenied {
                print("🔍🔍🔍 AllMerchantLocationsDataProvider.items: Permission denied, setting bounds/userPoint to nil")
                bounds = nil
                userPoint = nil
            }
        }

        if lastQuery == query && !items.isEmpty && lastBounds == bounds && lastFilters == filters {
            completion(.success(items))
            return
        }

        lastQuery = query
        lastUserPoint = userPoint
        lastBounds = bounds
        lastFilters = filters

        fetch(by: query, in: bounds, userPoint: userPoint, with: filters, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }

    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint, with: lastFilters, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }

    private func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, offset: Int,
                       completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        print("🔍 AllMerchantLocationsDataProvider.fetch: for merchant \(pointOfUse.name)")
        print("🔍 AllMerchantLocationsDataProvider.fetch: bounds=\(String(describing: bounds))")
        print("🔍 AllMerchantLocationsDataProvider.fetch: userPoint=\(String(describing: userPoint))")
        print("🔍 AllMerchantLocationsDataProvider.fetch: filters.radius=\(String(describing: filters?.radius))")

        dataSource.allLocations(for: pointOfUse.pointOfUseId, in: bounds, userPoint: userPoint) { result in
            switch result {
            case .success(let locations):
                print("🔍 AllMerchantLocationsDataProvider.fetch: Found \(locations.items.count) locations")
            case .failure(let error):
                print("🔍 AllMerchantLocationsDataProvider.fetch: Error - \(error)")
            }
            completion(result)
        }
    }
}

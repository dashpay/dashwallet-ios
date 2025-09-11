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
import MapKit

class AllMerchantLocationsDataProvider: PointOfUseDataProvider {
    private let pointOfUse: ExplorePointOfUse
    private let currentFilters: PointOfUseListFilters?
    private let currentMapBounds: ExploreMapBounds?

    init(pointOfUse: ExplorePointOfUse, currentFilters: PointOfUseListFilters? = nil, currentMapBounds: ExploreMapBounds? = nil) {
        self.pointOfUse = pointOfUse
        self.currentFilters = currentFilters
        self.currentMapBounds = currentMapBounds
        super.init()
    }

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        var finalBounds = bounds
        var finalUserPoint = userPoint

        // Use currentFilters if available, otherwise fall back to provided filters
        let filtersToUse = currentFilters ?? filters

        if DWLocationManager.shared.isPermissionDenied || DWLocationManager.shared.needsAuthorization {
            // When location is denied/not authorized, show all locations globally (no bounds filter)
            finalBounds = nil
            finalUserPoint = nil
        } else if let mapBounds = currentMapBounds {
            // Use the current visible map bounds (when user has zoomed/panned the map)
            finalBounds = mapBounds
            finalUserPoint = DWLocationManager.shared.currentLocation?.coordinate
        } else if DWLocationManager.shared.isAuthorized, let userLocation = DWLocationManager.shared.currentLocation {
            // Fall back to filter radius approach when no map bounds available
            finalUserPoint = userLocation.coordinate

            if let filtersToUse = filtersToUse {
                let radiusInMeters = filtersToUse.currentRadius
                let circle = MKCircle(center: userLocation.coordinate, radius: radiusInMeters)
                let rect = circle.boundingMapRect
                finalBounds = ExploreMapBounds(rect: rect)
            }
        } else {
            // Location is authorized but current location not available yet, show all globally
            finalBounds = nil
            finalUserPoint = nil
        }

        if lastQuery == query && !items.isEmpty && lastBounds == finalBounds {
            completion(.success(items))
            return
        }

        lastQuery = query
        lastUserPoint = finalUserPoint
        lastBounds = finalBounds

        fetch(by: query, in: finalBounds, userPoint: finalUserPoint, offset: 0) { [weak self] result in
            self?.handle(result: result, completion: completion)
        }
    }

    override func nextPage(completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint, offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }

    private func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, offset: Int,
                       completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.allLocations(for: pointOfUse.pointOfUseId, in: bounds, userPoint: userPoint) { result in
            switch result {
            case .success(let paginationResult):
                // Filter for active locations only to match the count shown in details view
                let activeLocations = paginationResult.items.filter { $0.active }
                let filteredResult = PaginationResult(items: activeLocations, offset: paginationResult.offset)
                completion(.success(filteredResult))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

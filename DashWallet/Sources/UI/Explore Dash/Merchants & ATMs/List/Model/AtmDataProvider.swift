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

// MARK: - BaseAtmsDataProvider

class BaseAtmsDataProvider: PointOfUseDataProvider {
    var types: [ExplorePointOfUse.Atm.`Type`]? { nil }

    override func items(query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                        with filters: PointOfUseListFilters?,
                        completion: @escaping (Swift.Result<[ExplorePointOfUse], Error>) -> Void) {
        var bounds = bounds
        var userPoint = userPoint

        if DWLocationManager.shared
            .needsAuthorization || (DWLocationManager.shared.isAuthorized && (bounds == nil || userPoint == nil)) {
            items = []
            currentPage = nil
            completion(.success(items))
            return
        } else if DWLocationManager.shared.isPermissionDenied {
            bounds = nil
            userPoint = nil
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
        fetch(by: lastQuery, in: lastBounds, userPoint: lastUserPoint, with: lastFilters,
              offset: nextOffset) { [weak self] result in
            self?.handle(result: result, appending: true, completion: completion)
        }
    }

    private func fetch(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?,
                       with filters: PointOfUseListFilters?, offset: Int,
                       completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        dataSource.atms(query: query, in: types, in: bounds, userPoint: userPoint, with: filters, offset: offset,
                        completion: completion)
    }
}

// MARK: - AllAtmsDataProvider

class AllAtmsDataProvider: BaseAtmsDataProvider { }

// MARK: - BuyAtmsDataProvider

class BuyAtmsDataProvider: BaseAtmsDataProvider {
    override var types: [ExplorePointOfUse.Atm.`Type`] { [.buy] }
}

// MARK: - BuyAndSellAtmsDataProvider

class BuyAndSellAtmsDataProvider: BaseAtmsDataProvider {
    override var types: [ExplorePointOfUse.Atm.`Type`] { [.buySell] }
}



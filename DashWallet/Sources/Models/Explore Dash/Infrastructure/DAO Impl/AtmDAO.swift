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
import SQLite

class AtmDAO: PointOfUseDAO {
    typealias Item = ExplorePointOfUse

    private let connection: ExploreDatabaseConnection
    private var cachedTerritories: [Territory] = []

    let serialQueue = DispatchQueue(label: "explore.db.serial.queue.atms")

    init(dbConnection: ExploreDatabaseConnection) {
        connection = dbConnection
    }

    func items(filters: PointOfUseDAOFilters, offset: Int?,
               completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }

            let atmTable = Table("atm")
            let name = ExplorePointOfUse.name
            let territoryColumn = ExplorePointOfUse.territory
            let type = ExplorePointOfUse.type
            let latitude = Expression<Float64>("latitude")
            let longitude = Expression<Float64>("longitude")
            let manufacturer = Expression<String>("manufacturer")
            let offset = offset ?? 0
            var queryFilter = Expression<Bool>(value: true)

            if let query = filters[.query] as? String {
                queryFilter = queryFilter && (name.like("\(query)%") || manufacturer.like("\(query)%"))
            }

            if let types = filters[.types] as? [ExplorePointOfUse.Atm.`Type`] {
                queryFilter = queryFilter && types.map { $0.rawValue }.contains(type)
            }

            if let territory = filters[.territory] as? String {
                queryFilter = queryFilter && territoryColumn.like(territory)
            } else if let bounds = filters[.bounds] as? ExploreMapBounds {
                queryFilter = queryFilter &&
                    (latitude > bounds.swCoordinate.latitude && latitude < bounds.neCoordinate.latitude && longitude > bounds
                        .swCoordinate.longitude && longitude < bounds.neCoordinate.longitude)
            }

            var query = atmTable.select(atmTable[*])
                .filter(queryFilter)


            if let sortDirection = filters[.sortDirection] as? PointOfUseListFilters.SortDirection {
                query = query.order(sortDirection == .ascending ? name.collate(.nocase).asc : name.collate(.nocase).desc)
            } else if let userLocation = filters[.userLocation] as? CLLocationCoordinate2D {
                let anchorLatitude = userLocation.latitude
                let anchorLongitude = userLocation.longitude

                query = query.order([
                    Expression<Bool>(literal: "ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC"),
                    name.collate(.nocase).asc,
                ])
            } else {
                query = query.order(name.asc)
            }

            query = query.limit(pageLimit, offset: offset)

            do {
                let items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: offset)))
            } catch {
                print(error)
                completion(.failure(error))
            }
        }
    }

    func territories(completion: @escaping (Swift.Result<[Territory], Error>) -> Void) {
        if !cachedTerritories.isEmpty {
            completion(.success(cachedTerritories))
            return
        }

        let query = "SELECT DISTINCT territory from atm WHERE territory != '' ORDER BY territory"

        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            do {
                let items: [Territory] = try wSelf.connection.execute(query: query)
                self?.cachedTerritories = items
                completion(.success(items))
            } catch {
                print(error)
                completion(.failure(error))
            }
        }
    }
}

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
import SQLite
import CoreLocation

class AtmDAO: PointOfUseDAO {
    typealias Item = ExplorePointOfUse
    
    private let connection: ExploreDatabaseConnection
    
    let serialQueue = DispatchQueue(label: "explore.db.serial.queue.atms")
    
    init(dbConnection: ExploreDatabaseConnection) {
        self.connection = dbConnection
    }
    
    func items(filters: PointOfUseDAOFilters, completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            let atmTable = Table("atm")
            let name = ExplorePointOfUse.name
            let type = ExplorePointOfUse.type
            let latitude = Expression<Float64>("latitude")
            let longitude = Expression<Float64>("longitude")
            let manufacturer = Expression<String>("manufacturer")
            let source = ExplorePointOfUse.source
            
            var queryFilter = Expression<Bool>(value: true)
            
            if let query = filters.query as? String {
                queryFilter = queryFilter && (name.like("\(query)%") || manufacturer.like("\(query)%"))
            }
            
            if let types = filters.types as? [ExplorePointOfUse.Atm.`Type`] {
                queryFilter = queryFilter && types.map({ $0.rawValue }).contains(type)
            }
            
            if let bounds = filters.bounds as? ExploreMapBounds {
                queryFilter = queryFilter && (latitude > bounds.swCoordinate.latitude && latitude < bounds.neCoordinate.latitude && longitude > bounds.swCoordinate.longitude && longitude < bounds.neCoordinate.longitude)
            }
            
            var query = atmTable.select(atmTable[*])
                .filter(queryFilter)
            
//            if let bounds = filters.bounds as? ExploreMapBounds, let userLocation = filters.userLocation as? CLLocationCoordinate2D {
//
//                let anchorLatitude = userLocation.latitude
//                let anchorLongitude = userLocation.longitude
//
//                let exp = Expression<Bool>(literal: "(latitude - \(anchorLatitude))*(latitude - \(anchorLatitude)) + (longitude - \(anchorLongitude))*(longitude - \(anchorLongitude)) = MIN((latitude - \(anchorLatitude))*(latitude - \(anchorLatitude)) + (longitude - \(anchorLongitude))*(longitude - \(anchorLongitude)))")
//
//                query = query.group([manufacturer, source], having: exp)
//            } else {
//                query = query.group([manufacturer, source])
//            }
            

            if let userLocation = filters.userLocation as? CLLocationCoordinate2D {
                
                let anchorLatitude = userLocation.latitude
                let anchorLongitude = userLocation.longitude
                
                query = query.order([Expression<Bool>(literal: "ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC"), name.collate(.nocase), name.asc])
            } else {
                query = query.order(name.asc)
            }
                
            query = query.limit(pageLimit, offset: filters.offset as! Int)
            
            do {
                let items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: filters.offset as! Int)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
        
    }
}

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

class MerchantDAO: PointOfUseDAO
{
    typealias Item = ExplorePointOfUse
    
    private let connection: ExploreDatabaseConnection
    
    let serialQueue = DispatchQueue(label: "org.dashfoundation.dashpaytnt.explore.serial.queue")
    
    private var cachedTerritories: [Territory] = []
    
    init(dbConnection: ExploreDatabaseConnection) {
        self.connection = dbConnection
    }
    
    func items(filters: PointOfUseDAOFilters, offset: Int?, completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void) {
        
    }
    
    //TODO: Refactor: Use a data struct for filters and sorting
    func items(query: String?,
               bounds: ExploreMapBounds?,
               userLocation: CLLocationCoordinate2D?,
               types: [ExplorePointOfUse.Merchant.`Type`],
               paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?,
               sortBy: PointOfUseListFilters.SortBy?,
               territory: Territory?,
               offset: Int,
               completion: @escaping (Swift.Result<PaginationResult<Item>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            let merchantTable = Table("merchant")
            let name = ExplorePointOfUse.name
            let typeColumn = ExplorePointOfUse.type
            let paymentMethodColumn = ExplorePointOfUse.paymentMethod
            let territoryColumn = ExplorePointOfUse.territory
            
            var queryFilter = Expression<Bool>(value: true)
            
            // Add query
            if let query = query {
                queryFilter = queryFilter && name.like("\(query)%")
            }

            queryFilter = queryFilter && types.map({ $0.rawValue }).contains(typeColumn) // Add types
            
            // Add payment methods
            if let methods = paymentMethods {
                queryFilter = queryFilter && methods.map({ $0.rawValue }).contains(paymentMethodColumn)
            }
            
            // Add payment methods or bounds
            if let territory = territory {
                queryFilter = queryFilter && territoryColumn.like(territory)
            }else if let bounds = bounds {
                var boundsFilter = Expression<Bool>(literal: "latitude > \(bounds.swCoordinate.latitude)") &&
                                   Expression<Bool>(literal: "latitude < \(bounds.neCoordinate.latitude)") &&
                                   Expression<Bool>(literal: "longitude > \(bounds.swCoordinate.longitude)") &&
                                   Expression<Bool>(literal: "longitude < \(bounds.neCoordinate.longitude)")
                
                if types.contains(.online) {
                    boundsFilter = boundsFilter || Expression<Bool>(literal: "type = online")
                }
                
                queryFilter = queryFilter && boundsFilter
            }
            
            var query = merchantTable
                .select(merchantTable[*])
                .filter(queryFilter)
            
            if let anchorLatitude = userLocation?.latitude, let anchorLongitude = userLocation?.longitude {
                
                let exp = Expression<Bool>(literal: "(latitude - \(anchorLatitude))*(latitude - \(anchorLatitude)) + (longitude - \(anchorLongitude))*(longitude - \(anchorLongitude)) = MIN((latitude - \(anchorLatitude))*(latitude - \(anchorLatitude)) + (longitude - \(anchorLongitude))*(longitude - \(anchorLongitude)))")
                
                query = query.group([ExplorePointOfUse.source, ExplorePointOfUse.merchantId], having: exp)
            }else{
                query = query.group([ExplorePointOfUse.source, ExplorePointOfUse.merchantId])
            }
            
            var distanceSorting = Expression<Bool>(value: true)
            
            if let userLocation = userLocation {
                
                let anchorLatitude = userLocation.latitude
                let anchorLongitude = userLocation.longitude
                
                distanceSorting = Expression<Bool>(literal: "ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC")
            }
            
            if let sortBy = sortBy, sortBy == .name {
                query = query.order(name.asc)
            }else if userLocation != nil {
                query = query.order([distanceSorting, name.collate(.nocase), name.asc])
            }else{
                var typeOrdering = Expression<Void>(literal:"")
                if bounds == nil && types.count == 3 {
                    typeOrdering = Expression<Void>(literal: """
                        CASE
                            WHEN type = 'online' THEN 1
                            WHEN type = 'physical' THEN 3
                            WHEN type = 'both' THEN 2
                        END
                        """)
                }
                    
                query = query.order([typeOrdering, name.asc])
            }
            
            query = query.limit(pageLimit, offset: offset)
            
            do {
                let items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: offset)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
}

extension MerchantDAO {
    func onlineMerchants(query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        items(query: query, bounds: nil, userLocation: userPoint, types: [.online, .onlineAndPhysical], paymentMethods: paymentMethods, sortBy: nil, territory: nil, offset: offset, completion: completion)
    }
    
    func nearbyMerchants(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?, sortBy: PointOfUseListFilters.SortBy?, territory: Territory?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        items(query: query, bounds: bounds, userLocation: userPoint, types: [.physical, .onlineAndPhysical], paymentMethods: paymentMethods, sortBy: sortBy, territory: territory, offset: offset, completion: completion)
    }
    
    func allMerchants(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?, sortBy: PointOfUseListFilters.SortBy?, territory: Territory?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        items(query: query, bounds: bounds, userLocation: userPoint, types: [.online, .onlineAndPhysical, .physical], paymentMethods: paymentMethods, sortBy: sortBy, territory: territory, offset: offset, completion: completion)
    }
    
    func allLocations(for merchantId: Int64, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            let anchorLatitude = userPoint?.latitude ?? bounds.center.latitude
            let anchorLongitude = userPoint?.longitude ?? bounds.center.longitude
            
            let query = """
                SELECT *
                FROM merchant
                WHERE type IN ('physical', 'both')
                    AND merchantId = \(merchantId)
                    AND latitude > \(bounds.swCoordinate.latitude)
                    AND latitude < \(bounds.neCoordinate.latitude)
                    AND longitude < \(bounds.neCoordinate.longitude)
                    AND longitude > \(bounds.swCoordinate.longitude)
                ORDER BY ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC
            """
            do {
                let items: [ExplorePointOfUse] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: Int.max)))
            }catch{
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
        
        let query = "SELECT DISTINCT territory from merchant WHERE territory != '' ORDER BY territory"
        
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            do {
                let items: [Territory] = try wSelf.connection.execute(query: query)
                self?.cachedTerritories = items
                completion(.success(items))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
}



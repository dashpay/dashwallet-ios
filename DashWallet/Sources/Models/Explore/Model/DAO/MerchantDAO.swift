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

let pageLimit = 100

extension MerchantDAO {
    func onlineMerchants(query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            let anchorLatitude = userPoint?.latitude
            let anchorLongitude = userPoint?.longitude
            
            var whereQuery = query != nil ? "WHERE name LIKE '\(query!)%'" : ""
            whereQuery += "\(whereQuery.isEmpty ? "WHERE" : "AND") type \(onlineOnly ? "= online" : "in ('both', 'online')")"
            
            let query = """
                SELECT *
                FROM merchant
                \(whereQuery)
                GROUP BY source, merchantId
                \(anchorLatitude != nil ? "HAVING (latitude - \(anchorLatitude!))*(latitude - \(anchorLatitude!)) + (longitude - \(anchorLongitude!))*(longitude - \(anchorLongitude!)) = MIN((latitude - \(anchorLatitude!))*(latitude - \(anchorLatitude!)) + (longitude - \(anchorLongitude!))*(longitude - \(anchorLongitude!)))" : "")
                ORDER BY
                    name 
                LIMIT \(pageLimit)
                OFFSET \(offset)
                """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: offset)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func nearbyMerchants(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            
            
            let anchorLatitude = userPoint?.latitude// ?? bounds.center.latitude
            let anchorLongitude = userPoint?.longitude// ?? bounds.center.longitude
            
            let query = """
                SELECT *
                FROM merchant
                WHERE type IN ('physical', 'both')
                    \(query != nil ? "AND name LIKE '\(query!)%'" : "")
                    AND latitude > \(bounds.swCoordinate.latitude)
                    AND latitude < \(bounds.neCoordinate.latitude)
                    AND longitude < \(bounds.neCoordinate.longitude)
                    AND longitude > \(bounds.swCoordinate.longitude)
                GROUP BY source, merchantId
                \(anchorLatitude != nil ? "HAVING (latitude - \(anchorLatitude!))*(latitude - \(anchorLatitude!)) + (longitude - \(anchorLongitude!))*(longitude - \(anchorLongitude!)) = MIN((latitude - \(anchorLatitude!))*(latitude - \(anchorLatitude!)) + (longitude - \(anchorLongitude!))*(longitude - \(anchorLongitude!)))" : "")
                ORDER BY ABS(latitude-\(anchorLatitude!)) + ABS(longitude - \(anchorLongitude!)) ASC
                LIMIT \(pageLimit)
                OFFSET \(offset)
            """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: 0 + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func allMerchants(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            var whereQuery = query != nil ? "WHERE name LIKE '\(query!)%'" : ""
            whereQuery += """
                    \(whereQuery.isEmpty ? "WHERE" : " AND") (latitude > \(bounds.swCoordinate.latitude)
                    AND latitude < \(bounds.neCoordinate.latitude)
                    AND longitude < \(bounds.neCoordinate.longitude)
                    AND longitude > \(bounds.swCoordinate.longitude))
                    OR type = "online" \(query != nil ? " AND name LIKE '\(query!)%'" : "")
            """
            let anchorLatitude = userPoint?.latitude// ?? bounds.center.latitude
            let anchorLongitude = userPoint?.longitude// ?? bounds.center.longitude
            
            let query = """
                SELECT *
                FROM merchant
                \(whereQuery)
                GROUP BY source, merchantId
                \(anchorLatitude != nil ? "HAVING (latitude - \(anchorLatitude!))*(latitude - \(anchorLatitude!)) + (longitude - \(anchorLongitude!))*(longitude - \(anchorLongitude!)) = MIN((latitude - \(anchorLatitude!))*(latitude - \(anchorLatitude!)) + (longitude - \(anchorLongitude!))*(longitude - \(anchorLongitude!)))" : "")
                ORDER BY ABS(latitude-\(anchorLatitude!)) + ABS(longitude - \(anchorLongitude!)) ASC,
                name COLLATE NOCASE ASC
                LIMIT \(pageLimit)
                OFFSET \(offset)
            """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: 0 + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
}
class MerchantDAO
{
    private let connection: ExploreDatabaseConnection
    
    let serialQueue = DispatchQueue(label: "org.dashfoundation.dashpaytnt.explore.serial.queue")
    
    init(dbConnection: ExploreDatabaseConnection) {
        self.connection = dbConnection
    }
    
    func merchants(query: String?, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            let query = """
                SELECT *
                FROM merchant
                \(query != nil ? "WHERE name LIKE '\(query!)%'" : "")
                ORDER BY
                    CASE
                    WHEN type IN ('physical', 'both') THEN 1
                    WHEN type = 'online' THEN 2
                    END,
                    \(userPoint != nil ? "ABS(latitude-\(userPoint!.latitude)) + ABS(longitude - \(userPoint!.longitude)) ASC," : "")
                    name
                LIMIT \(pageLimit)
                OFFSET \(offset)
                """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: offset + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func merchantsInRect(bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }

            let anchorLatitude = userPoint?.latitude ?? bounds.center.latitude
            let anchorLongitude = userPoint?.longitude ?? bounds.center.longitude
            
            let query = """
                SELECT *
                FROM merchant
                WHERE type IN ('physical', 'both')
                    AND latitude > \(bounds.swCoordinate.latitude)
                    AND latitude < \(bounds.neCoordinate.latitude)
                    AND longitude < \(bounds.neCoordinate.longitude)
                    AND longitude > \(bounds.swCoordinate.longitude)
                GROUP BY source, merchantId
                HAVING (latitude - \(anchorLatitude))*(latitude - \(anchorLatitude)) + (longitude - \(anchorLongitude))*(longitude - \(anchorLongitude)) = MIN((latitude - \(anchorLatitude))*(latitude - \(anchorLatitude)) + (longitude - \(anchorLongitude))*(longitude - \(anchorLongitude)))
                ORDER BY ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC
                
            """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: 0 + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func searchMerchants(by query: String, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            let anchorLatitude = userPoint?.latitude ?? bounds.center.latitude
            let anchorLongitude = userPoint?.longitude ?? bounds.center.longitude
            
            let query = """
                SELECT *
                FROM merchant
                WHERE type IN ('physical', 'both')
                    AND name LIKE '\(query)%'
                    AND latitude > \(bounds.swCoordinate.latitude)
                    AND latitude < \(bounds.neCoordinate.latitude)
                    AND longitude < \(bounds.neCoordinate.longitude)
                    AND longitude > \(bounds.swCoordinate.longitude)
                ORDER BY ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC
                
            """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: 0 + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func allLocations(for merchant: Merchant, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            
            let anchorLatitude = userPoint?.latitude ?? bounds.center.latitude
            let anchorLongitude = userPoint?.longitude ?? bounds.center.longitude
            
            let query = """
                SELECT *
                FROM merchant
                WHERE type IN ('physical', 'both')
                    AND merchantId = \(merchant.merchantId)
                    AND latitude > \(bounds.swCoordinate.latitude)
                    AND latitude < \(bounds.neCoordinate.latitude)
                    AND longitude < \(bounds.neCoordinate.longitude)
                    AND longitude > \(bounds.swCoordinate.longitude)
                ORDER BY ABS(latitude-\(anchorLatitude)) + ABS(longitude - \(anchorLongitude)) ASC
            """
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: 0 + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func allOnlineMerchants(offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        serialQueue.async { [weak self] in
            guard let wSelf = self else { return }
            let query = """
                SELECT *
                FROM merchant
                WHERE type IN ('online', 'both')
                GROUP BY source, merchantId
                ORDER BY name
                """
            
            do {
                let items: [Merchant] = try wSelf.connection.execute(query: query)
                completion(.success(PaginationResult(items: items, offset: offset + pageLimit)))
            }catch{
                print(error)
                completion(.failure(error))
            }
        }
    }
    
    func allOnlineMerchants(offset: Int = 0) -> PaginationResult<Merchant> {
        let query =
            """
            SELECT *
            FROM merchant
            WHERE type IN ('online', 'both')
            GROUP BY source, merchantId
            ORDER BY name
            """
        
        do {
            let items: [Merchant] = try connection.execute(query: query)
            return PaginationResult(items: items, offset: offset + pageLimit)
        }catch{
            print(error)
            return PaginationResult(items: [], offset: 0)
        }
    }
    
    func searchOnlineMerchants(query: String, offset: Int = 0) -> PaginationResult<Merchant> {
        let query =
            """
            SELECT *
            FROM merchant
            WHERE type IN ('online', 'both')
            AND name LIKE '\(query)%'
            GROUP BY source, merchantId
            ORDER BY name
            """
        
        do {
            let items: [Merchant] = try connection.execute(query: query)
            return PaginationResult(items: items, offset: offset + pageLimit)
        }catch{
            print(error)
            return PaginationResult(items: [], offset: 0)
        }
    }
}

struct PaginationResult<Item> {
    var items: [Item]
    var offset: Int
}

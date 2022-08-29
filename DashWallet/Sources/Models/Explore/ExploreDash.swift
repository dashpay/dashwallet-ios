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

@objc public class ExploreDashObjcWrapper: NSObject {
    @objc public class func configure() {
        do {
            try ExploreDash.configure()
        }catch{
            print(error)
            //Do something
        }
    }
}

let bundleExploreDatabaseSyncTime: TimeInterval = 1647448290710

public class ExploreDash {
    private var isConfigured: Bool = false
    
    private var databaseSyncManager: ExploreDatabaseSyncManager!
    private var databaseConnection: ExploreDatabaseConnection!
    
    var merchantDAO: MerchantDAO!
    var atmDAO: AtmDAO!
    
    private func configure() throws {
        guard !isConfigured else { return }
        
        try prepareDatabase()
        
        databaseConnection = ExploreDatabaseConnection()
        try databaseConnection.connect()
        
        databaseSyncManager = ExploreDatabaseSyncManager()
        databaseSyncManager.start()
        
        merchantDAO = MerchantDAO(dbConnection: databaseConnection)
        atmDAO = AtmDAO(dbConnection: databaseConnection)
        
        isConfigured = true
    }
    
    private func prepareDatabase() throws {
        let destinationPath = FileManager.getDocumentsDirectory()
            .appendingPathComponent("explore.db", isDirectory: true)
        let finalDestinationPath = destinationPath.appendingPathComponent("explore.db")
        
        guard !FileManager.default.fileExists(atPath: finalDestinationPath.path) else { return }
        
        try? FileManager.default.removeItem(atPath: destinationPath.path)
        try FileManager.default.createDirectory(at: destinationPath, withIntermediateDirectories: true, attributes: nil)
    
        guard let dbURL = Bundle.main.url(forResource: "explore", withExtension: "db") else {
            throw ExploreDatabaseConnectionError.fileNotFound
        }
        
        try FileManager.default.copyItem(at: dbURL, to: finalDestinationPath)
    }
    
    public static let shared: ExploreDash = ExploreDash()
}

extension ExploreDash {
    func onlineMerchants(query: String?, onlineOnly: Bool, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.onlineMerchants(query: query, onlineOnly: onlineOnly, userPoint: userPoint, offset: offset, completion: completion)
    }
    
    func nearbyMerchants(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.nearbyMerchants(by: query, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
    
    func allMerchants(by query: String?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.allMerchants(by: query, offset: offset, completion: completion)
    }
    
    func allMerchants(by query: String?, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.allMerchants(by: query, in: bounds, userPoint: userPoint, offset: offset, completion: completion)
    }
    
    func allLocations(for merchant: ExplorePointOfUse, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.allLocations(for: merchant, in: bounds, userPoint: userPoint, completion: completion)
    }
}

extension ExploreDash {
    func atms(query: String?, in types: [ExplorePointOfUse.Atm.`Type`]?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        let filters = PointOfUseDAOFilters(filters: ["query": query, "types": types, "bounds": bounds, "userLocation": userPoint, "offset": offset])
        atmDAO.items(filters: filters, completion: completion)
    }
}
extension ExploreDash {
    public class func configure() throws {
        try ExploreDash.shared.configure()
    }
}

extension BinaryInteger {
    var degreesToRadians: CGFloat { CGFloat(self) * .pi / 180 }
}

extension FloatingPoint {
    var degreesToRadians: Self { self * .pi / 180 }
    var radiansToDegrees: Self { self * 180 / .pi }
}


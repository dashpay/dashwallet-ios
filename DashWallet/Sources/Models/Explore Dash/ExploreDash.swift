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

typealias TerritoryDataSource = (@escaping (Result<[Territory], any Error>) -> Void) -> ()

//In meters
let kDefaultRadius: Double = 32000

extension ExploreDatabaseSyncManager.State {
    var objcState: ExploreDashObjcWrapper.SyncState {
        switch self {
        case .inititialing: return .inititialing
        case .syncing: return .syncing
        case .fetchingInfo: return .fetchingInfo
        case .synced(_): return .synced
        case .error(_): return .error
        }
    }
}

@objc public class ExploreDashObjcWrapper: NSObject {
    @objc public enum SyncState: Int {
        case inititialing
        case fetchingInfo
        case syncing
        case synced
        case error
    }
    
    @objc public class func configure() {
        do {
            try ExploreDash.configure()
        }catch{
            print(error)
            //Do something
        }
    }
    
    @objc public class var syncState: ExploreDashObjcWrapper.SyncState {
        return ExploreDash.shared.syncState.objcState
    }
    
    @objc public class var lastServerUpdateDate: Date {
        return ExploreDash.shared.lastServerUpdateDate
    }
    
    @objc public class var lastSyncTryDate: Date? {
        return ExploreDash.shared.lastSyncTryDate
    }
    
    @objc public class var lastFailedSyncDate: Date? {
        return ExploreDash.shared.lastFailedSyncDate
    }
}

public class ExploreDash {
    static var distanceFormatter: Foundation.MeasurementFormatter = {
        var formatter = MeasurementFormatter()
        formatter.locale = Locale.current
        formatter.unitOptions = .naturalScale
        return formatter
    }()
    
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
        
        databaseSyncManager = ExploreDatabaseSyncManager.share
        databaseSyncManager.start()
        
        merchantDAO = MerchantDAO(dbConnection: databaseConnection)
        atmDAO = AtmDAO(dbConnection: databaseConnection)
        
        isConfigured = true
    }
    
    private func prepareDatabase() throws {
        let destinationPath = FileManager.documentsDirectoryURL
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
    func onlineMerchants(query: String?, onlineOnly: Bool, paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?, userPoint: CLLocationCoordinate2D?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.onlineMerchants(query: query, onlineOnly: onlineOnly, userPoint: userPoint, paymentMethods: paymentMethods, offset: offset, completion: completion)
    }
    
    func nearbyMerchants(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?, sortBy: PointOfUseListFilters.SortBy?, territory: Territory?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.nearbyMerchants(by: query, in: bounds, userPoint: userPoint, paymentMethods: paymentMethods, sortBy: sortBy, territory: territory, offset: offset, completion: completion)
    }

    func allMerchants(by query: String?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, paymentMethods: [ExplorePointOfUse.Merchant.PaymentMethod]?, sortBy: PointOfUseListFilters.SortBy?, territory: Territory?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.allMerchants(by: query, in: bounds, userPoint: userPoint, paymentMethods: paymentMethods, sortBy: sortBy, territory: territory, offset: offset, completion: completion)
    }
    
    func allLocations(for merchantId: Int64, in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        merchantDAO.allLocations(for: merchantId, in: bounds, userPoint: userPoint, completion: completion)
    }
    
    func fetchTerritoriesForMerchants(completion: @escaping (Swift.Result<[Territory], Error>) -> Void) {
        merchantDAO.territories(completion: completion)
    }
    
    func fetchTerritoriesForAtms(completion: @escaping (Swift.Result<[Territory], Error>) -> Void) {
        atmDAO.territories(completion: completion)
    }
}

extension ExploreDash {
    func atms(query: String?, in types: [ExplorePointOfUse.Atm.`Type`]?, in bounds: ExploreMapBounds?, userPoint: CLLocationCoordinate2D?, with filters: PointOfUseListFilters?, offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<ExplorePointOfUse>, Error>) -> Void) {
        let filters: [PointOfUseDAOFilterKey: Any?] = [.query: query, .types: types, .bounds: bounds, .userLocation: userPoint, .territory: filters?.territory, .sortDirection: filters?.sortNameDirection ]
        
        atmDAO.items(filters: filters, offset: offset, completion: completion)
    }
}

extension ExploreDash {
    var lastServerUpdateDate: Date {
        return ExploreDatabaseSyncManager.share.lastServerUpdateDate
    }
    
    var syncState: ExploreDatabaseSyncManager.State {
        return ExploreDatabaseSyncManager.share.syncState
    }
    
    var lastSyncTryDate: Date? {
        switch syncState {
        case .synced(let date):
            return date
        default:
            return nil
        }
    }
    
    var lastFailedSyncDate: Date? {
        switch syncState {
        case .error(let date, _):
            return date
        default:
            return nil
        }
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


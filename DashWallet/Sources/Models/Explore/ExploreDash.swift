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
    
    private var merchantDAO: MerchantDAO!
    
    private func configure() throws {
        guard !isConfigured else { return }
        
        try prepareDatabase()
        
        databaseConnection = ExploreDatabaseConnection()
        try databaseConnection.connect()
        
        databaseSyncManager = ExploreDatabaseSyncManager()
        databaseSyncManager.start()
        
        merchantDAO = MerchantDAO(dbConnection: databaseConnection)
        
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
    /**
     Retrieve merchants by location
     @param location Center of
     @param rect Visible
    */
    func merchants(in bounds: ExploreMapBounds, userPoint: CLLocationCoordinate2D?, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        merchantDAO.merchantsInRect(bounds: bounds, userPoint: userPoint, completion: completion)
    }
    
    func allOnlineMerchants(offset: Int = 0, completion: @escaping (Swift.Result<PaginationResult<Merchant>, Error>) -> Void) {
        merchantDAO.allOnlineMerchants(offset: offset, completion: completion)
    }
    
    func allOnlineMerchants(offset: Int = 0) -> PaginationResult<Merchant> {
        return merchantDAO.allOnlineMerchants(offset: offset)
    }
    
    func searchOnlineMerchants(query: String, offset: Int = 0) -> PaginationResult<Merchant> {
        return merchantDAO.searchOnlineMerchants(query: query, offset: offset)
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

extension CLLocation {
    func derivedPosition(inRange range: Double, bearing: Double)-> CGPoint {
        let earthRadius: Double = 6371000
        
        let lat = Double(self.coordinate.latitude.degreesToRadians)
        let lon = Double(self.coordinate.longitude.degreesToRadians)
        let angularDistance = range/earthRadius
        let trueCourse = bearing.degreesToRadians
        
        var resultLat = asin(sin(lat) * cos(angularDistance) +
                       cos(lat) * sin(angularDistance) *
                       cos(trueCourse))
        
        let derivedlon = atan2(sin(trueCourse) * sin(angularDistance) * cos(lat),
                         cos(angularDistance) - sin(lat) * sin(lat))
        
        var resultLon = ((lon + derivedlon + Double.pi).truncatingRemainder(dividingBy: (Double.pi * 2))) - Double.pi
        
        resultLat = lat.radiansToDegrees
        resultLon = lon.radiansToDegrees
        
        let newPoint = CGPoint(x: lat, y: lon)
        return newPoint
    }
}

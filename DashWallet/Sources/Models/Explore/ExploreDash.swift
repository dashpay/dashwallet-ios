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
        let destinationPath = FileManager.getDocumentsDirectory().appendingPathComponent("explore.db")
        
        guard !FileManager.default.fileExists(atPath: destinationPath.path) else { return }
        
        guard let dbURL = Bundle.main.url(forResource: "explore", withExtension: "db") else {
            throw ExploreDatabaseConnectionError.fileNotFound
        }
        
        try FileManager.default.copyItem(at: dbURL, to: destinationPath)
    }
    
    public static let shared: ExploreDash = ExploreDash()
}

extension ExploreDash {
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

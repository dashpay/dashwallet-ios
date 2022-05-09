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

enum ExploreDatabaseConnectionError: Error  {
    case fileNotFound
}

class ExploreDatabaseConnection
{
    private var db: Connection!
    
    init() {
        NotificationCenter.default.addObserver(forName: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification, object: nil, queue: .main) { [weak self] notification in
        //    try? self?.connect()
        }
    }
    
    func connect() throws {
        db = nil
        
        guard let dbPath = dbPath() else { throw ExploreDatabaseConnectionError.fileNotFound}
        
        do {
            db = try Connection(nil ?? dbPath)
        }catch{
            print(error)
        }
        
    }
    
    private func dbPath() -> String? {
        let downloadedPath = FileManager.getDocumentsDirectory().appendingPathComponent("explore.db").path
        
        return FileManager.default.fileExists(atPath: downloadedPath) ? downloadedPath : nil
    }
    
    func find<Item: RowDecodable>(query: QueryType) throws -> [Item] {
        let items = try db.prepare(query)
        
        var resultItems: [Item] = []
        
        for item in items {
            resultItems.append(Item(row: item))
        }
        
        return resultItems
    }
    
    
}

extension Row
{
    public func get<V: Value>(_ column: String) throws -> V? {
        return try self.get(Expression<V>(column))
    }
}
protocol RowDecodable {
    init(row: Row)
}

//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import SQLiteMigrationManager

struct AddIconBitmapsTable: Migration {
    var version: Int64 = 20250114130000
    
    func migrateDatabase(_ db: Connection) throws {
        try db.run(IconBitmap.table.create(ifNotExists: true) { t in
            t.column(IconBitmap.id, primaryKey: true)
            t.column(IconBitmap.imageData)
            t.column(IconBitmap.originalUrl)
            t.column(IconBitmap.height)
            t.column(IconBitmap.width)
        })
    }
} 
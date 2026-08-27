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

struct AddGiftCardsTable: Migration {
    var version: Int64 = 20250114120000
    
    func migrateDatabase(_ db: Connection) throws {
        try db.run(GiftCard.table.create(ifNotExists: true) { t in
            t.column(GiftCard.txId, primaryKey: true)
            t.column(GiftCard.merchantName)
            t.column(GiftCard.merchantUrl)
            t.column(GiftCard.price)
            t.column(GiftCard.number)
            t.column(GiftCard.pin)
            t.column(GiftCard.barcodeValue)
            t.column(GiftCard.barcodeFormat)
            t.column(GiftCard.note)
        })
    }
} 
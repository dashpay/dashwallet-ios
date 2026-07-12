//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

struct AddSwapOrdersTable: Migration {
    var version: Int64 = 20260710100000

    func migrateDatabase(_ db: Connection) throws {
        try db.run(SwapOrder.table.create(ifNotExists: true) { t in
            t.column(SwapOrder.colId, primaryKey: true)
            t.column(SwapOrder.colDirection)
            t.column(SwapOrder.colService)
            t.column(SwapOrder.colProvider)
            t.column(SwapOrder.colFromAsset)
            t.column(SwapOrder.colToAsset)
            t.column(SwapOrder.colToAddress)
            t.column(SwapOrder.colDepositAddress)
            t.column(SwapOrder.colExpectedToAmount)
            t.column(SwapOrder.colActualToAmount)
            t.column(SwapOrder.colStatus)
            t.column(SwapOrder.colOutboundTxHash)
            t.column(SwapOrder.colTimestamp)
            t.column(SwapOrder.colFinalisedAt)
            t.column(SwapOrder.colLastChecked)
        })
    }
}

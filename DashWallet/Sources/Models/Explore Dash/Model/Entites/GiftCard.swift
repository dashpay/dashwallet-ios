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

// MARK: - GiftCard

struct GiftCard: RowDecodable {
    let txId: Data
    let merchantName: String
    let merchantUrl: String?
    let price: Decimal
    let number: String?
    let pin: String?
    let barcodeValue: String?
    let barcodeFormat: String?
    let note: String?
    let provider: String?

    static let table = Table("gift_cards")
    static let txId = SQLite.Expression<Data>("txId")
    static let merchantName = SQLite.Expression<String>("merchantName")
    static let merchantUrl = SQLite.Expression<String?>("merchantUrl")
    static let price = SQLite.Expression<String>("price")
    static let number = SQLite.Expression<String?>("number")
    static let pin = SQLite.Expression<String?>("pin")
    static let barcodeValue = SQLite.Expression<String?>("barcodeValue")
    static let barcodeFormat = SQLite.Expression<String?>("barcodeFormat")
    static let note = SQLite.Expression<String?>("note")
    static let provider = SQLite.Expression<String?>("provider")
    
    init(row: Row) {
        self.txId = row[GiftCard.txId]
        self.merchantName = row[GiftCard.merchantName]
        self.merchantUrl = row[GiftCard.merchantUrl]
        self.price = Decimal(string: row[GiftCard.price]) ?? 0
        self.number = row[GiftCard.number]
        self.pin = row[GiftCard.pin]
        self.barcodeValue = row[GiftCard.barcodeValue]
        self.barcodeFormat = row[GiftCard.barcodeFormat]
        self.note = row[GiftCard.note]
        // Safely handle provider column that may not exist yet
        self.provider = try? row.get(GiftCard.provider)
    }

    init(txId: Data, merchantName: String, merchantUrl: String?, price: Decimal, number: String? = nil,
         pin: String? = nil, barcodeValue: String? = nil, barcodeFormat: String? = nil, note: String? = nil, provider: String? = nil) {
        self.txId = txId
        self.merchantName = merchantName
        self.merchantUrl = merchantUrl
        self.price = price
        self.number = number
        self.pin = pin
        self.barcodeValue = barcodeValue
        self.barcodeFormat = barcodeFormat
        self.note = note
        self.provider = provider
    }
} 

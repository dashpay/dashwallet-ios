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

struct Merchant {
    let name: String
    let merchantId: Int64
    let id: Int64
    let active: Bool
    let paymentMethod: PaymentMethod
    let type: `Type`
    let city: String?
    let territory: String?
    let address1: String?
    let address2: String?
    let address3: String?
    let address4: String?
    let latitude: Double?
    let longitude: Double?
    let website: String?
    let phone: String?
    let logoLocation: String?
    let coverImage: String?
    let plusCode: String?
    let deeplink: String?
    
    enum PaymentMethod: String {
        case dash
        case giftCard
        
        init?(rawValue: String) {
            if rawValue == "dash" {
                self = .dash
            }else{
                self = .giftCard
            }
        }
    }
    
    enum `Type`: String {
        case online
        case physical
        case onlineAndPhysical = "both"
    }
}

extension Merchant: RowDecodable {
    static let name = Expression<String>("name")
    static let deeplink = Expression<String>("deeplink")
    static let plusCode = Expression<String>("plusCode")
    static let paymentMethod = Expression<String>("paymentMethod")
    static let merchantId = Expression<Int64>("merchantId")
    static let id = Expression<Int64>("id")
    static let active = Expression<Bool>("active")
    static let city = Expression<String>("city")
    static let territory = Expression<String>("territory")
    static let address1 = Expression<String?>("address1")
    static let address2 = Expression<String?>("address2")
    static let address3 = Expression<String?>("address3")
    static let address4 = Expression<String?>("address4")
    static let latitude = Expression<Float64?>("latitude")
    static let longitude = Expression<Float64?>("longitude")
    static let website = Expression<String>("website")
    static let phone = Expression<String>("phone")
    static let logoLocation = Expression<String>("logoLocation")
    static let coverImage = Expression<String?>("coverImage")
    static let type = Expression<String>("type")
    static let source = Expression<String>("source")
    
    
    init(row: Row) {
        let name = row[Merchant.name]
        let merchantId = row[Merchant.merchantId]
        let id = row[Merchant.id]
        let active = row[Merchant.active]
        let paymentMethod = PaymentMethod(rawValue: row[Merchant.paymentMethod])
        let type = `Type`(rawValue: row[Merchant.type])
        let city = row[Merchant.city]
        let territory = row[Merchant.territory]
        let address1 = row[Merchant.address1]
        let address2 = row[Merchant.address2]
        let address3 = row[Merchant.address3]
        let address4 = row[Merchant.address4]
        let latitude = row[Merchant.latitude]
        let longitude = row[Merchant.longitude]
        let website = row[Merchant.website]
        let phone = row[Merchant.phone]
        let logoLocation = row[Merchant.logoLocation]
        let coverImage: String? = row[Merchant.coverImage]
        let plusCode = row[Merchant.plusCode]
        let deeplink = row[Merchant.deeplink]
        
        self.init(name: name, merchantId: merchantId, id: id, active: active, paymentMethod: paymentMethod!, type: type!, city: city, territory: territory, address1: address1, address2: address2, address3: address3, address4: address4, latitude: latitude, longitude: longitude, website: website, phone: phone, logoLocation: logoLocation, coverImage: coverImage, plusCode: plusCode, deeplink: deeplink)
    }
}

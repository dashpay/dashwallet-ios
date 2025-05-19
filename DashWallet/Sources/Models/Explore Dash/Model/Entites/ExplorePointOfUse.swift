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
private typealias Expression = SQLite.Expression

// MARK: - ExplorePointOfUse + Hashable

extension ExplorePointOfUse: Hashable {
    static func == (lhs: ExplorePointOfUse, rhs: ExplorePointOfUse) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ExplorePointOfUse {
    struct Merchant {

        enum PaymentMethod: String {
            case dash
            case giftCard = "gift card"

            init?(rawValue: String) {
                if rawValue == "dash" {
                    self = .dash
                } else {
                    self = .giftCard
                }
            }
        }

        enum `Type`: String {
            case online
            case physical
            case onlineAndPhysical = "both"
        }

        let merchantId: String
        let paymentMethod: PaymentMethod
        let type: `Type`
        let deeplink: String?
        let savingsBasisPoints: Int // in basis points 1 = 0.001%
    }

    var merchant: Merchant? {
        guard case .merchant(let m) = category else { return nil }

        return m
    }

    var atm: Atm? {
        guard case .atm(let atm) = category else { return nil }

        return atm
    }

    var pointOfUseId: String {
        switch category {
        case .merchant(let m):
            return m.merchantId
        case .atm(let atm):
            return atm.manufacturer
        case .unknown:
            return ""
        }
    }
    
    var emptyLogoImageName: String {
        switch category {
        case .merchant(_), .unknown:
            return "image.explore.dash.wts.item.logo.empty"
        case .atm:
            return "image.explore.dash.atm.item.logo.empty"
        }
    }
}

// MARK: - ExplorePointOfUse.Atm

extension ExplorePointOfUse {
    struct Atm {
        enum `Type`: String {
            case buy = "Buy Only"
            case sell = "Sell Only"
            case buySell = "Buy and Sell"

            public init?(rawValue: String) {
                switch rawValue {
                case "Buy Only": self = .buy
                case "Sell Only": self = .sell
                case "Buy and Sell": self = .buySell
                default: self = .buy
                }
            }
        }

        let manufacturer: String
        let type: `Type`
    }
}

// MARK: - ExplorePointOfUse

struct ExplorePointOfUse {
    enum Category {
        case merchant(Merchant)
        case atm(Atm)
        case unknown
    }

    let id: Int64

    let name: String
    let category: Category
    let active: Bool
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
    let source: String?

    var isPhysical: Bool {
        switch category {
        case .merchant(let m):
            return m.type != .online
        case .atm:
            return true
        case .unknown:
            return false
        }
    }
}

// MARK: RowDecodable

extension ExplorePointOfUse: RowDecodable {
    static let name = Expression<String>("name")
    static let deeplink = Expression<String?>("deeplink")
    static let plusCode = Expression<String?>("plusCode")
    static let paymentMethod = Expression<String>("paymentMethod")
    static let merchantId = Expression<String>("merchantId")
    static let id = Expression<Int64>("id")
    static let active = Expression<Bool>("active")
    static let city = Expression<String?>("city")
    static let territory = Expression<String>("territory")
    static let address1 = Expression<String?>("address1")
    static let address2 = Expression<String?>("address2")
    static let address3 = Expression<String?>("address3")
    static let address4 = Expression<String?>("address4")
    static let latitude = Expression<Float64?>("latitude")
    static let longitude = Expression<Float64?>("longitude")
    static let website = Expression<String?>("website")
    static let phone = Expression<String?>("phone")
    static let logoLocation = Expression<String>("logoLocation")
    static let coverImage = Expression<String?>("coverImage")
    static let type = Expression<String>("type")
    static let source = Expression<String>("source")
    static let manufacturer = Expression<String?>("manufacturer")
    static let savingPercentage = Expression<Int>("savingsPercentage")

    init(row: Row) {
        let name = row[ExplorePointOfUse.name]

        let id = row[ExplorePointOfUse.id]
        let active = row[ExplorePointOfUse.active]

        let city = row[ExplorePointOfUse.city]
        let territory = row[ExplorePointOfUse.territory]
        let address1 = row[ExplorePointOfUse.address1]
        let address2 = row[ExplorePointOfUse.address2]
        let address3 = row[ExplorePointOfUse.address3]
        let address4 = row[ExplorePointOfUse.address4]
        let latitude = row[ExplorePointOfUse.latitude]
        let longitude = row[ExplorePointOfUse.longitude]
        var website: String?

        if let value = row[ExplorePointOfUse.website], !value.isEmpty {
            if !value.hasPrefix("http") {
                website = "https://" + value
            } else {
                website = value
            }
        }

        let phone: String? = try? row.get(ExplorePointOfUse.phone)?.digits
        let logoLocation: String? = try? row.get(ExplorePointOfUse.logoLocation)
        let coverImage: String? = try? row.get(ExplorePointOfUse.coverImage)
        let source: String? = row[ExplorePointOfUse.source]

        let category: Category
        if let paymentMethodRaw = try? row.get(ExplorePointOfUse.paymentMethod) {
            let merchantId = row[ExplorePointOfUse.merchantId]
            let type: Merchant.`Type`! = .init(rawValue: row[ExplorePointOfUse.type])
            let deeplink = row[ExplorePointOfUse.deeplink]
            let savingsPercentage = row[ExplorePointOfUse.savingPercentage]
            category = .merchant(Merchant(merchantId: merchantId,
                                          paymentMethod: Merchant.PaymentMethod(rawValue: paymentMethodRaw)!,
                                          type: type, deeplink: deeplink, savingsBasisPoints: savingsPercentage))
        } else if let manufacturer = try? row.get(ExplorePointOfUse.manufacturer) {
            let type: Atm.`Type`! = .init(rawValue: row[ExplorePointOfUse.type])
            category = .atm(Atm(manufacturer: manufacturer, type: type))
        } else {
            category = .unknown
        }

        self.init(id: id, name: name, category: category, active: active, city: city, territory: territory, address1: address1,
                  address2: address2, address3: address3, address4: address4, latitude: latitude, longitude: longitude,
                  website: website, phone: phone, logoLocation: logoLocation, coverImage: coverImage, source: source)
    }
}


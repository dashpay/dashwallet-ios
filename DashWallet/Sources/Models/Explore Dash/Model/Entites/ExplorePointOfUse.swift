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
        
        struct GiftCardProviderInfo {
            let providerId: String
            let provider: GiftCardProvider?
            let savingsPercentage: Int
            let denominationsType: String
            let sourceId: String?

            init(providerId: String, savingsPercentage: Int = 0, denominationsType: String = "", sourceId: String? = nil) {
                self.providerId = providerId
                self.savingsPercentage = savingsPercentage
                self.denominationsType = denominationsType
                self.sourceId = sourceId
                switch providerId.lowercased() {
                case "ctx":
                    self.provider = .ctx
                #if PIGGYCARDS_ENABLED
                case "piggycards", "piggy cards":
                    self.provider = .piggyCards
                #endif
                default:
                    self.provider = nil
                }
            }
        }

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
        /// `nil` when the synced database carries a `type` this build doesn't
        /// know — a category added server-side, or a NULL. Unknown stays
        /// unknown rather than being mapped onto one of the three cases.
        let type: `Type`?
        let deeplink: String?
        let savingsBasisPoints: Int // in basis points 1 = 0.001%
        let denominationsType: String?
        let denominations: [Int]
        let redeemType: String?
        let giftCardProviders: [GiftCardProviderInfo]
        
        init(merchantId: String, paymentMethod: PaymentMethod, type: `Type`?, deeplink: String?, savingsBasisPoints: Int, denominationsType: String?, denominations: [Int] = [], redeemType: String?, giftCardProviders: [GiftCardProviderInfo] = []) {
            self.merchantId = merchantId
            self.paymentMethod = paymentMethod
            self.type = type
            self.deeplink = deeplink
            self.savingsBasisPoints = savingsBasisPoints
            self.denominationsType = denominationsType
            self.denominations = denominations
            self.redeemType = redeemType
            self.giftCardProviders = giftCardProviders
        }
        
        func toSavingPercentages() -> Double {
            return Double(savingsBasisPoints) / 100
        }
        
        func toSavingsFraction() -> Double {
            return Double(savingsBasisPoints) / 10000
        }
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
        /// `nil` when the row carries no `type` at all; a non-empty but
        /// unrecognized value still resolves through `Type.init(rawValue:)`.
        let type: `Type`?
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

// MARK: - Address

extension ExplorePointOfUse {
    var address: String {
        [name, address1, address2, address3, address4, city, territory]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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
    static let denominationsType = Expression<String?>("denominationsType")
    static let redeemType = Expression<String?>("redeemType")

    init(row: Row) {
        // The explore database is generated server-side and none of its text
        // columns are declared NOT NULL, so every column here can arrive as
        // NULL. SQLite.swift's subscript for a non-optional `Expression` is
        // `try! get(column)`, which aborts the process on NULL (and on a
        // column the synced schema no longer carries) — `try? row.get` is the
        // same read without that trap, and is what this initializer already
        // used for `phone`, `logoLocation` and `coverImage`.
        let name = (try? row.get(ExplorePointOfUse.name)) ?? ""

        let id = row[ExplorePointOfUse.id]
        // `active` is `INTEGER DEFAULT 1` in the schema; absent means active.
        let active = (try? row.get(ExplorePointOfUse.active)) ?? true

        let city = row[ExplorePointOfUse.city]
        let territory = try? row.get(ExplorePointOfUse.territory)
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
        let source: String? = try? row.get(ExplorePointOfUse.source)

        let category: Category
        if let paymentMethodRaw = try? row.get(ExplorePointOfUse.paymentMethod) {
            let merchantId = (try? row.get(ExplorePointOfUse.merchantId)) ?? ""
            // Written through an annotated binding: spelled out in full,
            // `Merchant.`Type`` parses as the metatype and `.init(rawValue:)`
            // doesn't resolve against it.
            let type: Merchant.`Type`? = (try? row.get(ExplorePointOfUse.type)).flatMap { .init(rawValue: $0) }
            let deeplink = row[ExplorePointOfUse.deeplink]
            let savingsPercentage = (try? row.get(ExplorePointOfUse.savingPercentage)) ?? 0
            let denominationsType = row[ExplorePointOfUse.denominationsType]
            let redeemType = row[ExplorePointOfUse.redeemType]
            category = .merchant(Merchant(merchantId: merchantId, paymentMethod: Merchant.PaymentMethod(rawValue: paymentMethodRaw)!,
                                          type: type, deeplink: deeplink, savingsBasisPoints: savingsPercentage, denominationsType: denominationsType, denominations: [], redeemType: redeemType, giftCardProviders: []))
        } else if let manufacturer = try? row.get(ExplorePointOfUse.manufacturer) {
            let type: Atm.`Type`? = (try? row.get(ExplorePointOfUse.type)).flatMap { .init(rawValue: $0) }
            category = .atm(Atm(manufacturer: manufacturer, type: type))
        } else {
            category = .unknown
        }

        self.init(id: id, name: name, category: category, active: active, city: city, territory: territory, address1: address1,
                  address2: address2, address3: address3, address4: address4, latitude: latitude, longitude: longitude,
                  website: website, phone: phone, logoLocation: logoLocation, coverImage: coverImage, source: source)
    }
}


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

// MARK: - Request Models

struct LoginRequest: Codable {
    let email: String
}

struct VerifyEmailRequest: Codable {
    let email: String
    let code: String
}

public struct RefreshTokenRequest: Codable {
    let refreshToken: String
}

public struct PurchaseGiftCardRequest: Codable {
    let cryptoCurrency: String
    let fiatCurrency: String
    let fiatAmount: String
    let merchantId: String
}

// MARK: - Response Models

struct VerifyEmailResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct GiftCardResponse: Codable {
    // Required fields
    let id: String
    let status: String // unpaid, paid, fulfilled, rejected
    let paymentId: String

    // Optional fields
    let barcodeUrl: String?
    let cardNumber: String?
    let cardPin: String?

    let cryptoAmount: String?
    let cryptoCurrency: String?
    let paymentCryptoNetwork: String?
    let percentDiscount: String?
    let rate: String?
    let redeemType: String?
    let redeemUrl: String?
    let redeemUrlChallenge: String?
    let fiatAmount: String?
    let fiatCurrency: String?
    let paymentUrls: [String: String]?

    let cardFiatAmount: String?
    let cardFiatCurrency: String?
    let userId: String?
    let merchantName: String?
    let userEmail: String?
    let created: String?
    let info: MerchantInfo?
    
    enum CodingKeys: String, CodingKey {
        case id
        case status
        case barcodeUrl
        case cardNumber = "number"
        case cardPin = "pin"
        case cryptoAmount = "paymentCryptoAmount"
        case cryptoCurrency = "paymentCryptoCurrency"
        case paymentCryptoNetwork
        case paymentId
        case percentDiscount
        case rate
        case redeemType
        case redeemUrl
        case redeemUrlChallenge
        case fiatAmount = "paymentFiatAmount"
        case fiatCurrency = "paymentFiatCurrency"
        case paymentUrls
        case cardFiatAmount
        case cardFiatCurrency
        case userId
        case merchantName
        case userEmail
        case created
        case info
    }
}

struct MerchantResponse: Decodable {
    let id: String
    let name: String
    let logoUrl: String
    let enabled: Bool

    // Support both production (savingsPercentage) and staging (userDiscount) field names
    let savingsPercentage: Int?  // Production API field
    let userDiscount: Int?        // Staging API field

    let denominationsType: String
    let denominations: [String]

    // Support both production (cachedLocationCount) and staging (locationCount) field names
    let cachedLocationCount: Int?  // Production API field
    let locationCount: Int?        // Staging API field

    let mapPinUrl: String
    let type: String
    let redeemType: String
    let info: MerchantInfo?
    let cardImageUrl: String
    let currency: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case logoUrl
        case enabled
        case savingsPercentage
        case userDiscount
        case denominationsType
        case denominationType
        case denominations
        case denominationValues
        case cachedLocationCount
        case locationCount
        case mapPinUrl
        case type
        case redeemType
        case info
        case cardImageUrl
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        // Match Android leniency: only id/denominations/denominationsType are required.
        // Staging omits logoUrl/mapPinUrl/cardImageUrl, so decode all display fields optionally.
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        logoUrl = try container.decodeIfPresent(String.self, forKey: .logoUrl) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true

        savingsPercentage = try container.decodeIfPresent(Int.self, forKey: .savingsPercentage)
        userDiscount = try container.decodeIfPresent(Int.self, forKey: .userDiscount)

        let primaryDenominationType = try container.decodeIfPresent(String.self, forKey: .denominationsType)
        let legacyDenominationType = try container.decodeIfPresent(String.self, forKey: .denominationType)
        denominationsType = primaryDenominationType ?? legacyDenominationType ?? DenominationType.Fixed.rawValue

        denominations = Self.decodeDenominations(from: container)

        cachedLocationCount = try container.decodeIfPresent(Int.self, forKey: .cachedLocationCount)
        locationCount = try container.decodeIfPresent(Int.self, forKey: .locationCount)

        mapPinUrl = try container.decodeIfPresent(String.self, forKey: .mapPinUrl) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        redeemType = try container.decodeIfPresent(String.self, forKey: .redeemType) ?? ""
        info = try container.decodeIfPresent(MerchantInfo.self, forKey: .info)
        cardImageUrl = try container.decodeIfPresent(String.self, forKey: .cardImageUrl) ?? ""
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? ""
    }

    private static func decodeDenominations(from container: KeyedDecodingContainer<CodingKeys>) -> [String] {
        if let stringValues = try? container.decode([String].self, forKey: .denominations), !stringValues.isEmpty {
            return stringValues
        }
        if let doubleValues = try? container.decode([Double].self, forKey: .denominations), !doubleValues.isEmpty {
            return doubleValues.map { NSDecimalNumber(value: $0).stringValue }
        }
        if let intValues = try? container.decode([Int].self, forKey: .denominations), !intValues.isEmpty {
            return intValues.map(String.init)
        }

        // Some responses use denominationValues instead of denominations.
        if let stringValues = try? container.decode([String].self, forKey: .denominationValues), !stringValues.isEmpty {
            return stringValues
        }
        if let doubleValues = try? container.decode([Double].self, forKey: .denominationValues), !doubleValues.isEmpty {
            return doubleValues.map { NSDecimalNumber(value: $0).stringValue }
        }
        if let intValues = try? container.decode([Int].self, forKey: .denominationValues), !intValues.isEmpty {
            return intValues.map(String.init)
        }

        return []
    }

    // Computed property to get discount value from either field
    var discount: Int {
        return savingsPercentage ?? userDiscount ?? 0
    }

    // Computed property to get location count from either field
    var locationCountValue: Int {
        return cachedLocationCount ?? locationCount ?? 0
    }

    var minimumCardPurchase: Double {
        guard denominations.count >= 1, let min = Double(denominations[0]) else { return 0.0 }
        return min
    }

    var maximumCardPurchase: Double {
        guard denominations.count >= 2, let max = Double(denominations[1]) else { return 0.0 }
        return max
    }

    var denominationType: DenominationType {
        switch denominationsType {
        case "min-max":
            return .Range
        default:
            return .Fixed
        }
    }
}

struct MerchantInfo: Codable {
    let terms: String
    let description: String
    let instructions: String
    let intro: String
}

enum DenominationType: String, Codable {
    case Range = "min-max"
    case Fixed = "fixed"
} 

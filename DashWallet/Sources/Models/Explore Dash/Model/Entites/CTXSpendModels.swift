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
    let id: String
    let status: String // unpaid, paid, fulfilled, rejected
    let barcodeUrl: String?
    let cardNumber: String?
    let cardPin: String?
    
    let cryptoAmount: String?
    let cryptoCurrency: String?
    let paymentCryptoNetwork: String
    let paymentId: String
    let percentDiscount: String
    let rate: String
    let redeemUrl: String?
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
        case redeemUrl
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

struct MerchantResponse: Codable {
    let id: String
    let name: String
    let logoUrl: String
    let enabled: Bool
    let savingsPercentage: Int
    let denominationsType: String
    let denominations: [String]
    let cachedLocationCount: Int
    let mapPinUrl: String
    let type: String
    let redeemType: String
    let info: MerchantInfo
    let cardImageUrl: String
    let currency: String
    
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
    case Range = "range"
    case Fixed = "fixed"
} 

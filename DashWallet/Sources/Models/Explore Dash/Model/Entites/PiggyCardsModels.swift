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

struct PiggyCardsSignupRequest: Codable {
    let firstName: String
    let lastName: String
    let email: String
    let country: String
    let state: String?
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case country
        case state
    }
}

struct PiggyCardsLoginRequest: Codable {
    let userId: String
    let password: String
}

struct PiggyCardsLoginResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct PiggyCardsVerifyOtpRequest: Codable {
    let email: String
    let otp: String
}

struct PiggyCardsVerifyOtpResponse: Codable {
    let generatedPassword: String
}

// MARK: - Order Models

public struct PiggyCardsOrderRequest: Codable {
    let orders: [PiggyCardsOrder]
    let recipientEmail: String
    let user: PiggyCardsUser

    enum CodingKeys: String, CodingKey {
        case orders
        case recipientEmail = "recipient_email"
        case user
    }
}

struct PiggyCardsOrder: Codable {
    let productId: Int
    let quantity: Int
    let denomination: Double
    let currency: String

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case quantity
        case denomination
        case currency
    }
}

struct PiggyCardsUser: Codable {
    let name: String
    let ip: String
    let metadata: PiggyCardsUserMetadata
}

struct PiggyCardsUserMetadata: Codable {
    let registeredSince: String
    let country: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case registeredSince = "registered_since"
        case country
        case state
    }
}

// Legacy purchase request (may need to be removed/replaced)
public struct PiggyCardsPurchaseRequest: Codable {
    let cryptoCurrency: String
    let fiatCurrency: String
    let fiatAmount: String
    let merchantId: String

    enum CodingKeys: String, CodingKey {
        case cryptoCurrency = "crypto_currency"
        case fiatCurrency = "fiat_currency"
        case fiatAmount = "fiat_amount"
        case merchantId = "merchant_id"
    }
}

// MARK: - Response Models

struct PiggyCardsSignupResponse: Codable {
    let userId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "userId"
    }
}

// MARK: - Order Response Models

struct PiggyCardsOrderResponse: Codable {
    let id: String
    let payTo: String
    let payMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case payTo = "pay_to"
        case payMessage = "pay_message"
    }
}

struct PiggyCardsOrderStatusResponse: Codable {
    let code: Int
    let message: String
    let data: PiggyCardsOrderData
}

struct PiggyCardsOrderData: Codable {
    let orderId: String
    let payTo: String?
    let deliveryTime: String?
    let status: String
    let cards: [PiggyCardsOrderGiftCard]

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case payTo = "pay_to"
        case deliveryTime = "delivery_time"
        case status
        case cards
    }
}

struct PiggyCardsOrderGiftCard: Codable {
    let name: String
    let claimCode: String?
    let claimPin: String?
    let barcodeLink: String?
    let cardStatus: String
    let claimLink: String?
    let answer: String?

    enum CodingKeys: String, CodingKey {
        case name
        case claimCode = "claim_code"
        case claimPin = "claim_pin"
        case barcodeLink = "barcode_link"
        case cardStatus = "card_status"
        case claimLink = "claim_link"
        case answer
    }
}

// MARK: - Brand Models

struct PiggyCardsBrand: Codable {
    let id: String
    let name: String
}

// MARK: - Gift Card Models

struct PiggyCardsGiftcardResponse: Codable {
    let code: Int
    let message: String
    let data: [PiggyCardsGiftcard]?
}

struct PiggyCardsGiftcard: Codable {
    let id: Int
    let name: String
    let description: String
    let image: String
    let priceType: String // "fixed", "range", or "option"
    let currency: String
    let discountPercentage: Double // Decimal (0.15 = 15%)
    let minDenomination: Double
    let maxDenomination: Double
    let denomination: String // For fixed: "25", for option: "25,50,100"
    let fee: Int
    let quantity: Int // Stock availability
    let brandId: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case image
        case priceType = "price_type"
        case currency
        case discountPercentage = "discount_percentage"
        case minDenomination = "min_denomination"
        case maxDenomination = "max_denomination"
        case denomination
        case fee
        case quantity
        case brandId = "brand_id"
    }
}

// MARK: - Exchange Rate Models

struct PiggyCardsExchangeRateResult: Codable {
    let currency: String
    let exchangeRate: Double // DASH per USD rate
    let dateModified: String

    enum CodingKeys: String, CodingKey {
        case currency
        case exchangeRate = "exchange_rate"
        case dateModified = "date_modified"
    }
}

// This model was incorrectly structured - gift cards are retrieved via order status

struct PiggyCardsMerchantResponse: Codable {
    let id: String
    let name: String
    let description: String?
    let logoUrl: String?
    let category: String?
    let minAmount: String?
    let maxAmount: String?
    let denominationType: String?
    let denominations: [String]?
    let currency: String
    let isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case logoUrl = "logo_url"
        case category
        case minAmount = "min_amount"
        case maxAmount = "max_amount"
        case denominationType = "denomination_type"
        case denominations
        case currency
        case isActive = "is_active"
    }
}

// MARK: - Domain Models

/// Unified gift card information for UI display
struct GiftCardInfo {
    let orderId: String
    let paymentAddress: String
    let amount: Double // Amount in DASH
    let merchantName: String
    let discountPercentage: Double // After service fee
    let exchangeRate: Double
    let status: String
}

// MARK: - Status Enums

enum GiftCardStatus: String {
    case unpaid
    case paid
    case fulfilled
    case rejected
}

enum PiggyCardsOrderStatus: String {
    case paymentPending = "Payment pending"
    case paid = "Paid"
    case processing = "Processing"
    case complete = "Complete"
    case cancelled = "Cancelled"

    var giftCardStatus: GiftCardStatus {
        switch self {
        case .paymentPending:
            return .unpaid
        case .paid, .processing:
            return .paid
        case .complete:
            return .fulfilled
        case .cancelled:
            return .rejected
        }
    }
}

enum PiggyCardsPriceType: String {
    case fixed = "fixed"
    case range = "range"
    case option = "option"
}

// MARK: - Error Models

struct PiggyCardsAPIError: Codable {
    let errors: [PiggyCardsAPIErrorDetail]
    let fields: [String: [String]]?
}

struct PiggyCardsAPIErrorDetail: Codable {
    let code: String
    let message: String
}

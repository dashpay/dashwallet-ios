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

struct PiggyCardsGiftCardResponse: Codable {
    let id: String
    let orderId: String
    let merchantId: String
    let merchantName: String
    let amount: String
    let currency: String
    let paymentUrl: String?
    let status: String
    let pin: String?
    let barcode: String?
    let expirationDate: String?
    let createdAt: String
    let txid: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case merchantId = "merchant_id"
        case merchantName = "merchant_name"
        case amount
        case currency
        case paymentUrl = "payment_url"
        case status
        case pin
        case barcode
        case expirationDate = "expiration_date"
        case createdAt = "created_at"
        case txid
    }
}

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

// MARK: - Error Models

struct PiggyCardsAPIError: Codable {
    let errors: [PiggyCardsAPIErrorDetail]
    let fields: [String: [String]]?
}

struct PiggyCardsAPIErrorDetail: Codable {
    let code: String
    let message: String
}

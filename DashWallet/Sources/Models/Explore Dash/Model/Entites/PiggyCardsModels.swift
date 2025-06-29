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
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case country
    }
}

struct PiggyCardsLoginRequest: Codable {
    let email: String
}

struct PiggyCardsVerifyOtpRequest: Codable {
    let email: String
    let otp: String
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
    let success: Bool
    let message: String?
    let userId: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case message
        case userId = "user_id"
    }
}

struct PiggyCardsAuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
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

enum PiggyCardsError: LocalizedError {
    case networkError
    case unauthorized
    case invalidCredentials
    case invalidOtp
    case tokenRefreshFailed
    case insufficientFunds
    case invalidMerchant
    case merchantUnavailable
    case invalidAmount
    case transactionRejected
    case purchaseLimitExceeded
    case purchaseLimitBelowMinimum
    case serverError
    case unknown
    case customError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return NSLocalizedString("Network connection error. Please try again.", comment: "")
        case .unauthorized:
            return NSLocalizedString("You need to log in to continue.", comment: "")
        case .invalidCredentials:
            return NSLocalizedString("Invalid email or password.", comment: "")
        case .invalidOtp:
            return NSLocalizedString("Invalid verification code. Please try again.", comment: "")
        case .tokenRefreshFailed:
            return NSLocalizedString("Your session expired. Please log in again.", comment: "")
        case .insufficientFunds:
            return NSLocalizedString("Insufficient funds for this purchase.", comment: "")
        case .invalidMerchant:
            return NSLocalizedString("This merchant is not available.", comment: "")
        case .merchantUnavailable:
            return NSLocalizedString("This merchant is temporarily unavailable.", comment: "")
        case .invalidAmount:
            return NSLocalizedString("Invalid purchase amount.", comment: "")
        case .transactionRejected:
            return NSLocalizedString("Transaction was rejected. Please try again.", comment: "")
        case .purchaseLimitExceeded:
            return NSLocalizedString("Purchase amount exceeds the limit for this gift card.", comment: "")
        case .purchaseLimitBelowMinimum:
            return NSLocalizedString("Purchase amount is below the minimum for this gift card.", comment: "")
        case .serverError:
            return NSLocalizedString("Server error. Please try again later.", comment: "")
        case .unknown:
            return NSLocalizedString("An unknown error occurred.", comment: "")
        case .customError(let message):
            return message
        }
    }
}

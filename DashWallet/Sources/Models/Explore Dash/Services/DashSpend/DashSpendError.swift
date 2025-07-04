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

enum DashSpendError: Error, LocalizedError {
    case networkError
    case parsingError
    case invalidCode
    case invalidCredentials
    case unauthorized
    case tokenRefreshFailed
    case insufficientFunds
    case invalidMerchant
    case invalidAmount
    case merchantUnavailable
    case transactionRejected
    case purchaseLimitExceeded
    case serverError
    case customError(String)
    case unknown
    case paymentProcessingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .networkError:
            return NSLocalizedString("Network error. Please check your connection and try again.", comment: "DashSpend")
        case .parsingError:
            return NSLocalizedString("Error processing server response. Please try again later.", comment: "DashSpend")
        case .invalidCode:
            return NSLocalizedString("Invalid verification code. Please try again.", comment: "CTXSpend error")
        case .invalidCredentials:
            return NSLocalizedString("Invalid email or password.", comment: "DashSpend")
        case .unauthorized:
            return NSLocalizedString("Please sign in to your DashSpend account.", comment: "DashSpend")
        case .tokenRefreshFailed:
            return NSLocalizedString("Your session expired", comment: "DashSpend")
        case .insufficientFunds:
            return NSLocalizedString("You do not have sufficient funds to complete this transaction", comment: "DashSpend")
        case .invalidMerchant:
            return NSLocalizedString("This merchant is currently unavailable.", comment: "DashSpend")
        case .invalidAmount:
            return NSLocalizedString("Invalid amount. Please check merchant limits.", comment: "DashSpend")
        case .merchantUnavailable:
            return NSLocalizedString("This merchant is currently unavailable. Please try again later or choose a different merchant.", comment: "DashSpend")
        case .transactionRejected:
            return NSLocalizedString("Your transaction was rejected. Please try again or contact support if the problem persists.", comment: "DashSpend")
        case .purchaseLimitExceeded:
            return NSLocalizedString("The purchase limits for this merchant have changed. Please contact CTX Support for more information.", comment: "DashSpend")
        case .serverError:
            return NSLocalizedString("Server error occurred. Please try again later.", comment: "DashSpend")
        case .customError(let message):
            return message
        case .unknown:
            return NSLocalizedString("An unknown error occurred. Please try again later.", comment: "DashSpend")
        case .paymentProcessingError(let details):
            return String(format: NSLocalizedString("Payment processing error: %@", comment: "DashSpend"), details)
        }
    }
}

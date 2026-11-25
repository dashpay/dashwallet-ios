//
//  Created by tkhp
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

extension Coinbase {
    /// A type representing an error value that can be thrown by Coinbase
    ///
    /// `Coinbase.Error` is the error type returned/throwned by Coinbase. It encompasses a few different types of errors, each with
    /// their own associated reasons.
    enum Error: Swift.Error, LocalizedError {
        enum GeneralFailureReason: LocalizedError {
            case noActiveUser
            case revokedToken
            case noPaymentMethods
            case noCashAccount
            case rateNotFound
            case depositFailed

            var errorDescription: String? {
                switch self {
                case .noActiveUser:
                    return String(localized: "No active user", comment: "Coinbase")
                case .revokedToken:
                    return String(localized: "For your security, you have been signed out.", comment: "Coinbase")
                case .noPaymentMethods:
                    return String(localized: "Please add a payment method on Coinbase", comment: "Coinbase/Buy Dash")
                case .noCashAccount:
                    return String(localized: "No cash account found", comment: "Coinbase")
                case .rateNotFound:
                    return String(localized: "Could not find exchange rate.", comment: "")
                case .depositFailed:
                    return String(localized: "Couldn't complete the transfer", comment: "Coinbase")
                }
            }
            
            var failureReason: String? {
                switch self {
                case .noPaymentMethods:
                    return String(localized: "No payment methods found", comment: "Coinbase/Buy Dash")
                default:
                    return ""
                }
            }
            
            var recoverySuggestion: String? {
                switch self {
                case .noPaymentMethods:
                    return String(localized: "Add", comment: "Coinbase/Buy Dash")
                default:
                    return ""
                }
            }
        }

        enum AuthFailureReason: LocalizedError {
            case failedToStartAuthSession
            case failedToRetrieveCode

            var errorDescription: String? {
                switch self {
                case .failedToStartAuthSession:
                    return String(localized: "Failed to start auth session", comment: "Coinbase")
                case .failedToRetrieveCode:
                    return String(localized: "oAuth failed", comment: "Coinbase")
                }
            }
        }

        enum TransactionFailureReason: LocalizedError, Identifiable, Equatable {
            static func == (lhs: Coinbase.Error.TransactionFailureReason, rhs: Coinbase.Error.TransactionFailureReason) -> Bool {
                lhs.id == rhs.id
            }

            var id: Int {
                switch self {
                case .failedToObtainNewAddress:
                    return 0
                case .twoFactorRequired:
                    return 1
                case .invalidVerificationCode:
                    return 2
                case .notEnoughFunds:
                    return 3
                case .enteredAmountTooLow:
                    return 4
                case .limitExceded:
                    return 5
                case .unknown:
                    return 6
                case .message:
                    return 7
                case .invalidAmount:
                    return 8
                }
            }

            case invalidAmount
            case failedToObtainNewAddress
            case twoFactorRequired(idem: UUID)
            case invalidVerificationCode
            case notEnoughFunds
            case enteredAmountTooLow(minimumAmount: String)
            case limitExceded
            case unknown(any Swift.Error)
            case message(String)

            var errorDescription: String? {
                switch self {
                case .invalidAmount:
                    let amountString = CoreTxConstants.minOutputAmount.formattedDashAmount
                    return String(localized: "Dash payments can't be less than \(amountString)", comment: "Coinbase")
                case .failedToObtainNewAddress:
                    return String(localized: "There was an error while obtaining new address", comment: "Coinbase")
                case .twoFactorRequired:
                    return String(localized: "Two factor auth required", comment: "Coinbase")
                case .invalidVerificationCode:
                    return String(localized: "The code is incorrect. Please check and try again!", comment: "Coinbase")
                case .notEnoughFunds:
                    return String(localized: "Insufficient funds", comment: "Coinbase")
                case .enteredAmountTooLow(let minAmount):
                    return String(localized: "The minimum amount you can send is \(minAmount)", comment: "Coinbase")
                case .limitExceded:
                    return String(localized: "You exceeded the authorization limit on Coinbase.", comment: "Coinbase")
                case .unknown:
                    return String(localized: "There was an error, please try again later", comment: "Coinbase")
                case .message(let msg):
                    return msg
                }
            }
        }

        case userSessionRevoked
        case general(GeneralFailureReason)
        case authFailed(AuthFailureReason)
        case transactionFailed(TransactionFailureReason)
        case unknownError

        var errorDescription: String? {
            switch self {
            case .userSessionRevoked:
                return String(localized: "For your security, you have been signed out.", comment: "Coinbase")
            case .general(let r):
                return r.localizedDescription
            case .authFailed(let r):
                return r.localizedDescription
            case .transactionFailed(let r):
                return r.localizedDescription
            case .unknownError:
                return String(localized: "Unknown", comment: "Coinbase")
            }
        }
    }
}

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

            var errorDescription: String? {
                switch self {
                case .noActiveUser:
                    return NSLocalizedString("No active user", comment: "Coinbase")
                }
            }
        }

        enum AuthFailureReason: LocalizedError {
            case failedToStartAuthSession
            case failedToRetrieveCode

            var errorDescription: String? {
                switch self {
                case .failedToStartAuthSession:
                    return NSLocalizedString("Failed to start auth session", comment: "Coinbase")
                case .failedToRetrieveCode:
                    return NSLocalizedString("oAuth failed", comment: "Coinbase")
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
                }
            }

            case failedToObtainNewAddress
            case twoFactorRequired
            case invalidVerificationCode
            case notEnoughFunds
            case enteredAmountTooLow
            case limitExceded
            case unknown(any Swift.Error)
            case message(String)

            var errorDescription: String? {
                switch self {
                case .failedToObtainNewAddress:
                    return NSLocalizedString("There was an error while obtaining new address", comment: "Coinbase")
                case .twoFactorRequired:
                    return NSLocalizedString("Two factor auth required", comment: "Coinbase")
                case .invalidVerificationCode:
                    return NSLocalizedString("The code is incorrect. Please check and try again!", comment: "Coinbase")
                case .notEnoughFunds:
                    return NSLocalizedString("Insufficient funds", comment: "Coinbase")
                case .enteredAmountTooLow:
                    let max = NSDecimalNumber(decimal: kMinUSDAmountOrder)
                    let localFormatter = DSPriceManager.sharedInstance().localFormat.copy() as! NumberFormatter
                    localFormatter.currencyCode = Coinbase.sendLimitCurrency
                    let str = localFormatter.string(from: max) ?? "$1.99"
                    return String(format: NSLocalizedString("Entered amount is too low. The minimum amount is %@", comment: "Coinbase"), str)
                case .limitExceded:
                    return NSLocalizedString("You exceeded the authorization limit on Coinbase.", comment: "Coinbase")
                case .unknown:
                    return NSLocalizedString("There was an error, please try again later", comment: "Coinbase")
                case .message(let msg):
                    return msg
                }
            }
        }

        case userSessionExpired
        case general(GeneralFailureReason)
        case authFailed(AuthFailureReason)
        case transactionFailed(TransactionFailureReason)
        case unknownError

        var errorDescription: String? {
            switch self {
            case .userSessionExpired:
                return NSLocalizedString("User session expired", comment: "Coinbase")
            case .general(let r):
                return r.localizedDescription
            case .authFailed(let r):
                return r.localizedDescription
            case .transactionFailed(let r):
                return r.localizedDescription
            case .unknownError:
                return NSLocalizedString("Unknown", comment: "Coinbase")
            }
        }
    }
}

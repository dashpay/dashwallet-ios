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
import Moya

enum CTXSpendError: Error, LocalizedError {
    case networkError
    case parsingError
    case invalidCode
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

final class CTXSpendAPI: HTTPClient<CTXSpendEndpoint> {
    weak var ctxSpendAPIAccessTokenProvider: CTXSpendTokenProvider!
    
    override func request(_ target: CTXSpendEndpoint) async throws {
        do {
            try checkAccessTokenIfNeeded(for: target)
            try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            try await handleUnauthorizedError(for: target)
            try await super.request(target)
        }
    }
    
    override func request<R>(_ target: CTXSpendEndpoint) async throws -> R where R: Decodable {
        do {
            try checkAccessTokenIfNeeded(for: target)
            return try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            try await handleUnauthorizedError(for: target)
            return try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 400 {
            if target.path.contains("/api/verify") {
                throw CTXSpendError.invalidCode
            }
            throw CTXSpendError.invalidAmount
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 409 {
            throw CTXSpendError.transactionRejected
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 422 {
            throw CTXSpendError.invalidAmount
        } catch HTTPClientError.statusCode(let r) where r.statusCode >= 500 {
            throw CTXSpendError.serverError
        } catch HTTPClientError.decoder {
            throw CTXSpendError.parsingError
        }
    }
    
    // Direct request method that bypasses refresh logic (used by token service)
    func requestDirectly<R>(_ target: CTXSpendEndpoint) async throws -> R where R: Decodable {
        return try await super.request(target)
    }
    
    func requestDirectly(_ target: CTXSpendEndpoint) async throws {
        try await super.request(target)
    }
    
    private func handleUnauthorizedError(for target: CTXSpendEndpoint) async throws {
        guard target.authorizationType == .bearer else {
            throw CTXSpendError.unauthorized
        }
        
        try await CTXSpendTokenService.shared.refreshAccessToken()
        
        // Update the access token provider after refresh
        accessTokenProvider = { [weak self] in
            self?.ctxSpendAPIAccessTokenProvider?.accessToken
        }
    }
    
    private func checkAccessTokenIfNeeded(for target: CTXSpendEndpoint) throws {
        guard target.authorizationType == .bearer else {
            return
        }
        
        guard let _ = accessTokenProvider?() else {
            throw CTXSpendError.unauthorized
        }
    }
    
    static var shared = CTXSpendAPI()
    
    static func initialize(with ctxSpendAPIAccessTokenProvider: CTXSpendTokenProvider) {
        shared.initialize(with: ctxSpendAPIAccessTokenProvider)
    }
    
    private func initialize(with ctxSpendAPIAccessTokenProvider: CTXSpendTokenProvider) {
        accessTokenProvider = { [weak ctxSpendAPIAccessTokenProvider] in
            ctxSpendAPIAccessTokenProvider!.accessToken
        }
        self.ctxSpendAPIAccessTokenProvider = ctxSpendAPIAccessTokenProvider
        
        // Configure the token service
        if let tokenProvider = ctxSpendAPIAccessTokenProvider as? CTXSpendTokenProvider {
            CTXSpendTokenService.shared.configure(with: tokenProvider)
        }
    }
} 

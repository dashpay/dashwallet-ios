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
                throw DashSpendError.invalidCode
            }
            throw DashSpendError.invalidAmount
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 409 {
            throw DashSpendError.transactionRejected
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 422 {
            throw DashSpendError.invalidAmount
        } catch HTTPClientError.statusCode(let r) where r.statusCode >= 500 {
            throw DashSpendError.serverError
        } catch HTTPClientError.decoder {
            throw DashSpendError.parsingError
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
            throw DashSpendError.unauthorized
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
            throw DashSpendError.unauthorized
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

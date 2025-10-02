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

final class PiggyCardsAPI: HTTPClient<PiggyCardsEndpoint> {
    override func request(_ target: PiggyCardsEndpoint) async throws {
        do {
            try checkAccessTokenIfNeeded(for: target)
            try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            try await handleUnauthorizedError(for: target)
            try await super.request(target)
        }
    }
    
    override func request<R>(_ target: PiggyCardsEndpoint) async throws -> R where R: Decodable {
        do {
            try checkAccessTokenIfNeeded(for: target)
            return try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            try await handleUnauthorizedError(for: target)
            return try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 400 {
            if target.path.contains("/verify-otp") {
                throw DashSpendError.invalidCode
            }
            
            throw HTTPClientError.statusCode(r)
        }
    }
    
    static let shared = PiggyCardsAPI()
    
    static func initialize() {
        shared.initialize()
    }
    
    private func initialize() {
        accessTokenProvider = {
            PiggyCardsTokenService.shared.accessToken
        }
    }
    
    private func handleUnauthorizedError(for target: PiggyCardsEndpoint) async throws {
        DSLogger.log("PiggyCards: Got 401, attempting to refresh access token")
        try await PiggyCardsTokenService.shared.refreshAccessToken()
    }
    
    private func checkAccessTokenIfNeeded(for target: PiggyCardsEndpoint) throws {
        switch target {
        case .signup, .login, .verifyOtp:
            return
        default:
            if PiggyCardsTokenService.shared.accessToken == nil {
                DSLogger.log("PiggyCards: No access token available for protected endpoint")
                throw DashSpendError.unauthorized
            }
        }
    }
}

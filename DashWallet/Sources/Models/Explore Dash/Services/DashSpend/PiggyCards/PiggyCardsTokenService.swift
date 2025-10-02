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

final class PiggyCardsTokenService {
    static let shared = PiggyCardsTokenService()
    private var isRefreshing = false
    
    var accessToken: String? {
        KeychainService.load(key: PiggyCardsRepository.Keys.accessToken)
    }
    
    func refreshAccessToken() async throws {
        guard !isRefreshing else {
            DSLogger.log("PiggyCards: Token refresh already in progress")
            return
        }
        
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if try await performAutoLogin() {
                DSLogger.log("PiggyCards: Successfully refreshed access token")
            } else {
                DSLogger.log("PiggyCards: Failed to refresh token, accessToken is empty")
                throw DashSpendError.tokenRefreshFailed
            }
        } catch {
            DSLogger.log("PiggyCards: Failed to refresh token: \(error)")
            throw DashSpendError.tokenRefreshFailed
        }
    }
    
    func performAutoLogin() async throws -> Bool {
        let userId = KeychainService.load(key: PiggyCardsRepository.Keys.userId)
        let password = KeychainService.load(key: PiggyCardsRepository.Keys.password)

        if let userId = userId, let password = password {
            let response: PiggyCardsLoginResponse = try await PiggyCardsAPI.shared.request(.login(userId: userId, password: password))
            KeychainService.save(key: PiggyCardsRepository.Keys.accessToken, data: response.accessToken)
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: PiggyCardsRepository.Keys.tokenExpiresAt)

            return !response.accessToken.isEmpty
        } else {
            return false
        }
    }
}

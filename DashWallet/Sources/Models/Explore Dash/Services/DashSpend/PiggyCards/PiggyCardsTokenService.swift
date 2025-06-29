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

protocol PiggyCardsTokenProvider: AnyObject {
    var accessToken: String? { get }
    var refreshToken: String? { get }
    func updateTokens(accessToken: String, refreshToken: String)
    func clearTokensOnRefreshFailure()
}

final class PiggyCardsTokenService {
    static let shared = PiggyCardsTokenService()
    private var isRefreshing = false
    
    weak var tokenProvider: PiggyCardsTokenProvider?
    
    private init() {
        self.tokenProvider = PiggyCardsRepository.shared
    }
    
    func refreshAccessToken() async throws {
        guard !isRefreshing else {
            DSLogger.log("PiggyCards: Token refresh already in progress")
            return
        }
        
        isRefreshing = true
        defer { isRefreshing = false }
        
        guard let refreshToken = tokenProvider?.refreshToken else {
            DSLogger.log("PiggyCards: No refresh token available")
            tokenProvider?.clearTokensOnRefreshFailure()
            throw PiggyCardsError.tokenRefreshFailed
        }
        
        do {
            let response: PiggyCardsAuthResponse = try await PiggyCardsAPI.shared.request(.refreshToken(refreshToken: refreshToken))
            
            tokenProvider?.updateTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken
            )
            
            DSLogger.log("PiggyCards: Successfully refreshed access token")
        } catch {
            DSLogger.log("PiggyCards: Failed to refresh token: \(error)")
            tokenProvider?.clearTokensOnRefreshFailure()
            throw PiggyCardsError.tokenRefreshFailed
        }
    }
}

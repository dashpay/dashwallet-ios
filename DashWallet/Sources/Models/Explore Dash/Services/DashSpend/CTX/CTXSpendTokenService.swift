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

protocol CTXSpendTokenProvider: AnyObject {
    var accessToken: String? { get }
    var refreshToken: String? { get }
    func updateTokens(accessToken: String, refreshToken: String)
    func clearTokensOnRefreshFailure()
}

// MARK: - CTXSpendTokenService

class CTXSpendTokenService {
    static let shared = CTXSpendTokenService()
    
    private var tokenRefreshTask: Task<Void, Error>?
    private weak var tokenProvider: CTXSpendTokenProvider?
    
    private init() {}
    
    func configure(with tokenProvider: CTXSpendTokenProvider) {
        self.tokenProvider = tokenProvider
    }
    
    func refreshAccessToken() async throws {
        // If there's already a refresh task running, wait for it
        if let task = tokenRefreshTask {
            try await task.value
            return
        }
        
        guard let tokenProvider = tokenProvider,
              let refreshToken = tokenProvider.refreshToken,
              !refreshToken.isEmpty else {
            return
        }
        
        tokenRefreshTask = Task {
            defer {
                tokenRefreshTask = nil
            }
            
            DSLogger.log("CTXSpend: Attempting to refresh access token")
            
            do {
                let request = RefreshTokenRequest(refreshToken: refreshToken)
                let response: RefreshTokenResponse = try await CTXSpendAPI.shared.requestDirectly(.refreshToken(request))
                
                // Update tokens through the service
                tokenProvider.updateTokens(accessToken: response.accessToken, refreshToken: response.refreshToken)
                
                DSLogger.log("CTXSpend: Token refresh successful")
            } catch {
                DSLogger.log("CTXSpend: Token refresh failed: \(error)")
                
                // Clear tokens on refresh failure
                tokenProvider.clearTokensOnRefreshFailure()
                
                throw DashSpendError.tokenRefreshFailed
            }
        }
        
        try await tokenRefreshTask!.value
    }
} 

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

    // Thread-safe token refresh using actor pattern
    private let tokenRefreshActor = TokenRefreshActor()

    var accessToken: String? {
        KeychainService.load(key: PiggyCardsRepository.Keys.accessToken)
    }

    /// Check if token is expired
    var isTokenExpired: Bool {
        guard let expiresAt = UserDefaults.standard.object(forKey: PiggyCardsRepository.Keys.tokenExpiresAt) as? TimeInterval else {
            return true // No expiration time means expired
        }
        let expirationDate = Date(timeIntervalSince1970: expiresAt)
        return Date() >= expirationDate
    }

    /// Thread-safe token refresh with automatic retry prevention
    func refreshAccessToken() async throws {
        // Use actor to ensure thread-safe, single refresh operation
        try await tokenRefreshActor.refreshToken { [weak self] in
            guard let self = self else { throw DashSpendError.tokenRefreshFailed }
            return try await self.performAutoLogin()
        }
    }
    
    func performAutoLogin() async throws -> Bool {
        let userId = KeychainService.load(key: PiggyCardsRepository.Keys.userId)
        let password = KeychainService.load(key: PiggyCardsRepository.Keys.password)

        if let userId = userId, let password = password {
            DSLogger.log("PiggyCards: Attempting auto-login for user \(userId)")
            let response: PiggyCardsLoginResponse = try await PiggyCardsAPI.shared.request(.login(userId: userId, password: password))
            KeychainService.save(key: PiggyCardsRepository.Keys.accessToken, data: response.accessToken)
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: PiggyCardsRepository.Keys.tokenExpiresAt)

            DSLogger.log("PiggyCards: Auto-login successful, token expires at \(expiresAt)")
            return !response.accessToken.isEmpty
        } else {
            DSLogger.log("PiggyCards: Auto-login failed - missing userId or password")
            return false
        }
    }

    /// Proactive token refresh before expiration
    func refreshTokenIfNeeded() async throws {
        if isTokenExpired {
            DSLogger.log("PiggyCards: Token expired, refreshing...")
            try await refreshAccessToken()
        } else {
            // Check if token will expire soon (within 5 minutes)
            guard let expiresAt = UserDefaults.standard.object(forKey: PiggyCardsRepository.Keys.tokenExpiresAt) as? TimeInterval else { return }
            let expirationDate = Date(timeIntervalSince1970: expiresAt)
            let timeUntilExpiration = expirationDate.timeIntervalSinceNow

            if timeUntilExpiration < 300 { // 5 minutes
                DSLogger.log("PiggyCards: Token expiring soon, proactively refreshing...")
                try await refreshAccessToken()
            }
        }
    }
}

// MARK: - Thread-Safe Token Refresh Actor

/// Actor ensures thread-safe token refresh operations
/// Prevents concurrent refresh attempts that could cause API rate limiting
private actor TokenRefreshActor {
    private var isRefreshing = false
    private var refreshTask: Task<Bool, Error>?

    func refreshToken(_ performRefresh: @escaping () async throws -> Bool) async throws {
        // If already refreshing, wait for the existing task
        if let existingTask = refreshTask {
            DSLogger.log("PiggyCards: Token refresh already in progress, waiting...")
            _ = try await existingTask.value
            return
        }

        // Start new refresh task
        refreshTask = Task {
            defer {
                refreshTask = nil
                isRefreshing = false
            }

            isRefreshing = true
            let success = try await performRefresh()

            if success {
                DSLogger.log("PiggyCards: Token refresh completed successfully")
            } else {
                DSLogger.log("PiggyCards: Token refresh failed")
                throw DashSpendError.tokenRefreshFailed
            }

            return success
        }

        _ = try await refreshTask!.value
    }
}

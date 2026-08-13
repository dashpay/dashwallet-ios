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
        try await tokenRefreshActor.refreshToken(label: "PiggyCards") { [weak self] in
            guard let self = self else { throw DashSpendError.tokenRefreshFailed }

            guard try await self.performAutoLogin() else {
                DWLogger.log("PiggyCards: Token refresh failed")
                throw DashSpendError.tokenRefreshFailed
            }

            DWLogger.log("PiggyCards: Token refresh completed successfully")
        }
    }
    
    func performAutoLogin() async throws -> Bool {
        let userId = KeychainService.load(key: PiggyCardsRepository.Keys.userId)
        let password = KeychainService.load(key: PiggyCardsRepository.Keys.password)

        if let userId = userId, let password = password {
            DWLogger.log("PiggyCards: Attempting auto-login for user \(userId)")
            let response: PiggyCardsLoginResponse = try await PiggyCardsAPI.shared.request(.login(userId: userId, password: password))
            KeychainService.save(key: PiggyCardsRepository.Keys.accessToken, data: response.accessToken)
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: PiggyCardsRepository.Keys.tokenExpiresAt)

            DWLogger.log("PiggyCards: Auto-login successful, token expires at \(expiresAt)")
            return !response.accessToken.isEmpty
        } else {
            DWLogger.log("PiggyCards: Auto-login failed - missing userId or password")
            return false
        }
    }

    /// Proactive token refresh before expiration
    func refreshTokenIfNeeded() async throws {
        if isTokenExpired {
            DWLogger.log("PiggyCards: Token expired, refreshing...")
            try await refreshAccessToken()
        } else {
            // Check if token will expire soon (within 5 minutes)
            guard let expiresAt = UserDefaults.standard.object(forKey: PiggyCardsRepository.Keys.tokenExpiresAt) as? TimeInterval else { return }
            let expirationDate = Date(timeIntervalSince1970: expiresAt)
            let timeUntilExpiration = expirationDate.timeIntervalSinceNow

            if timeUntilExpiration < 300 { // 5 minutes
                DWLogger.log("PiggyCards: Token expiring soon, proactively refreshing...")
                try await refreshAccessToken()
            }
        }
    }
}

// MARK: - Thread-Safe Token Refresh Actor

/// Serializes token refreshes for one service: concurrent callers join the
/// single in-flight attempt instead of each starting its own. Shared by every
/// token service that refreshes from more than one API call at a time —
/// PiggyCards, CTXSpend and Coinbase — because a plain stored `Task` property
/// on a non-isolated class is a data race there, and force-unwrapping it after
/// a competing caller's `defer` cleared it is a crash.
actor TokenRefreshActor {
    private var refreshTask: Task<Void, Error>?

    /// - Parameters:
    ///   - label: service name, used for the log line when a caller joins a
    ///     refresh that is already running.
    ///   - performRefresh: the refresh itself; throws to report failure.
    func refreshToken(label: String, _ performRefresh: @escaping () async throws -> Void) async throws {
        // If already refreshing, wait for the existing task
        if let existingTask = refreshTask {
            DWLogger.log("\(label): Token refresh already in progress, waiting...")
            try await existingTask.value
            return
        }

        // Start new refresh task
        let task = Task { try await performRefresh() }
        refreshTask = task

        do {
            try await task.value
            refreshTask = nil
        } catch {
            refreshTask = nil
            throw error
        }
    }
}

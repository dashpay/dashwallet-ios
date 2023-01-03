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

// MARK: - CBSecureTokenService

class CBSecureTokenService: Codable {
    private(set) var accessToken: String
    private(set) var refreshToken: String
    private(set) var accessTokenExpirationDate: Date

    private lazy var httpClient = HTTPClient<CoinbaseEndpoint>()
    private var tokenRefreshTask: Task<String, any Error>?

    init(accessToken: String, refreshToken: String, accessTokenExpirationDate: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpirationDate = accessTokenExpirationDate
    }

    var hasValidAccessToken: Bool {
        Date() < accessTokenExpirationDate
    }

    @discardableResult  func fetchAccessToken() async throws -> String {
        if let task = tokenRefreshTask {
            return try await task.value
        }

        if hasValidAccessToken &&
            accessTokenExpirationDate.timeIntervalSince1970 - Date().timeIntervalSince1970 > 300 {
            return accessToken
        }

        tokenRefreshTask = Task { [weak self] in
            defer {
                self?.tokenRefreshTask = nil
            }

            let result: CoinbaseTokenResponse = try await httpClient.request(.refreshToken(refreshToken: refreshToken))
            accessToken = result.accessToken
            refreshToken = result.refreshToken
            accessTokenExpirationDate = result.expirationDate
            return result.accessToken
        }

        return try await tokenRefreshTask!.value
    }

    func revokeAccessToken() async throws {
        try await httpClient.request(.revokeToken(token: accessToken))
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case accessTokenExpirationDate
    }
}

extension Task where Failure == Error {
    @discardableResult  static func retrying(priority: TaskPriority? = nil, maxRetryCount: Int = 3, retryDelay: TimeInterval = 1,
                                             operation: @Sendable @escaping () async throws -> Success) -> Task {
        Task(priority: priority) {
            for _ in 0..<maxRetryCount {
                do {
                    return try await operation()
                } catch {
                    let oneSecond = TimeInterval(1_000_000_000)
                    let delay = UInt64(oneSecond * retryDelay)
                    try await Task<Never, Never>.sleep(nanoseconds: delay)

                    continue
                }
            }

            try Task<Never, Never>.checkCancellation()
            return try await operation()
        }
    }
}

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

// MARK: - CoinbaseAPIAccessTokenProvider

protocol CoinbaseAPIAccessTokenProvider: AnyObject {
    var accessToken: String? { get }

    func refreshTokenIfNeeded() async throws
}

// MARK: - CoinbaseAPI

final class CoinbaseAPI: HTTPClient<CoinbaseEndpoint> {
    weak var coinbaseAPIAccessTokenProvider: CoinbaseAPIAccessTokenProvider!

    override func request(_ target: CoinbaseEndpoint) async throws {
        do {
            try checkAccessTokenIfNeeded(for: target)
            try await refreshTokenIfNeeded(for: target)
            try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            if let error = r.error?.errors.first,
               error.id == .invalidToken || error.id == .revokedToken || error.id == .invalidGrant {
                throw Coinbase.Error.userSessionRevoked
            }

            if let url = r.request?.url?.absoluteString, url == "https://api.coinbase.com/oauth/token" {
                throw Coinbase.Error.userSessionRevoked
            }

            throw HTTPClientError.statusCode(r)
        }
    }

    override func request<R>(_ target: CoinbaseEndpoint) async throws -> R where R : Decodable {
        do {
            try checkAccessTokenIfNeeded(for: target)
            try await refreshTokenIfNeeded(for: target)
            return try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            if let error = r.error?.errors.first,
               error.id == .invalidToken || error.id == .revokedToken || error.id == .invalidGrant {
                throw Coinbase.Error.userSessionRevoked
            }

            if let url = r.request?.url?.absoluteString, url == "https://api.coinbase.com/oauth/token" {
                throw Coinbase.Error.userSessionRevoked
            }

            throw HTTPClientError.statusCode(r)
        }
    }

    private func refreshTokenIfNeeded(for target: CoinbaseEndpoint) async throws {
        guard target.authorizationType != nil else {
            return
        }

        try await coinbaseAPIAccessTokenProvider.refreshTokenIfNeeded()
    }

    private func checkAccessTokenIfNeeded(for target: CoinbaseEndpoint) throws {
        guard target.authorizationType == .bearer else {
            return
        }

        guard let _ = accessTokenProvider?() else {
            throw Coinbase.Error.userSessionRevoked
        }
    }

    static var shared = CoinbaseAPI()

    static func initialize(with coinbaseAPIAccessTokenProvider: CoinbaseAPIAccessTokenProvider) {
        shared.initialize(with: coinbaseAPIAccessTokenProvider)
    }

    private func initialize(with coinbaseAPIAccessTokenProvider: CoinbaseAPIAccessTokenProvider) {
        accessTokenProvider = { [weak coinbaseAPIAccessTokenProvider] in coinbaseAPIAccessTokenProvider!.accessToken!
        }
        self.coinbaseAPIAccessTokenProvider = coinbaseAPIAccessTokenProvider
    }
}

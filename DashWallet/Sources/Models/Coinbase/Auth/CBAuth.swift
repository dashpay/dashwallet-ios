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

import AuthenticationServices
import Foundation

// MARK: - CBAuth

class CBAuth {
    public var currentUser: CBUser?

    private lazy var httpClient = HTTPClient<CoinbaseAPI>()
    private lazy var coinbaseService = CoinbaseService()
    private lazy var userManager = CBUserManager()

    private var tokenRefreshTask: Task<Void, any Error>?
    private var timer: Timer?

    @MainActor public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        let signInURL: URL = oAuth2URL
        let callbackURLScheme = Coinbase.callbackURLScheme

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Swift.Error>) in
            let authenticationSession = ASWebAuthenticationSession(url: signInURL,
                                                                   callbackURLScheme: callbackURLScheme) { callbackURL, error in
                guard error == nil,
                      let callbackURL,
                      let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: Coinbase.Error.failedToAuth)
                    return
                }

                continuation.resume(returning: code)
            }

            authenticationSession.presentationContextProvider = presentationContext
            authenticationSession.prefersEphemeralWebBrowserSession = true

            if !authenticationSession.start() {
                continuation.resume(throwing: Coinbase.Error.failedToStartAuthSession)
            }
        }

        let token = try await authorize(with: code)
        let account = try await fetchAccount()

        scheduleAutoTokenRefresh()
    }

    public func authorize(with code: String) async throws -> CoinbaseTokenResponse {
        try await httpClient.request(.getToken(code))
    }

    public func fetchAccount() async throws -> CoinbaseUserAccountData {
        let result: BaseDataResponse<CoinbaseUserAccountData> = try await httpClient.request(.userAccount)
        return result.data
    }

    private func refreshUserToken() async throws {
        guard let currentUser else {
            throw Coinbase.Error.noActiveUser
        }

        try await currentUser.refreshAccessToken()
    }

    public func signOut() async throws {
        Coinbase.accessToken = nil
        Coinbase.refreshToken = nil
        Coinbase.coinbaseUserAccountId = nil
        Coinbase.lastKnownBalance = nil
        // TODO: call appropriate api endpoint

        userManager.removeUser()
        timer?.invalidate()
        timer = nil
    }
}

// MARK: SecureTokenProvider

extension CBAuth: SecureTokenProvider {
    var accessToken: String? {
        currentUser?.accessToken
    }
}

extension CBAuth {
    private var oAuth2URL: URL {
        let path = CoinbaseAPI.signIn.path

        var queryItems = [
            URLQueryItem(name: "redirect_uri", value: Coinbase.redirectUri),
            URLQueryItem(name: "response_type", value: Coinbase.responseType),
            URLQueryItem(name: "scope", value: Coinbase.scope),
            URLQueryItem(name: "meta[send_limit_amount]", value: "\(Coinbase.send_limit_amount)"),
            URLQueryItem(name: "meta[send_limit_currency]", value: Coinbase.send_limit_currency),
            URLQueryItem(name: "meta[send_limit_period]", value: Coinbase.send_limit_period),
            URLQueryItem(name: "account", value: Coinbase.account),
        ]

        if let clientID = Coinbase.clientID as? String {
            queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        }

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "coinbase.com"
        urlComponents.path = path
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            fatalError("URL must be valid")
        }

        return url
    }

    private func save(user: CBUser?) -> Bool {
        if let user {
            return userManager.store(user: user)
        } else {
            return userManager.removeUser()
        }
    }

    private func scheduleAutoTokenRefresh() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
        }
    }

    private func tokenRefreshHandler() {
        tokenRefreshTask?.cancel()

        tokenRefreshTask = Task {
            try await refreshUserToken()
        }
    }
}

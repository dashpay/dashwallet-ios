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

    private var httpClient: CoinbaseAPI { CoinbaseAPI.shared }
    private lazy var userManager = CBUserManager()

    private var tokenRefreshTask: Task<Void, any Error>?
    private var timer: Timer?

    init() {
        currentUser = userManager.storedUser

        guard let currentUser else {
            return
        }

        tokenRefreshHandler()
        scheduleAutoTokenRefresh()
    }

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

        let tokenService = CBSecureTokenService(accessToken: token.accessToken, refreshToken: token.refreshToken, accessTokenExpirationDate: token.expirationDate)

        let user = CBUser(tokenService: tokenService)
        currentUser = user

        try await user.refreshAccount()

        save(user: user)

        scheduleAutoTokenRefresh()
    }

    public func authorize(with code: String) async throws -> CoinbaseTokenResponse {
        try await httpClient.request(.getToken(code))
    }

    private func refreshUserToken() async throws {
        guard let currentUser else {
            throw Coinbase.Error.noActiveUser
        }

        try await currentUser.refreshAccessToken()
    }

    private func refreshAccount() async throws {
        guard let currentUser else {
            throw Coinbase.Error.noActiveUser
        }

        try await currentUser.refreshAccount()
    }

    public func signOut() async throws {
        userManager.removeUser()
        timer?.invalidate()
        timer = nil

        try await currentUser?.revokeAccessToken()
        currentUser = nil
        save(user: nil)
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
        let path = CoinbaseEndpoint.signIn.path

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

    @discardableResult private func save(user: CBUser?) -> Bool {
        if let user {
            return userManager.store(user: user)
        } else {
            return userManager.removeUser()
        }
    }

    private func scheduleAutoTokenRefresh() {
        Timer.scheduledTimer(withTimeInterval: 60*60, repeats: true) { [weak self] _ in
            self?.tokenRefreshHandler()
        }
    }

    private func tokenRefreshHandler() {
        tokenRefreshTask?.cancel()

        tokenRefreshTask = Task {
            do {
                try await refreshUserToken()
                try await refreshAccount()
                save(user: currentUser)
            } catch {
                try await signOut()
            }
        }
    }
}

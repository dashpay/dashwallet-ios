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

extension Notification.Name {
    static let userDidChangeNotification: Notification.Name = .init(rawValue: "userDidChangeNotification")
}

typealias UserDidChangeListenerHandle = AnyObject
typealias UserDidChangeListenerBlock = (CBUser?) -> Void

// MARK: - CBAuth

class CBAuth {
    public var currentUser: CBUser? {
        didSet {
            if currentUser != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .userDidChangeNotification, object: self)
                }
            }
        }
    }

    private var httpClient: CoinbaseAPI { CoinbaseAPI.shared }
    private lazy var userManager = CBUserManager()

    private var listeners: [UserDidChangeListenerHandle] = []

    init() {
        currentUser = userManager.storedUser

        guard currentUser != nil else {
            return
        }

        Task {
            try await refreshUserToken()
        }
    }

    @MainActor
    public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        let signInURL: URL = oAuth2URL
        let callbackURLScheme = Coinbase.callbackURLScheme

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Swift.Error>) in
            let authenticationSession = ASWebAuthenticationSession(url: signInURL,
                                                                   callbackURLScheme: callbackURLScheme) { callbackURL, error in
                guard error == nil,
                      let callbackURL,
                      let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: Coinbase.Error.authFailed(.failedToRetrieveCode))
                    return
                }
                continuation.resume(returning: code)
            }

            authenticationSession.presentationContextProvider = presentationContext
            authenticationSession.prefersEphemeralWebBrowserSession = true

            if !authenticationSession.start() {
                continuation.resume(throwing: Coinbase.Error.authFailed(.failedToStartAuthSession))
            }
        }

        let token = try await authorize(with: code)
        let tokenService = CBSecureTokenService(accessToken: token.accessToken,
                                                refreshToken: token.refreshToken,
                                                accessTokenExpirationDate: token.expirationDate)

        let user = CBUser(tokenService: tokenService)
        currentUser = user
        save(user: user)
    }

    func authorize(with code: String) async throws -> CoinbaseTokenResponse {
        try await httpClient.request(.getToken(code))
    }

    public func signOut() async throws {
        guard let user = currentUser else { return }

        // Detach task to avoid waiting for a response
        Task.detached(priority: .background) {
            try? await user.revokeAccessToken()
        }

        currentUser = nil
        save(user: nil)
    }

    public func addUserDidChangeListener(_ listener: @escaping UserDidChangeListenerBlock) -> UserDidChangeListenerHandle {
        let handle = NotificationCenter.default.addObserver(forName: .userDidChangeNotification, object: self, queue: .main) { notification in
            guard let auth = notification.object as? CBAuth else { return }
            listener(auth.currentUser)
        }
        listeners.append(handle)

        DispatchQueue.main.async { [weak self] in
            listener(self?.currentUser)
        }
        return handle
    }

    public func removeUserDidChangeListener(handle: UserDidChangeListenerHandle) {
        listeners.removeAll(where: { $0 === handle })
    }
}

// MARK: SecureTokenProvider

extension CBAuth {
    var accessToken: String? {
        currentUser?.accessToken
    }
}

extension CBAuth {
    nonisolated
    private var oAuth2URL: URL {
        let path = CoinbaseEndpoint.signIn.path

        var queryItems = [
            URLQueryItem(name: "redirect_uri", value: Coinbase.redirectUri),
            URLQueryItem(name: "response_type", value: Coinbase.responseType),
            URLQueryItem(name: "scope", value: Coinbase.scope),
            URLQueryItem(name: "meta[send_limit_amount]", value: "\((Coinbase.sendLimitAmount as NSDecimalNumber).intValue)"),
            URLQueryItem(name: "meta[send_limit_currency]", value: Coinbase.sendLimitCurrency),
            URLQueryItem(name: "meta[send_limit_period]", value: Coinbase.sendLimitPeriod),
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

    func refreshUserToken() async throws {
        guard let currentUser else {
            throw Coinbase.Error.general(.noActiveUser)
        }

        do {
            try await currentUser.refreshAccessToken()
        } catch Coinbase.Error.userSessionRevoked {
            try await signOut()
        }
    }

    func refreshAccount() async throws {
        guard let currentUser else {
            throw Coinbase.Error.general(.noActiveUser)
        }

        try await currentUser.refreshUser()
        save(user: currentUser)
    }

    @discardableResult
    private func save(user: CBUser?) -> Bool {
        if let user {
            return userManager.store(user: user)
        } else {
            return userManager.removeUser()
        }
    }
}

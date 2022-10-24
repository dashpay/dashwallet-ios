//
//  TokenNetworkRequest.swift
//  Coinbase
//
//  Created by hadia on 20/06/2022.
//

import Foundation

struct NetworkRequest {
    // MARK: Private Constants
    static let callbackURLScheme = "authhub"
    static let clientSecret = Bundle.main.infoDictionary?["CLIENT_SECRET"]
    static let redirect_uri = "authhub://oauth-callback"
    static let clientID = Bundle.main.infoDictionary?["CLIENT_ID"]
    static let grant_type = "authorization_code"
    static let response_type = "code"
    static let scope = "wallet:accounts:read,wallet:user:read,wallet:payment-methods:read,wallet:buys:read,wallet:buys:create,wallet:transactions:transfer,wallet:transactions:request,wallet:transactions:read,wallet:supported-assets:read,wallet:sells:create,wallet:sells:read,wallet:transactions:send,wallet:addresses:read,wallet:addresses:create"
    static let send_limit_currency = "USD"
    static let send_limit_amount = 1
    static let send_limit_period = "month"
    static let account = "all"
    // MARK: Private Constants
    private static let accessTokenKey = "accessToken"
    private static let refreshTokenKey = "refreshToken"
    private static let coinbaseUserAccountIdKey = "coinbaseUserAccountId"
    
    
    // MARK: Properties
    static var coinbaseUserAccountId: String? {
        get {
            UserDefaults.standard.string(forKey: coinbaseUserAccountIdKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: coinbaseUserAccountIdKey)
        }
    }
    
    // MARK: Properties
    static var accessToken: String? {
        get {
            UserDefaults.standard.string(forKey: accessTokenKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: accessTokenKey)
        }
    }
    
    static var refreshToken: String? {
        get {
            UserDefaults.standard.string(forKey: refreshTokenKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: refreshTokenKey)
        }
    }

    
}

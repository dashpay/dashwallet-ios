//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

import Foundation
import Moya

struct AccessTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String
    let createdAt: Int64

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case createdAt = "created_at"
    }
}

struct ZenLedgerCreatePortfolioRequest: Codable {
    let portfolio: [ZenLedgerAddress]
}

struct ZenLedgerAddress: Codable {
    let blockchain: String
    let coin: String
    let address: String
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case blockchain
        case coin
        case address
        case displayName = "display_name"
    }
}

struct ZenLedgerCreatePortfolioResponse: Codable {
    let apiVersion: String
    let data: ResponseData

    private enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case data
    }
}

struct ResponseData: Codable {
    let signupUrl: String
    let aggcode: String

    private enum CodingKeys: String, CodingKey {
        case signupUrl = "signup_url"
        case aggcode
    }
}

enum ZenLedgerEndpoint {
    case getAccessToken(clientId: String, clientSecret: String)
    case createPortfolio(authToken: String, request: ZenLedgerCreatePortfolioRequest)
}

extension ZenLedgerEndpoint: TargetType {
    var baseURL: URL { return URL(string: "https://api.zenledger.io")! }

    var path: String {
        switch self {
        case .getAccessToken:
            return "/oauth/token"
        case .createPortfolio:
            return "/aggregators/api/v1/portfolios/"
        }
    }

    var method: Moya.Method {
        switch self {
        case .getAccessToken:
            return .post
        case .createPortfolio:
            return .post
        }
    }

    var task: Task {
        switch self {
        case let .getAccessToken(clientId, clientSecret):
            return .requestParameters(parameters: ["client_id": clientId, "client_secret": clientSecret, "grant_type": "client_credentials"], encoding: URLEncoding.httpBody)
        case let .createPortfolio(_, request):
            return .requestJSONEncodable(request)
        }
    }

    var headers: [String: String]? {
        switch self {
        case .getAccessToken:
            return ["Content-Type": "application/x-www-form-urlencoded"]
        case let .createPortfolio(authToken, _):
            return ["Authorization": "Bearer \(authToken)", "Content-Type": "application/json"]
        }
    }
}

class ZenLedger: HTTPClient<ZenLedgerEndpoint> {
    private var token: String? = nil
    
    private let clientSecret: String = {
        if let path = Bundle.main.path(forResource: "ZenLedger-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            return dict["CLIENT_SECRET"] as! String
        } else {
            return ""
        }
    }()

    private let clientID: String = {
        if let path = Bundle.main.path(forResource: "ZenLedger-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            return dict["CLIENT_ID"] as! String
        } else {
            return ""
        }
    }()
    
    private func getToken() async throws {
        let response: AccessTokenResponse = try await request(.getAccessToken(clientId: clientID, clientSecret: clientSecret))
        token = response.accessToken
    }
    
    func createPortfolio(addresses: [String]) async throws -> String? {
        if self.token == nil {
            try await getToken()
        }
        
        let response: ZenLedgerCreatePortfolioResponse = try await request(.createPortfolio(
            authToken: self.token!,
            request: ZenLedgerCreatePortfolioRequest(
                portfolio: addresses.map { address in
                    ZenLedgerAddress(
                        blockchain: kDashCurrency,
                        coin: kDashCurrency,
                        address: address,
                        displayName: kWalletName
                    )
                }
            ))
        )
        
        return response.data.signupUrl
    }
}

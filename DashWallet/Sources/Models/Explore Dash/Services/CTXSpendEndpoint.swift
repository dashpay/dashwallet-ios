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
import Moya

private let kBaseURL = URL(string: CTXConstants.baseURI)!

// MARK: - CTXSpendAPIError

struct CTXSpendAPIError: Decodable {
    struct Error: Swift.Error, LocalizedError, Decodable {
        let id: String?
        let message: String
        
        var errorDescription: String? {
            message
        }
    }
    
    struct FieldError: Decodable {
        let fiatAmount: [String]?
    }
    
    var errors: [Error]
    let fields: FieldError?
}

// MARK: - CTXSpendEndpoint

public enum CTXSpendEndpoint {
    case login(email: String)
    case verifyEmail(email: String, code: String)
    case refreshToken(RefreshTokenRequest)
    case purchaseGiftCard(PurchaseGiftCardRequest)
    case getMerchant(String)
    case getGiftCard(String)
}

// MARK: TargetType, AccessTokenAuthorizable

extension CTXSpendEndpoint: TargetType, AccessTokenAuthorizable {
    public var authorizationType: Moya.AuthorizationType? {
        switch self {
        case .login, .verifyEmail, .refreshToken:
            return nil
        default:
            return .bearer
        }
    }
    
    public var baseURL: URL {
        return kBaseURL
    }
    
    public var path: String {
        switch self {
        case .login: return "login"
        case .verifyEmail: return "verify-email"
        case .refreshToken: return "refresh-token"
        case .purchaseGiftCard: return "gift-cards"
        case .getMerchant(let merchantId): return "merchants/\(merchantId)"
        case .getGiftCard(let txid): return "gift-cards"
        }
    }
    
    public var method: Moya.Method {
        switch self {
        case .login, .verifyEmail, .refreshToken, .purchaseGiftCard:
            return .post
        default:
            return .get
        }
    }
    
    public var task: Moya.Task {
        switch self {
        case .login(let email):
            let loginRequest = LoginRequest(email: email)
            return .requestJSONEncodable(loginRequest)
        case .verifyEmail(let email, let code):
            let verifyRequest = VerifyEmailRequest(email: email, code: code)
            return .requestJSONEncodable(verifyRequest)
        case .refreshToken(let request):
            return .requestJSONEncodable(request)
        case .purchaseGiftCard(let request):
            return .requestJSONEncodable(request)
        default:
            return .requestPlain
        }
    }
    
    public var headers: [String: String]? {
        var headers = ["Content-Type": "application/json"]
        
        if let lang = Locale.current.languageCode {
            headers["Accept-Language"] = lang
        }
        
        return headers
    }
}

extension Moya.Response {
    var ctxError: CTXSpendAPIError? {
        let jsonDecoder = JSONDecoder()
        
        do {
            let result = try jsonDecoder.decode(CTXSpendAPIError.self, from: data)
            return result
        } catch {
            return nil
        }
    }
    
    var ctxErrorDescription: String? {
        guard let error = ctxError else { return nil }
        
        return String(describing: error.errors)
    }
} 

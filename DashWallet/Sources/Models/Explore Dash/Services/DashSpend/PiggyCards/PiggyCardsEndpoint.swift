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

private let kBaseURL = URL(string: PiggyCardsConstants.baseURI)!

// MARK: - PiggyCardsEndpoint

public enum PiggyCardsEndpoint {
    case signup(firstName: String, lastName: String, email: String, country: String, state: String?)
    case login(userId: String, password: String)
    case verifyOtp(email: String, otp: String)
    case purchaseGiftCard(PiggyCardsPurchaseRequest)
    case getMerchant(String)
    case getGiftCard(String)
}

// MARK: TargetType, AccessTokenAuthorizable

extension PiggyCardsEndpoint: TargetType, AccessTokenAuthorizable {
    public var authorizationType: Moya.AuthorizationType? {
        switch self {
        case .signup, .login, .verifyOtp:
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
        case .signup: return "signup"
        case .login: return "login"
        case .verifyOtp: return "verify-otp"
        case .purchaseGiftCard: return "orders"
        case .getMerchant(let merchantId): return "merchants/\(merchantId)"
        case .getGiftCard(let txid): return "gift-cards/\(txid)" // TODO: no such path
        }
    }
    
    public var method: Moya.Method {
        switch self {
        case .signup, .login, .verifyOtp, .purchaseGiftCard:
            return .post
        default:
            return .get
        }
    }
    
    public var task: Moya.Task {
        switch self {
        case .signup(let firstName, let lastName, let email, let country, let state):
            let signupRequest = PiggyCardsSignupRequest(firstName: firstName, lastName: lastName, email: email, country: country, state: state)
            return .requestJSONEncodable(signupRequest)
        case .login(let userId, let password):
            let loginRequest = PiggyCardsLoginRequest(userId: userId, password: password)
            return .requestJSONEncodable(loginRequest)
        case .verifyOtp(let email, let otp):
            let verifyRequest = PiggyCardsVerifyOtpRequest(email: email, otp: otp)
            return .requestJSONEncodable(verifyRequest)
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
    var piggyCardsError: PiggyCardsAPIError? {
        let jsonDecoder = JSONDecoder()
        
        do {
            let result = try jsonDecoder.decode(PiggyCardsAPIError.self, from: data)
            return result
        } catch {
            return nil
        }
    }
    
    var piggyCardsErrorDescription: String? {
        guard let error = piggyCardsError else { return nil }
        
        return String(describing: error.errors)
    }
}

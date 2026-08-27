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
    case getBrands(country: String)
    case getGiftCards(country: String, brandId: String)
    case createOrder(PiggyCardsOrderRequest)
    case getOrderStatus(orderId: String)
    case getExchangeRate(currency: String)
    case purchaseGiftCard(PiggyCardsPurchaseRequest) // Legacy - to be removed
    case getMerchant(String) // Legacy - to be removed
    case getGiftCard(String) // Legacy - doesn't exist in API
}

// MARK: TargetType, AccessTokenAuthorizable

extension PiggyCardsEndpoint: TargetType, AccessTokenAuthorizable {
    public var authorizationType: Moya.AuthorizationType? {
        switch self {
        case .signup, .login, .verifyOtp:
            return nil
        case .getBrands, .getGiftCards, .createOrder, .getOrderStatus, .getExchangeRate,
             .purchaseGiftCard, .getMerchant, .getGiftCard:
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
        case .getBrands(let country): return "brands/\(country)"
        case .getGiftCards(let country, _): return "giftcards/\(country)"
        case .createOrder: return "orders"
        case .getOrderStatus(let orderId): return "orders/\(orderId)"
        case .getExchangeRate: return "exchange-rate"
        case .purchaseGiftCard: return "orders" // Legacy
        case .getMerchant(let merchantId): return "merchants/\(merchantId)" // Legacy
        case .getGiftCard(let txid): return "gift-cards/\(txid)" // Doesn't exist
        }
    }
    
    public var method: Moya.Method {
        switch self {
        case .signup, .login, .verifyOtp, .createOrder, .purchaseGiftCard:
            return .post
        case .getBrands, .getGiftCards, .getOrderStatus, .getExchangeRate, .getMerchant, .getGiftCard:
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
        case .getGiftCards(_, let brandId):
            return .requestParameters(parameters: ["brandId": brandId], encoding: URLEncoding.queryString)
        case .createOrder(let request):
            return .requestJSONEncodable(request)
        case .getExchangeRate(let currency):
            return .requestParameters(parameters: ["currency": currency], encoding: URLEncoding.queryString)
        case .purchaseGiftCard(let request):
            return .requestJSONEncodable(request)
        case .getBrands, .getOrderStatus, .getMerchant, .getGiftCard:
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

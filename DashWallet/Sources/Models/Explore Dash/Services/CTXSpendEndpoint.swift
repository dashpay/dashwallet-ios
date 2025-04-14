import Foundation
import Moya

/// Base URL for CTXSpend API Endpoint
private let kBaseURL = URL(string: CTXConstants.baseURI)!

// MARK: - CTXSpendAPIError

struct CTXSpendAPIError: Decodable {
    struct Error: Swift.Error, LocalizedError, Decodable {
        let id: String?
        
        /// Human readable message.
        let message: String
        
        var errorDescription: String? {
            message
        }
    }
    
    var errors: [Error]
}

// MARK: - CTXSpendEndpoint

public enum CTXSpendEndpoint {
    case login(email: String)
    case verifyEmail(email: String, code: String)
    case purchaseGiftCard(PurchaseGiftCardRequest)
    case getMerchant(String)
    case getGiftCard(String)
}

// MARK: TargetType, AccessTokenAuthorizable

extension CTXSpendEndpoint: TargetType, AccessTokenAuthorizable {
    public var authorizationType: Moya.AuthorizationType? {
        switch self {
        case .login, .verifyEmail:
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
        case .purchaseGiftCard: return "gift-cards"
        case .getMerchant(let merchantId): return "merchants/\(merchantId)"
        case .getGiftCard(let txid): return "gift-cards"
        }
    }
    
    public var method: Moya.Method {
        switch self {
        case .login, .verifyEmail, .purchaseGiftCard:
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
        case .purchaseGiftCard(let request):
            return .requestJSONEncodable(request)
        default:
            return .requestPlain
        }
    }
    
    public var headers: [String: String]? {
        var headers = ["Content-Type": "application/json"]
        
        // Add localization header if needed
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

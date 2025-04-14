import Foundation
import Moya

enum CTXSpendError: Error {
    case networkError
    case parsingError
    case invalidCode
    case unauthorized
    case unknown
}

protocol CTXSpendAPIAccessTokenProvider: AnyObject {
    var accessToken: String? { get }
}

final class CTXSpendAPI: HTTPClient<CTXSpendEndpoint> {
    weak var ctxSpendAPIAccessTokenProvider: CTXSpendAPIAccessTokenProvider!
    
    override func request(_ target: CTXSpendEndpoint) async throws {
        do {
            try checkAccessTokenIfNeeded(for: target)
            try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            throw CTXSpendError.unauthorized
        }
    }
    
    override func request<R>(_ target: CTXSpendEndpoint) async throws -> R where R: Decodable {
        do {
            try checkAccessTokenIfNeeded(for: target)
            return try await super.request(target)
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 401 {
            throw CTXSpendError.unauthorized
        } catch HTTPClientError.statusCode(let r) where r.statusCode == 400 {
            if target.path.contains("/api/verify") {
                throw CTXSpendError.invalidCode
            }
            throw CTXSpendError.unknown
        } catch HTTPClientError.decoder {
            throw CTXSpendError.parsingError
        }
    }
    
    private func checkAccessTokenIfNeeded(for target: CTXSpendEndpoint) throws {
        guard target.authorizationType == .bearer else {
            return
        }
        
        guard let _ = accessTokenProvider?() else {
            throw CTXSpendError.unauthorized
        }
    }
    
    static var shared = CTXSpendAPI()
    
    static func initialize(with ctxSpendAPIAccessTokenProvider: CTXSpendAPIAccessTokenProvider) {
        shared.initialize(with: ctxSpendAPIAccessTokenProvider)
    }
    
    private func initialize(with ctxSpendAPIAccessTokenProvider: CTXSpendAPIAccessTokenProvider) {
        accessTokenProvider = { [weak ctxSpendAPIAccessTokenProvider] in
            ctxSpendAPIAccessTokenProvider!.accessToken
        }
        self.ctxSpendAPIAccessTokenProvider = ctxSpendAPIAccessTokenProvider
    }
} 
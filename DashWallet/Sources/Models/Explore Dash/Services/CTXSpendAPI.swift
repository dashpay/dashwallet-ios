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

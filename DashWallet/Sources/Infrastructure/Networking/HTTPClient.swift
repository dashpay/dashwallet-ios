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

import Foundation
import Moya

typealias CompletionHandler = (Swift.Result<Response, HTTPClientError>) -> ()

private let acceptableCodes = Array(200..<300)

private func JSONResponseDataFormatter(_ data: Data) -> String {
    do {
        let dataAsJSON = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: dataAsJSON, options: .prettyPrinted)
        return String(data: prettyData, encoding: .utf8) ?? String(data: data, encoding: .utf8) ?? ""
    } catch {
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - HTTPClientError

enum HTTPClientError: Error {
    case statusCode(Moya.Response)
    case mapping(Moya.Response)
    case moya(MoyaError)

    var localizedDescription: String {
        switch self {
        case .statusCode(let response):
            return "\(response.debugDescription)\nError: \(response.errorDescription ?? "")"
        case .mapping(let response):
            return "\(response.debugDescription)"
        case .moya(let error):
            return "\(String(describing: error.errorDescription))"
        }
    }
}

// MARK: - SecureTokenProvider

protocol SecureTokenProvider: AnyObject {
    var accessToken: String? { get }
}

// MARK: - HTTPClient

public class HTTPClient<Target: TargetType> {
    private let apiWorkQueue = DispatchQueue(label: "org.dashfoundation.dash.queue.api", qos: .background, attributes: .concurrent)
    private var provider: MoyaProvider<Target>!
    weak var secureTokenProvider: SecureTokenProvider?

    var accessToken: String? {
        secureTokenProvider?.accessToken
    }

    init(tokenProvider: SecureTokenProvider? = nil) {
        let config: NetworkLoggerPlugin.Configuration = .init(formatter: .init(responseData: JSONResponseDataFormatter),
                                                              logOptions: .verbose)
        let logger = NetworkLoggerPlugin(configuration: config)
        let accessTokenPlugin = AccessTokenPlugin { [weak self] _ in
            self?.accessToken ?? "" // TODO: Passing empty access token isn't good idea either
        }

        provider = MoyaProvider<Target>(plugins: [logger, accessTokenPlugin])
        secureTokenProvider = tokenProvider
    }

    @discardableResult func request(_ target: Target, completion: @escaping CompletionHandler) -> Cancellable {
        let cancellableToken = CancellableWrapper()
        cancellableToken.innerCancellable = _request(target, completion: completion)
        return cancellableToken
    }

    public func request(_ target: Target) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request(target) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func request<R: Decodable>(_ target: Target) async throws -> R {
        let r: R = try await withCheckedThrowingContinuation { continuation in
            request(target) { result in
                do {
                    let r: R = try result.decodeJSON()
                    continuation.resume(returning: r)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return r
    }
}

extension HTTPClient {
    @discardableResult private func _request(_ target: Target, completion: @escaping CompletionHandler) -> Cancellable {
        provider.request(target) { result in
            switch result {
            case .success(let response):
                #if DEBUG
                print(try? JSONSerialization.jsonObject(with: response.data, options: .allowFragments))
                #endif

                if acceptableCodes.contains(response.statusCode) {
                    completion(.success(response))
                } else {
                    let responseString = try? JSONSerialization.jsonObject(with: response.data, options: .allowFragments)
                    DSLogger.log("HTTPClient failure begin")
                    DSLogger.log("HTTPClient request: \(String(describing: response.request))")
                    DSLogger.log("HTTPClient response: \(String(describing: responseString))")
                    DSLogger.log("HTTPClient failure end")
                    completion(.failure(.statusCode(response)))
                }
            case .failure(let error):
                DSLogger.log("HTTPClient failure: \(String(describing: error))")
                completion(.failure(.moya(error)))
            }
        }
    }
}

// MARK: - CancellableWrapper

class CancellableWrapper: Moya.Cancellable {
    class SimpleCancellable: Moya.Cancellable {
        var isCancelled = false
        func cancel() {
            isCancelled = true
        }
    }

    internal var innerCancellable: Moya.Cancellable = SimpleCancellable()

    var isCancelled: Bool { innerCancellable.isCancelled }

    internal func cancel() {
        innerCancellable.cancel()
    }
}

private func JSONResponseDataFormatter(_ data: Data) -> Data {
    do {
        let dataAsJSON = try JSONSerialization.jsonObject(with: data)
        let prettyData = try JSONSerialization.data(withJSONObject: dataAsJSON, options: .prettyPrinted)
        return prettyData
    } catch {
        return data // fallback to original data if it can't be serialized.
    }
}

extension Swift.Result where Success: Moya.Response, Failure: Error {
    func decodeJSON<T: Decodable>() throws -> T {
        switch self {
        case .success(let r):
            let jsonDecoder = JSONDecoder()
            do {
                let result = try jsonDecoder.decode(T.self, from: r.data)
                return result
            } catch {
                throw HTTPClientError.mapping(r)
            }
        case .failure(let error):
            throw error
        }
    }
}

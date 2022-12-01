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
}


// MARK: - HTTPClient

public final class HTTPClient<Target: TargetType> {
    private let apiWorkQueue = DispatchQueue(label: "org.dashfoundation.dash.queue.api", qos: .utility, attributes: .concurrent)
    private let provider: MoyaProvider<Target>

    init() {
        let config: NetworkLoggerPlugin.Configuration = .init(formatter: .init(responseData: JSONResponseDataFormatter),
                                                              logOptions: .verbose)
        let logger = NetworkLoggerPlugin(configuration: config)
        provider = MoyaProvider<Target>(plugins: [logger])
    }

    @discardableResult func request(_ target: Target, completion: @escaping CompletionHandler) -> Cancellable {
        let cancellableToken = CancellableWrapper()

//        if target.needAuthToken {
//            refreshAuthTokenIfNeeded { [weak self] err in
//                if let error = err {
//                    DispatchQueue.main.async {
//                        completion(.failure(error))
//                    }
//
//                } else if let wSelf = self {
//                    DispatchQueue.main.async {
//                        cancellableToken.innerCancellable = wSelf._request(target, completion: completion)
//                    }
//                }
//            }
//        } else {
//            cancellableToken.innerCancellable = _request(target, completion: completion)
//        }

        cancellableToken.innerCancellable = _request(target, completion: completion)

        return cancellableToken
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
                    completion(.failure(.statusCode(response)))
                }
            case .failure(let error):
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
            // jsonDecoder.dateDecodingStrategy = .secondsSince1970
            // jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
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

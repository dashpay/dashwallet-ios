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

typealias AccessTokenProvider = () -> String?

// MARK: - HTTPClient

private let apiWorkQueue = DispatchQueue(label: "org.dashfoundation.dash.queue.api",
                                         attributes: .concurrent)
private let eTagReaderQueue = DispatchQueue(label: "org.dashfoundation.dash.queue.api.etag",
                                            target: apiWorkQueue)

// MARK: - HTTPClient

public class HTTPClient<Target: TargetType> {
    private var provider: MoyaProvider<Target>!
    private var etags: [String: String] = [:]

    var accessTokenProvider: AccessTokenProvider?

    private var receiveMemoryWarningHandler: Any!

    init(accessTokenProvider: AccessTokenProvider? = nil) {
        self.accessTokenProvider = accessTokenProvider

        let config: NetworkLoggerPlugin.Configuration = .init(formatter: .init(responseData: JSONResponseDataFormatter),
                                                              logOptions: .verbose)
        var plugins: [PluginType] = [NetworkLoggerPlugin(configuration: config)]
        let accessTokenPlugin = AccessTokenPlugin { [weak self] target in
            guard let self else { return "" }
            return self.retrieveAccessToken(for: target as! Target)
        }
        plugins.append(accessTokenPlugin)

        let etagPlugin = EtagPlugin { [weak self] _, url in
            guard let self else { return "" }
            return self.eTag(for: url)
        }
        plugins.append(etagPlugin)

        provider = MoyaProvider<Target>(plugins: plugins)

        receiveMemoryWarningHandler = NotificationCenter.default
            .addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                self?.etags = [:]
            }
    }

    @discardableResult
    func request(_ target: Target, completion: @escaping CompletionHandler) -> Cancellable {
        let cancellableToken = CancellableWrapper()

        apiWorkQueue.async {
            cancellableToken.innerCancellable = self._request(target, completion: completion)
        }

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

    private func retrieveAccessToken(for target: Target) -> String {
        if let target = target as? AccessTokenAuthorizable, target.authorizationType == .bearer,
           let provider = accessTokenProvider {
            return provider()! // Assume that we have token when we need it
        }

        fatalError("Token should be provided")
    }

    deinit {
        NotificationCenter.default.removeObserver(receiveMemoryWarningHandler!)
    }
}

extension HTTPClient {
    @discardableResult
    private func _request(_ target: Target, completion: @escaping CompletionHandler) -> Cancellable {
        provider.request(target, callbackQueue: apiWorkQueue) { [weak self] result in
            switch result {
            case .success(let response):
                #if DEBUG
                print(try? JSONSerialization.jsonObject(with: response.data, options: .allowFragments))
                #endif

                if acceptableCodes.contains(response.statusCode) {
                    if let etag = response.response?.value(forHTTPHeaderField: "Etag"),
                       let key = response.request?.url?.absoluteString {
                        eTagReaderQueue.sync {
                            self?.etags[key] = etag
                        }
                    }

                    completion(.success(response))
                } else {
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

// MARK: - EtagPlugin

public struct EtagPlugin: PluginType {

    public typealias EtagClosure = (_ target: TargetType, _ url: URL) -> String?

    /// A closure returning the etag to be applied in the header.
    public let etagClosure: EtagClosure

    /// Initialize a new `EtagPlugin`.
    ///
    /// - parameters:
    /// - etagClosure: A closure returning the etag to be applied in the pattern `Etag: tag`
    public init(etagClosure: @escaping EtagClosure) {
        self.etagClosure = etagClosure
    }

    /// Prepare a request by adding an authorization header if necessary.
    ///
    /// - parameters:
    /// - request: The request to modify.
    /// - target: The target of the request.
    /// - returns: The modified `URLRequest`.
    public func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        var request = request
        let realTarget = (target as? MultiTarget)?.target ?? target

        if let value = etagClosure(realTarget, request.url!) {
            request.addValue(value, forHTTPHeaderField: "Etag")
        }

        return request
    }
}

extension HTTPClient {
    func eTag(for url: URL) -> String? {
        eTagReaderQueue.sync {
            self.etags[url.absoluteString]
        }
    }
}

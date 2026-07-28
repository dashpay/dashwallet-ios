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
import Moya

private let upholdAccessTokenAccount = "DW_UPHOLD_ACCESS_TOKEN"

// MARK: - UpholdEndpoint

public enum UpholdEndpoint {
    case authorize(code: String)
    case getCapabilities(String)
    case getCards(accessToken: String)
    case createDashCard(accessToken: String)
    case createAddress(cardIdentifier: String, accessToken: String)
    case createTransaction(cardIdentifier: String, amount: String, address: String, otpToken: String?, accessToken: String)
    case commitTransaction(cardIdentifier: String, transactionIdentifier: String, otpToken: String?, accessToken: String)
    case revoke(accessToken: String)
}

// MARK: TargetType

extension UpholdEndpoint: TargetType, AccessTokenAuthorizable {
    public var authorizationType: Moya.AuthorizationType? {
        switch self {
        case .getCapabilities:
            return .bearer
        default:
            // Legacy DWUpholdClient supplies its in-memory token explicitly.
            // In particular, revoke must build its header before the keychain
            // item is deleted by the fire-and-forget logout path.
            return nil
        }
    }

    public var baseURL: URL {
        URL(string: DWUpholdConstants.baseURLString())!
    }

    public var path: String {
        switch self {
        case .authorize:
            return "oauth2/token"
        case .getCapabilities(let operation):
            return "v0/me/capabilities/\(operation)"
        case .getCards, .createDashCard:
            return "v0/me/cards"
        case .createAddress(let cardIdentifier, _):
            return "v0/me/cards/\(cardIdentifier)/addresses"
        case .createTransaction(let cardIdentifier, _, _, _, _):
            return "v0/me/cards/\(cardIdentifier)/transactions"
        case .commitTransaction(let cardIdentifier, let transactionIdentifier, _, _):
            return "v0/me/cards/\(cardIdentifier)/transactions/\(transactionIdentifier)/commit"
        case .revoke:
            return "oauth2/revoke"
        }
    }

    public var method: Moya.Method {
        switch self {
        case .getCapabilities, .getCards:
            return .get
        default:
            return .post
        }
    }

    public var task: Moya.Task {
        switch self {
        case .authorize(let code):
            return .requestParameters(parameters: [
                "code": code,
                "grant_type": "authorization_code",
            ], encoding: URLEncoding.httpBody)
        case .getCapabilities, .getCards, .commitTransaction:
            return .requestPlain
        case .createDashCard:
            return .requestParameters(parameters: [
                "label": "Dash Card",
                "currency": "DASH",
            ], encoding: JSONEncoding.default)
        case .createAddress:
            return .requestParameters(parameters: [
                "network": "dash",
            ], encoding: JSONEncoding.default)
        case .createTransaction(_, let amount, let address, _, _):
            return .requestParameters(parameters: [
                "denomination": [
                    "amount": amount.replacingOccurrences(of: ",", with: "."),
                    "currency": "DASH",
                ],
                "destination": address,
            ], encoding: JSONEncoding.default)
        case .revoke(let accessToken):
            return .requestParameters(parameters: [
                "token": accessToken,
            ], encoding: URLEncoding.httpBody)
        }
    }

    public var headers: [String: String]? {
        var headers: [String: String] = [:]

        switch self {
        case .authorize:
            let credentials = "\(DWUpholdConstants.clientID()):\(DWUpholdConstants.clientSecret())"
            headers["Authorization"] = "Basic \(Data(credentials.utf8).base64EncodedString())"
        case .getCapabilities:
            break
        case .getCards(let accessToken),
             .createDashCard(let accessToken),
             .createAddress(_, let accessToken),
             .createTransaction(_, _, _, _, let accessToken),
             .commitTransaction(_, _, _, let accessToken),
             .revoke(let accessToken):
            headers["Authorization"] = "Bearer \(accessToken)"
        }

        switch self {
        case .createTransaction(_, _, _, let otpToken, _),
             .commitTransaction(_, _, let otpToken, _):
            if let otpToken {
                headers["OTP-Token"] = otpToken
            }
        default:
            break
        }

        return headers
    }
}

// MARK: - UpholdClient

final class UpholdClient: HTTPClient<UpholdEndpoint> {
    init() {
        super.init(accessTokenProvider: {
            KeychainStore.string(account: upholdAccessTokenAccount)
        })
    }

    func getCapabilities(capability: String) async throws -> UpholdCapability? {
        try await request(.getCapabilities(capability))
    }
}

// MARK: - Objective-C compatibility boundary

@objc enum UpholdAPIResponseStatus: Int {
    case ok
    case otpRequired
    case otpInvalid
    case unauthorized
    case failed
}

@objc final class UpholdRequestCancellationToken: NSObject, DWUpholdClientCancellationToken {
    private let cancellable: Cancellable

    init(cancellable: Cancellable) {
        self.cancellable = cancellable
    }

    @objc func cancel() {
        cancellable.cancel()
    }
}

/// Transport adapter used by the existing Objective-C `DWUpholdClient`
/// facade. It deliberately returns Foundation JSON containers so legacy model
/// parsing and public callbacks stay unchanged while DashSync networking is
/// removed.
@objcMembers final class UpholdClientObjcBridge: NSObject {
    static let shared = UpholdClientObjcBridge()

    private let client = UpholdClient()

    private override init() {
        super.init()
    }

    @discardableResult
    @objc(authorizeWithCode:completion:)
    func authorize(code: String, completion: @escaping (String?) -> Void) -> UpholdRequestCancellationToken {
        perform(.authorize(code: code)) { object, _ in
            let response = object as? NSDictionary
            completion(response?["access_token"] as? String)
        }
    }

    @discardableResult
    @objc(getCardsWithAccessToken:completion:)
    func getCards(accessToken: String,
                  completion: @escaping (NSArray?, UpholdAPIResponseStatus) -> Void) -> UpholdRequestCancellationToken {
        perform(.getCards(accessToken: accessToken)) { object, status in
            completion(object as? NSArray, status)
        }
    }

    @discardableResult
    @objc(createDashCardWithAccessToken:completion:)
    func createDashCard(accessToken: String,
                        completion: @escaping (NSDictionary?, UpholdAPIResponseStatus) -> Void) -> UpholdRequestCancellationToken {
        perform(.createDashCard(accessToken: accessToken)) { object, status in
            completion(object as? NSDictionary, status)
        }
    }

    @discardableResult
    @objc(createAddressWithCardIdentifier:accessToken:completion:)
    func createAddress(cardIdentifier: String,
                       accessToken: String,
                       completion: @escaping (NSDictionary?, UpholdAPIResponseStatus) -> Void) -> UpholdRequestCancellationToken {
        perform(.createAddress(cardIdentifier: cardIdentifier, accessToken: accessToken)) { object, status in
            completion(object as? NSDictionary, status)
        }
    }

    @discardableResult
    @objc(createTransactionWithCardIdentifier:amount:address:otpToken:accessToken:completion:)
    func createTransaction(cardIdentifier: String,
                           amount: String,
                           address: String,
                           otpToken: String?,
                           accessToken: String,
                           completion: @escaping (NSDictionary?, UpholdAPIResponseStatus) -> Void) -> UpholdRequestCancellationToken {
        perform(.createTransaction(cardIdentifier: cardIdentifier,
                                   amount: amount,
                                   address: address,
                                   otpToken: otpToken,
                                   accessToken: accessToken)) { object, status in
            completion(object as? NSDictionary, status)
        }
    }

    @discardableResult
    @objc(commitTransactionWithCardIdentifier:transactionIdentifier:otpToken:accessToken:completion:)
    func commitTransaction(cardIdentifier: String,
                           transactionIdentifier: String,
                           otpToken: String?,
                           accessToken: String,
                           completion: @escaping (NSDictionary?, UpholdAPIResponseStatus) -> Void) -> UpholdRequestCancellationToken {
        perform(.commitTransaction(cardIdentifier: cardIdentifier,
                                   transactionIdentifier: transactionIdentifier,
                                   otpToken: otpToken,
                                   accessToken: accessToken)) { object, status in
            completion(object as? NSDictionary, status)
        }
    }

    @discardableResult
    @objc(revokeWithAccessToken:)
    func revoke(accessToken: String) -> UpholdRequestCancellationToken {
        perform(.revoke(accessToken: accessToken)) { _, _ in }
    }

    private func perform(_ endpoint: UpholdEndpoint,
                         completion: @escaping (Any?, UpholdAPIResponseStatus) -> Void) -> UpholdRequestCancellationToken {
        let cancellable = client.request(endpoint) { result in
            let response: Moya.Response
            switch result {
            case .success(let successfulResponse):
                response = successfulResponse
            case .failure(.statusCode(let failedResponse)):
                response = failedResponse
            case .failure(let error):
                guard !Self.isCancellation(error) else { return }
                DispatchQueue.main.async {
                    completion(nil, .failed)
                }
                return
            }

            let object = try? JSONSerialization.jsonObject(with: response.data, options: .allowFragments)
            let status = Self.status(for: response, object: object)
            DispatchQueue.main.async {
                completion(object, status)
            }
        }
        return UpholdRequestCancellationToken(cancellable: cancellable)
    }

    private static func status(for response: Moya.Response, object: Any?) -> UpholdAPIResponseStatus {
        // DashSync's legacy loader accepted the inclusive 200...300 range.
        if (200...300).contains(response.statusCode) {
            return .ok
        }

        guard response.statusCode == 401 else {
            return .failed
        }

        let responseDictionary = object as? NSDictionary
        let errors = responseDictionary?["errors"] as? NSDictionary
        let hasOTPError = errors?["token"] != nil
        let otpRequiredHeader = response.response?.value(forHTTPHeaderField: "OTP-Token")
        let otpRequired = otpRequiredHeader?.caseInsensitiveCompare("required") == .orderedSame || hasOTPError

        if otpRequired {
            return .otpRequired
        }
        if response.response?.value(forHTTPHeaderField: "otp-method-id") != nil {
            return .otpInvalid
        }
        return .unauthorized
    }

    private static func isCancellation(_ error: HTTPClientError) -> Bool {
        guard case .moya(let moyaError) = error,
              case .underlying(let underlyingError, _) = moyaError else {
            return false
        }

        let nsError = underlyingError as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

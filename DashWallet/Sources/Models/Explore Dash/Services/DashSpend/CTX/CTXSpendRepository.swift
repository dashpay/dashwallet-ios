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
import Combine


class CTXSpendRepository: CTXSpendTokenProvider, DashSpendRepository {
    public static let shared: CTXSpendRepository = .init()
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let accessToken = "ctx_spend_access_token"
        static let refreshToken = "ctx_spend_refresh_token"
        static let email = "ctx_spend_email"
        static let deviceUUID = "ctx_spend_device_uuid"
    }
    
    var accessToken: String? {
        return KeychainService.load(key: Keys.accessToken)
    }
    
    var refreshToken: String? {
        return KeychainService.load(key: Keys.refreshToken)
    }
    
    @Published private(set) var userEmail: String? = nil
    @Published private(set) var isUserSignedIn = false
    
    var userEmailPublisher: AnyPublisher<String?, Never> {
        $userEmail.eraseToAnyPublisher()
    }
    
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> {
        $isUserSignedIn.eraseToAnyPublisher()
    }
    
    init() {
        CTXSpendAPI.initialize(with: self)
        updateSignInState()
        updateEmailState()
    }
    
    private func updateSignInState() {
        let token = accessToken
        isUserSignedIn = token != nil && !token!.isEmpty
    }
    
    private func updateEmailState() {
        userEmail = KeychainService.load(key: Keys.email)
    }
    
    func login(email: String) async throws -> Bool {
        return try await signUp(email: email)
    }
    
    func signUp(email: String) async throws -> Bool {
        do {
            try await CTXSpendAPI.shared.request(.login(email: email))
            KeychainService.save(key: Keys.email, data: email)
            updateEmailState()
            
            if userDefaults.string(forKey: Keys.deviceUUID) == nil {
                userDefaults.set(UUID().uuidString, forKey: Keys.deviceUUID)
            }
            
            return true
        } catch {
            throw mapError(error)
        }
    }
    
    func verifyEmail(code: String) async throws -> Bool {
        guard let email = userEmail else {
            DSLogger.log("CTX: email is missing while trying to verify")
            throw DashSpendError.unknown
        }
        
        do {
            let response: VerifyEmailResponse = try await CTXSpendAPI.shared.request(.verifyEmail(email: email, code: code))
            
            KeychainService.save(key: Keys.accessToken, data: response.accessToken)
            KeychainService.save(key: Keys.refreshToken, data: response.refreshToken)
            updateSignInState()
            
            return true
        } catch {
            throw mapError(error)
        }
    }
    
    func logout() {
        KeychainService.delete(key: Keys.accessToken)
        KeychainService.delete(key: Keys.refreshToken)
        KeychainService.delete(key: Keys.email)
        userDefaults.removeObject(forKey: Keys.deviceUUID)
        updateSignInState()
        updateEmailState()
    }
    
    // MARK: - Token Management
    
    func updateTokens(accessToken: String, refreshToken: String) {
        KeychainService.save(key: Keys.accessToken, data: accessToken)
        KeychainService.save(key: Keys.refreshToken, data: refreshToken)
        updateSignInState()
    }
    
    func clearTokensOnRefreshFailure() {
        KeychainService.delete(key: Keys.accessToken)
        KeychainService.delete(key: Keys.refreshToken)
        updateSignInState()
    }
    
    func refreshToken() async throws {
        try await CTXSpendTokenService.shared.refreshAccessToken()
    }
    
    // MARK: - Gift Card Methods
    
    func purchaseGiftCard(merchantId: String, fiatAmount: String, fiatCurrency: String = "USD", cryptoCurrency: String = "DASH") async throws -> GiftCardResponse {
        let request = PurchaseGiftCardRequest(
            cryptoCurrency: cryptoCurrency,
            fiatCurrency: fiatCurrency,
            fiatAmount: fiatAmount,
            merchantId: merchantId
        )

        DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - Request:")
        DSLogger.log("🔍   merchantId: \(merchantId)")
        DSLogger.log("🔍   fiatAmount: \(fiatAmount)")
        DSLogger.log("🔍   fiatCurrency: \(fiatCurrency)")
        DSLogger.log("🔍   cryptoCurrency: \(cryptoCurrency)")

        do {
            let response: GiftCardResponse = try await CTXSpendAPI.shared.request(.purchaseGiftCard(request))

            DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - Success Response:")
            DSLogger.log("🔍   id: \(response.id)")
            DSLogger.log("🔍   status: \(response.status)")
            DSLogger.log("🔍   paymentId: \(response.paymentId)")
            DSLogger.log("🔍   paymentUrls: \(response.paymentUrls ?? [:])")

            return response
        } catch let error as DashSpendError {
            DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - Failed with CTXSpendError: \(error)")
            throw error
        } catch let error as HTTPClientError {
            DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - Failed with HTTPClientError: \(error)")

            if case .statusCode(let response) = error {
                DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - HTTP Status: \(response.statusCode)")
                DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - Raw Response Data:")
                if let responseString = String(data: response.data, encoding: .utf8) {
                    DSLogger.log("🔍   Response body: \(responseString)")
                } else {
                    DSLogger.log("🔍   Response data (hex): \(response.data.hexEncodedString())")
                }
                switch response.statusCode {
                case 400:
                    if let errorData = try? JSONDecoder().decode(CTXSpendAPIError.self, from: response.data) {
                        // Check for limit errors first
                        if let fiatAmountErrors = errorData.fields?.fiatAmount,
                           let firstFiatError = fiatAmountErrors.first {
                            if firstFiatError == "above threshold" || firstFiatError == "below threshold" {
                                throw DashSpendError.purchaseLimitExceeded
                            }
                        }

                        if let firstError = errorData.errors.first {
                            // Look for specific error messages
                            let errorMessage = firstError.message.lowercased()

                            if errorMessage.contains("insufficient") || errorMessage.contains("funds") || errorMessage.contains("balance") {
                                throw DashSpendError.insufficientFunds
                            } else if errorMessage.contains("merchant") && (errorMessage.contains("unavailable") || errorMessage.contains("disabled") || errorMessage.contains("suspended")) {
                                throw DashSpendError.merchantUnavailable
                            } else if errorMessage.contains("merchant") {
                                throw DashSpendError.invalidMerchant
                            } else if errorMessage.contains("rejected") || errorMessage.contains("declined") {
                                throw DashSpendError.transactionRejected
                            } else if errorMessage.contains("amount") || errorMessage.contains("value") || errorMessage.contains("limit") {
                                throw DashSpendError.invalidAmount
                            }

                            // Custom error with the actual message from API
                            throw DashSpendError.customError(firstError.message)
                        }
                    }
                case 401, 403:
                    throw DashSpendError.unauthorized
                case 404:
                    throw DashSpendError.invalidMerchant
                case 409:
                    throw DashSpendError.transactionRejected
                case 422:
                    throw DashSpendError.invalidAmount
                case 500...599:
                    throw DashSpendError.serverError
                default:
                    break
                }
            }

            throw DashSpendError.unknown
        } catch let decodingError as DecodingError {
            DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - JSON Decoding Error: \(decodingError)")
            switch decodingError {
            case .dataCorrupted(let context):
                DSLogger.log("🔍   Data corrupted: \(context)")
            case .keyNotFound(let key, let context):
                DSLogger.log("🔍   Key not found: \(key), context: \(context)")
            case .typeMismatch(let type, let context):
                DSLogger.log("🔍   Type mismatch: \(type), context: \(context)")
            case .valueNotFound(let type, let context):
                DSLogger.log("🔍   Value not found: \(type), context: \(context)")
            @unknown default:
                DSLogger.log("🔍   Unknown decoding error")
            }
            throw DashSpendError.parsingError
        } catch {
            DSLogger.log("🔍 CTXSpendRepository.purchaseGiftCard - Unknown error: \(error)")
            throw DashSpendError.networkError
        }
    }
    
    func getMerchant(merchantId: String) async throws -> MerchantResponse {
        do {
            let response: MerchantResponse = try await CTXSpendAPI.shared.request(.getMerchant(merchantId))

            // DEBUG: Log the parsed response
            DSLogger.log("🔍 CTXSpendRepository.getMerchant - Response for \(merchantId):")
            DSLogger.log("🔍   name: \(response.name)")
            DSLogger.log("🔍   denominationsType: \(response.denominationsType)")
            DSLogger.log("🔍   denominations array: \(response.denominations)")
            DSLogger.log("🔍   denominations count: \(response.denominations.count)")
            if response.denominations.count > 0 {
                DSLogger.log("🔍   First denomination: \(response.denominations[0])")
            }
            if response.denominations.count > 1 {
                DSLogger.log("🔍   Second denomination: \(response.denominations[1])")
            }
            DSLogger.log("🔍   Computed minimumCardPurchase: \(response.minimumCardPurchase)")
            DSLogger.log("🔍   Computed maximumCardPurchase: \(response.maximumCardPurchase)")

            return response
        } catch let error as DashSpendError {
            DSLogger.log("Failed to get merchant with CTXSpendError: \(error)")
            throw error
        } catch let error as HTTPClientError {
            DSLogger.log("Failed to get merchant with HTTPClientError: \(error)")
            
            if case .statusCode(let response) = error {
                switch response.statusCode {
                case 401, 403:
                    throw DashSpendError.unauthorized
                case 404:
                    throw DashSpendError.invalidMerchant
                case 500...599:
                    throw DashSpendError.networkError
                default:
                    break
                }
            }
            
            throw DashSpendError.unknown
        } catch {
            DSLogger.log("Failed to get merchant with error: \(error)")
            throw DashSpendError.networkError
        }
    }
    
    func getGiftCardByTxid(txid: String) async throws -> GiftCardResponse {
        do {
            return try await CTXSpendAPI.shared.request(.getGiftCard(txid))
        } catch {
            throw mapError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapError(_ error: Error) -> Error {
        if let ctxError = error as? DashSpendError {
            return ctxError
        }
        
        return DashSpendError.networkError
    }
}

// MARK: - KeychainService

public class KeychainService {
    static func save(key: String, data: String) {
        if let dataToStore = data.data(using: .utf8) {
            let query = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: dataToStore
            ] as [String: Any]
            
            SecItemDelete(query as CFDictionary)
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    
    static func load(key: String) -> String? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == noErr {
            if let data = result as? Data,
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        
        return nil
    }
    
    static func delete(key: String) {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ] as [String: Any]
        
        SecItemDelete(query as CFDictionary)
    }
} 

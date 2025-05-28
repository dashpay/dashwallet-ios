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

class CTXSpendService: CTXSpendAPIAccessTokenProvider, CTXSpendTokenProvider, ObservableObject {
    public static let shared: CTXSpendService = .init()
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
    
    var userEmail: String? {
        KeychainService.load(key: Keys.email)
    }
    
    @Published private(set) var isUserSignedIn = false
    
    init() {
        CTXSpendAPI.initialize(with: self)
        updateSignInState()
    }
    
    private func updateSignInState() {
        let token = accessToken
        isUserSignedIn = token != nil && !token!.isEmpty
    }
    
    func signIn(email: String) async throws -> Bool {
        do {
            try await CTXSpendAPI.shared.request(.login(email: email))
            KeychainService.save(key: Keys.email, data: email)
            
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
            throw CTXSpendError.unknown
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
        
        do {
            let response: GiftCardResponse = try await CTXSpendAPI.shared.request(.purchaseGiftCard(request))
            DSLogger.log("Gift card purchased successfully: \(response)")
            return response
        } catch let error as CTXSpendError {
            DSLogger.log("Gift card purchase failed with CTXSpendError: \(error)")
            throw error
        } catch let error as HTTPClientError {
            DSLogger.log("Gift card purchase failed with HTTPClientError: \(error)")
            
            if case .statusCode(let response) = error {
                switch response.statusCode {
                case 400:
                    if let errorData = try? JSONDecoder().decode(CTXSpendAPIError.self, from: response.data) {
                        // Check for limit error first
                        if let fiatAmountErrors = errorData.fields?.fiatAmount,
                           let firstFiatError = fiatAmountErrors.first,
                           (firstFiatError == "above threshold" || firstFiatError == "below threshold") {
                            throw CTXSpendError.customError(NSLocalizedString("The purchase limits for this merchant have changed. Please contact CTX Support for more information.", comment: "DashSpend"))
                        }
                        
                        if let firstError = errorData.errors.first {
                            // Look for specific error messages
                            let errorMessage = firstError.message.lowercased()
                            
                            if errorMessage.contains("insufficient") || errorMessage.contains("funds") {
                                throw CTXSpendError.insufficientFunds
                            } else if errorMessage.contains("merchant") {
                                throw CTXSpendError.invalidMerchant
                            } else if errorMessage.contains("amount") || errorMessage.contains("value") {
                                throw CTXSpendError.invalidAmount
                            }
                            
                            // Custom error with the actual message from API
                            throw NSError(domain: "CTXSpend", code: 400, userInfo: [NSLocalizedDescriptionKey: firstError.message])
                        }
                    }
                case 401, 403:
                    throw CTXSpendError.unauthorized
                case 404:
                    throw CTXSpendError.invalidMerchant
                case 500...599:
                    throw CTXSpendError.networkError
                default:
                    break
                }
            }
            
            throw CTXSpendError.unknown
        } catch {
            DSLogger.log("Gift card purchase failed with error: \(error)")
            throw CTXSpendError.networkError
        }
    }
    
    func getMerchant(merchantId: String) async throws -> MerchantResponse {
        do {
            let response: MerchantResponse = try await CTXSpendAPI.shared.request(.getMerchant(merchantId))
            return response
        } catch let error as CTXSpendError {
            DSLogger.log("Failed to get merchant with CTXSpendError: \(error)")
            throw error
        } catch let error as HTTPClientError {
            DSLogger.log("Failed to get merchant with HTTPClientError: \(error)")
            
            if case .statusCode(let response) = error {
                switch response.statusCode {
                case 401, 403:
                    throw CTXSpendError.unauthorized
                case 404:
                    throw CTXSpendError.invalidMerchant
                case 500...599:
                    throw CTXSpendError.networkError
                default:
                    break
                }
            }
            
            throw CTXSpendError.unknown
        } catch {
            DSLogger.log("Failed to get merchant with error: \(error)")
            throw CTXSpendError.networkError
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
        if let ctxError = error as? CTXSpendError {
            return ctxError
        }
        
        return CTXSpendError.networkError
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

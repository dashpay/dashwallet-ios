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

class PiggyCardsRepository: PiggyCardsTokenProvider, ObservableObject {
    public static let shared: PiggyCardsRepository = .init()
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let accessToken = "piggycards_access_token"
        static let refreshToken = "piggycards_refresh_token"
        static let email = "piggycards_email"
        static let userId = "piggycards_user_id"
        static let deviceUUID = "piggycards_device_uuid"
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
    
    var userId: String? {
        KeychainService.load(key: Keys.userId)
    }
    
    @Published private(set) var isUserSignedIn = false
    
    init() {
        PiggyCardsAPI.initialize(with: self)
        updateSignInState()
    }
    
    private func updateSignInState() {
        let token = accessToken
        isUserSignedIn = token != nil && !token!.isEmpty
    }
    
    func signUp(firstName: String, lastName: String, email: String, country: String) async throws -> Bool {
        do {
            let response: PiggyCardsSignupResponse = try await PiggyCardsAPI.shared.request(.signup(firstName: firstName, lastName: lastName, email: email, country: country))
            
            KeychainService.save(key: Keys.email, data: email)
            if let userId = response.userId {
                KeychainService.save(key: Keys.userId, data: userId)
            }
            
            if userDefaults.string(forKey: Keys.deviceUUID) == nil {
                userDefaults.set(UUID().uuidString, forKey: Keys.deviceUUID)
            }
            
            return true
        } catch {
            throw mapError(error)
        }
    }
    
    func login(email: String) async throws -> Bool {
        do {
            try await PiggyCardsAPI.shared.request(.login(email: email))
            KeychainService.save(key: Keys.email, data: email)
            
            if userDefaults.string(forKey: Keys.deviceUUID) == nil {
                userDefaults.set(UUID().uuidString, forKey: Keys.deviceUUID)
            }
            
            return true
        } catch {
            throw mapError(error)
        }
    }
    
    func verifyOtp(code: String) async throws -> Bool {
        guard let email = userEmail else {
            DSLogger.log("PiggyCards: email is missing while trying to verify OTP")
            throw PiggyCardsError.unknown
        }
        
        do {
            let response: PiggyCardsAuthResponse = try await PiggyCardsAPI.shared.request(.verifyOtp(email: email, otp: code))
            
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
        KeychainService.delete(key: Keys.userId)
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
        try await PiggyCardsTokenService.shared.refreshAccessToken()
    }
    
    // MARK: - Gift Card Methods
    
    func purchaseGiftCard(merchantId: String, fiatAmount: String, fiatCurrency: String = "USD", cryptoCurrency: String = "DASH") async throws -> PiggyCardsGiftCardResponse {
        let request = PiggyCardsPurchaseRequest(
            cryptoCurrency: cryptoCurrency,
            fiatCurrency: fiatCurrency,
            fiatAmount: fiatAmount,
            merchantId: merchantId
        )
        
        do {
            return try await PiggyCardsAPI.shared.request(.purchaseGiftCard(request))
        } catch let error as PiggyCardsError {
            DSLogger.log("PiggyCards gift card purchase failed with PiggyCardsError: \(error)")
            throw error
        } catch let error as HTTPClientError {
            DSLogger.log("PiggyCards gift card purchase failed with HTTPClientError: \(error)")
            
            if case .statusCode(let response) = error {
                switch response.statusCode {
                case 400:
                    if let errorData = try? JSONDecoder().decode(PiggyCardsAPIError.self, from: response.data) {
                        if let firstError = errorData.errors.first {
                            let errorMessage = firstError.message.lowercased()
                            
                            if errorMessage.contains("insufficient") || errorMessage.contains("funds") || errorMessage.contains("balance") {
                                throw PiggyCardsError.insufficientFunds
                            } else if errorMessage.contains("merchant") && (errorMessage.contains("unavailable") || errorMessage.contains("disabled")) {
                                throw PiggyCardsError.merchantUnavailable
                            } else if errorMessage.contains("merchant") {
                                throw PiggyCardsError.invalidMerchant
                            } else if errorMessage.contains("rejected") || errorMessage.contains("declined") {
                                throw PiggyCardsError.transactionRejected
                            } else if errorMessage.contains("amount") || errorMessage.contains("value") || errorMessage.contains("limit") {
                                throw PiggyCardsError.invalidAmount
                            }
                            
                            throw PiggyCardsError.customError(firstError.message)
                        }
                    }
                case 401, 403:
                    throw PiggyCardsError.unauthorized
                case 404:
                    throw PiggyCardsError.invalidMerchant
                case 409:
                    throw PiggyCardsError.transactionRejected
                case 422:
                    throw PiggyCardsError.invalidAmount
                case 500...599:
                    throw PiggyCardsError.serverError
                default:
                    break
                }
            }
            
            throw PiggyCardsError.unknown
        } catch {
            DSLogger.log("PiggyCards gift card purchase failed with error: \(error)")
            throw PiggyCardsError.networkError
        }
    }
    
    func getMerchant(merchantId: String) async throws -> PiggyCardsMerchantResponse {
        do {
            let response: PiggyCardsMerchantResponse = try await PiggyCardsAPI.shared.request(.getMerchant(merchantId))
            return response
        } catch let error as PiggyCardsError {
            DSLogger.log("PiggyCards failed to get merchant with PiggyCardsError: \(error)")
            throw error
        } catch let error as HTTPClientError {
            DSLogger.log("PiggyCards failed to get merchant with HTTPClientError: \(error)")
            
            if case .statusCode(let response) = error {
                switch response.statusCode {
                case 401, 403:
                    throw PiggyCardsError.unauthorized
                case 404:
                    throw PiggyCardsError.invalidMerchant
                case 500...599:
                    throw PiggyCardsError.networkError
                default:
                    break
                }
            }
            
            throw PiggyCardsError.unknown
        } catch {
            DSLogger.log("PiggyCards failed to get merchant with error: \(error)")
            throw PiggyCardsError.networkError
        }
    }
    
    func getGiftCardByTxid(txid: String) async throws -> PiggyCardsGiftCardResponse {
        do {
            return try await PiggyCardsAPI.shared.request(.getGiftCard(txid))
        } catch {
            throw mapError(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapError(_ error: Error) -> Error {
        if let piggyError = error as? PiggyCardsError {
            return piggyError
        }
        
        return PiggyCardsError.networkError
    }
}


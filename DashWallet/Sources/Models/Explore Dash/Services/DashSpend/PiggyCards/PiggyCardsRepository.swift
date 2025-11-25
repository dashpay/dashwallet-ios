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

class PiggyCardsRepository: DashSpendRepository {
    public static let shared: PiggyCardsRepository = .init()
    private let userDefaults = UserDefaults.standard
    
    enum Keys {
        static let accessToken = "piggycards_access_token"
        static let email = "piggycards_email"
        static let userId = "piggycards_user_id"
        static let password = "piggycards_password"
        static let tokenExpiresAt = "piggycards_token_expires_at"
    }
    
    @Published private(set) var userEmail: String? = nil
    
    var userId: String? {
        KeychainService.load(key: Keys.userId)
    }
    
    @Published private(set) var isUserSignedIn = false
    
    var userEmailPublisher: AnyPublisher<String?, Never> {
        $userEmail.eraseToAnyPublisher()
    }
    
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> {
        $isUserSignedIn.eraseToAnyPublisher()
    }
    
    init() {
        PiggyCardsAPI.initialize()
        updateSignInState()
        updateEmailState()
    }
    
    private func updateSignInState() {
        let token = KeychainService.load(key: Keys.accessToken)
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
            let response: PiggyCardsSignupResponse = try await PiggyCardsAPI.shared.request(
                .signup(firstName: "", lastName: "", email: email, country: "US", state: "AZ")
            )
            
            KeychainService.save(key: Keys.email, data: email)
            updateEmailState()
            if let userId = response.userId {
                KeychainService.save(key: Keys.userId, data: userId)
            }
            
            return true
        } catch let error as DashSpendError {
            throw error
        } catch let error as HTTPClientError {
            throw try parseError(from: error, context: "signup")
        } catch {
            throw DashSpendError.networkError
        }
    }
    
    // MARK: - Error Handling
    
    private func parseError(from error: HTTPClientError, context: String) throws -> DashSpendError {
        
        if case .statusCode(let response) = error {
            // First, try to parse the response body for single error format (used by auth endpoints)
            if response.statusCode == 400 || response.statusCode == 422 {
                if let jsonObject = try? JSONSerialization.jsonObject(with: response.data, options: []) as? [String: Any],
                   let errorMessage = jsonObject["error"] as? String {
                    let lowercasedMessage = errorMessage.lowercased()
                    
                    if lowercasedMessage.contains("invalid") && lowercasedMessage.contains("verification") && lowercasedMessage.contains("code") {
                        throw DashSpendError.invalidCode
                    }
                    
                    throw DashSpendError.customError(errorMessage)
                }
            }
            
            // Then try to parse the standard API error format (used by gift card endpoints)
            switch response.statusCode {
            case 400, 422:
                if let errorData = try? JSONDecoder().decode(PiggyCardsAPIError.self, from: response.data),
                   let firstError = errorData.errors.first {
                    let errorMessage = firstError.message.lowercased()
                    
                    if errorMessage.contains("insufficient") || errorMessage.contains("funds") || errorMessage.contains("balance") {
                        throw DashSpendError.insufficientFunds
                    } else if errorMessage.contains("merchant") && (errorMessage.contains("unavailable") || errorMessage.contains("disabled")) {
                        throw DashSpendError.merchantUnavailable
                    } else if errorMessage.contains("merchant") {
                        throw DashSpendError.invalidMerchant
                    } else if errorMessage.contains("rejected") || errorMessage.contains("declined") {
                        throw DashSpendError.transactionRejected
                    } else if errorMessage.contains("amount") || errorMessage.contains("value") || errorMessage.contains("limit") {
                        throw DashSpendError.invalidAmount
                    }
                    
                    throw DashSpendError.customError(firstError.message)
                }
                // Default to invalid amount for 422
                if response.statusCode == 422 {
                    throw DashSpendError.invalidAmount
                }
            case 401, 403:
                throw DashSpendError.unauthorized
            case 404:
                throw DashSpendError.invalidMerchant
            case 409:
                throw DashSpendError.transactionRejected
            case 500...599:
                throw DashSpendError.serverError
            default:
                break
            }
        }
        
        throw DashSpendError.unknown
    }
    
    func verifyEmail(code: String) async throws -> Bool {
        guard let email = KeychainService.load(key: Keys.email) else {
            throw DashSpendError.unknown
        }
        
        do {
            let response: PiggyCardsVerifyOtpResponse = try await PiggyCardsAPI.shared.request(.verifyOtp(email: email, otp: code))
            KeychainService.save(key: Keys.password, data: response.generatedPassword)

            if try await PiggyCardsTokenService.shared.performAutoLogin() {
                updateSignInState()
                return true
            }
            
            return false
        } catch let error as HTTPClientError {
            throw try parseError(from: error, context: "email verification")
        }
    }
    
    func logout() {
        KeychainService.delete(key: Keys.accessToken)
        KeychainService.delete(key: Keys.email)
        KeychainService.delete(key: Keys.userId)
        KeychainService.delete(key: Keys.password)
        UserDefaults.standard.removeObject(forKey: Keys.tokenExpiresAt)
        
        updateSignInState()
        updateEmailState()
    }
    
    
    // MARK: - Gift Card Methods

    /// Create an order for a gift card purchase
    /// This is the main flow for PiggyCards purchases
    func orderGiftCard(merchantId: String, fiatAmount: Double, fiatCurrency: String = "USD", cryptoCurrency: String = "DASH") async throws -> GiftCardInfo {

        // Step 1: Get cached gift cards or fetch them
        guard let giftCards = PiggyCardsCache.shared.getGiftCards(forMerchant: merchantId) else {
            throw DashSpendError.invalidMerchant
        }

        for (index, card) in giftCards.enumerated() {
        }

        // Step 2: Select the appropriate gift card
        guard let selectedCard = PiggyCardsCache.shared.selectGiftCard(from: giftCards, forAmount: fiatAmount) else {
            for card in giftCards {
                let normalizedType = card.priceType.lowercased()
                if normalizedType == "fixed" {
                } else if normalizedType == "range" {
                }
            }
            throw DashSpendError.invalidAmount
        }


        // Step 3: Get user email
        guard let email = userEmail else {
            throw DashSpendError.unauthorized
        }

        // Step 4: Create order request
        let order = PiggyCardsOrder(
            productId: selectedCard.id,
            quantity: 1,
            denomination: fiatAmount,
            currency: fiatCurrency
        )

        // Match Android's hardcoded values exactly
        // Android uses "2025-07-01" as a fixed date, not actual registration date
        let userMetadata = PiggyCardsUserMetadata(
            registeredSince: "2025-07-01",  // Hardcoded like Android
            country: "US",
            state: "CA"
        )

        let user = PiggyCardsUser(
            name: "none",
            ip: "192.168.100.1",
            metadata: userMetadata
        )

        let orderRequest = PiggyCardsOrderRequest(
            orders: [order],
            recipientEmail: email,
            user: user
        )

        // Step 5: Create the order

        // Check authentication
        let hasToken = KeychainService.load(key: Keys.accessToken) != nil

        // Log the JSON request for debugging
        if let jsonData = try? JSONEncoder().encode(orderRequest),
           let jsonString = String(data: jsonData, encoding: .utf8) {
        }

        do {
            let orderResponse: PiggyCardsOrderResponse = try await PiggyCardsAPI.shared.request(.createOrder(orderRequest))
            return try await processOrderResponse(orderResponse, selectedCard: selectedCard, giftCards: giftCards, fiatCurrency: fiatCurrency)
        } catch let error as HTTPClientError {
            // Log the raw error response for debugging
            if case .statusCode(let response) = error {
                if let errorString = String(data: response.data, encoding: .utf8) {
                }
            }
            throw try parseError(from: error, context: "create order")
        } catch let error as DashSpendError {
            throw error
        } catch {
            throw DashSpendError.unknown
        }
    }

    private func processOrderResponse(_ orderResponse: PiggyCardsOrderResponse,
                                     selectedCard: PiggyCardsGiftcard,
                                     giftCards: [PiggyCardsGiftcard],
                                     fiatCurrency: String) async throws -> GiftCardInfo {

        // Step 6: Get exchange rate
        // TEMPORARY: Skip exchange rate to get to PIN authorization
        let exchangeRate = 0.025 // Hardcoded for now to bypass and reach PIN
        // let exchangeRate = try await getExchangeRate(currency: fiatCurrency)

        // Step 7: Poll for order status (with delay)
        try await Task.sleep(nanoseconds: UInt64(PiggyCardsConstants.orderPollingDelayMs) * 1_000_000)
        let orderStatus = try await getOrderStatus(orderId: orderResponse.id)

        // Step 8: Parse payment URI and create GiftCardInfo
        // Payment info might come from either initial response or status response
        let payTo = orderResponse.payTo ?? orderStatus.data.payTo
        guard let paymentUri = payTo else {
            throw DashSpendError.customError("No payment information received")
        }
        let paymentInfo = try parsePaymentURI(paymentUri, orderId: orderResponse.id, message: orderResponse.payMessage)

        return GiftCardInfo(
            orderId: orderResponse.id,
            paymentAddress: paymentInfo.address,
            amount: paymentInfo.amount,
            merchantName: giftCards.first?.name ?? "Unknown",
            discountPercentage: calculateDisplayDiscount(selectedCard.discountPercentage),
            exchangeRate: exchangeRate,
            status: orderStatus.data.status
        )
    }

    /// Get order status to retrieve gift card details
    func getOrderStatus(orderId: String) async throws -> PiggyCardsOrderStatusResponse {
        do {
            let baseURL = PiggyCardsConstants.baseURI
            DSLogger.log("DashSpend: PiggyCards API request - BaseURL: \(baseURL), Endpoint: orders/\(orderId)")
            return try await PiggyCardsAPI.shared.request(.getOrderStatus(orderId: orderId))
        } catch let error as DashSpendError {
            throw error
        } catch let error as HTTPClientError {
            throw try parseError(from: error, context: "get order status")
        } catch {
            throw DashSpendError.networkError
        }
    }

    /// Get exchange rate for currency conversion
    func getExchangeRate(currency: String) async throws -> Double {
        // Check cache first
        if let cached = PiggyCardsCache.shared.getExchangeRate(forCurrency: currency) {
            return cached.exchangeRate
        }

        do {
            let result: PiggyCardsExchangeRateResult = try await PiggyCardsAPI.shared.request(.getExchangeRate(currency: currency))
            PiggyCardsCache.shared.storeExchangeRate(result, forCurrency: currency)
            return result.exchangeRate
        } catch let error as HTTPClientError {
            throw try parseError(from: error, context: "get exchange rate")
        }
    }

    /// Fetch available brands for a country
    func getBrands(country: String = "US") async throws -> [PiggyCardsBrand] {
        do {
            return try await PiggyCardsAPI.shared.request(.getBrands(country: country))
        } catch let error as HTTPClientError {
            throw try parseError(from: error, context: "get brands")
        }
    }

    /// Fetch gift cards for a brand and cache them
    func getGiftCards(country: String = "US", sourceId: String, merchantId: String) async throws -> [PiggyCardsGiftcard] {
        // sourceId is the PiggyCards brand ID from the database

        do {
            let response: PiggyCardsGiftcardResponse = try await PiggyCardsAPI.shared.request(.getGiftCards(country: country, brandId: sourceId))


            guard let cards = response.data else {
                throw DashSpendError.merchantUnavailable
            }

            // Log details of each card
            for (index, card) in cards.enumerated() {
            }

            // Cache the cards for later use in order creation
            PiggyCardsCache.shared.storeGiftCards(cards, forMerchant: merchantId)

            return cards
        } catch let error as HTTPClientError {
            throw try parseError(from: error, context: "get gift cards")
        }
    }

    /// Calculate display discount after service fee
    private func calculateDisplayDiscount(_ discountDecimal: Double) -> Double {
        // PiggyCards returns discount as decimal (0.15 = 15%)
        // Subtract service fee
        return (discountDecimal * 100) - PiggyCardsConstants.serviceFeePercent
    }

    /// Parse payment URI into address and amount
    private func parsePaymentURI(_ payTo: String, orderId: String, message: String?) throws -> (address: String, amount: Double) {
        // Check for empty or invalid URI
        guard !payTo.isEmpty else {
            let errorMessage = message ?? "Payment URI unavailable"
            throw DashSpendError.customError(errorMessage)
        }

        // Parse dash: URI format
        // Example: "dash:XsomeAddress?amount=1.234"
        guard payTo.hasPrefix("dash:") else {
            throw DashSpendError.customError("Invalid payment URI format")
        }

        let uriWithoutScheme = String(payTo.dropFirst(5)) // Remove "dash:"
        let components = uriWithoutScheme.split(separator: "?", maxSplits: 1)

        guard components.count >= 1 else {
            throw DashSpendError.customError("Invalid payment URI: missing address")
        }

        let address = String(components[0])
        var amount: Double = 0

        // Parse query parameters
        if components.count > 1 {
            let queryString = String(components[1])
            let queryItems = queryString.split(separator: "&")

            for item in queryItems {
                let keyValue = item.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 && keyValue[0] == "amount" {
                    amount = Double(keyValue[1]) ?? 0
                    break
                }
            }
        }

        guard amount > 0 else {
            throw DashSpendError.customError("Invalid payment amount")
        }

        return (address: address, amount: amount)
    }

    // MARK: - Legacy Methods (to be removed)

    func getMerchant(merchantId: String) async throws -> PiggyCardsMerchantResponse {
        // This should be replaced with proper brand/gift card fetching
        throw DashSpendError.unknown
    }
}


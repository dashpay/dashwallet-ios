//
//  MayaExchangeAddressProvider.swift
//  DashWallet
//
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

/// Provides deposit addresses from Uphold and Coinbase for a given cryptocurrency.
/// Used by the Maya swap flow to let users select a destination address from their exchange accounts.
@MainActor
class MayaExchangeAddressProvider {

    // MARK: - Uphold

    /// Whether the user is currently logged in to Uphold.
    var isUpholdAuthorized: Bool {
        DWUpholdClient.sharedInstance().isAuthorized
    }

    /// In-memory session cache for Uphold addresses, keyed by uppercase currency code.
    /// Cleared automatically on app restart.
    private static var upholdAddressCache: [String: String] = [:]

    /// Clears the Uphold address cache. Call this on app launch.
    static func clearUpholdCache() {
        upholdAddressCache.removeAll()
    }

    /// Returns the cached Uphold address for the currency, or fetches from API if none is cached.
    ///
    /// - Parameter currencyCode: The uppercase currency code (e.g., "BTC", "ETH").
    /// - Returns: The deposit address string, or `nil` if the currency is not available.
    func fetchUpholdAddress(for currencyCode: String) async -> String? {
        DSLogger.log("Maya Uphold: fetchUpholdAddress for \(currencyCode), authorized=\(isUpholdAuthorized)")
        guard isUpholdAuthorized else { return nil }

        let key = currencyCode.uppercased()

        // Return cached address if available
        if let cached = Self.upholdAddressCache[key] {
            DSLogger.log("Maya Uphold: Returning cached address for \(key)")
            return cached
        }

        DSLogger.log("Maya Uphold: No cache for \(key), fetching from API")
        // No cached address — fetch from API and cache
        return await fetchAndCacheUpholdAddress(for: currencyCode)
    }

    /// Fetches address from Uphold API and caches it for the session.
    /// If no card exists for the currency, creates one and generates an address.
    /// Called on login and when no cached address exists.
    ///
    /// - Parameter currencyCode: The uppercase currency code (e.g., "BTC", "ETH").
    /// - Returns: The deposit address string, or `nil` if the currency is not available.
    func fetchAndCacheUpholdAddress(for currencyCode: String) async -> String? {
        guard isUpholdAuthorized else { return nil }

        let key = currencyCode.uppercased()
        let network = upholdNetwork(for: key)

        // Step 1: Try to find an existing card
        let cards = await fetchUpholdCards()
        let availableCurrencies = cards.map { $0.currency.uppercased() }
        DSLogger.log("Maya Uphold: Got \(cards.count) cards: \(availableCurrencies), looking for \(key)")

        if let matchingCard = cards.first(where: { $0.currency.uppercased() == key }) {
            // Look for the real crypto address by network key (e.g., "bitcoin", "ethereum").
            // The card's address dictionary can also contain internal Uphold identifiers
            // (e.g., "UH1D8C10A5") under non-network keys — skip those.
            if let networkAddress = matchingCard.address?[network], !networkAddress.isEmpty {
                DSLogger.log("Maya Uphold: Found network address for \(key) on network '\(network)': \(networkAddress)")
                Self.upholdAddressCache[key] = networkAddress
                return networkAddress
            }

            // No address for this network — create one via POST
            DSLogger.log("Maya Uphold: No '\(network)' address on card \(matchingCard.id), creating one")
            if let address = await createUpholdAddress(cardId: matchingCard.id, network: network) {
                Self.upholdAddressCache[key] = address
                return address
            }
            return nil
        }

        // Step 2: No card exists — create card then address
        DSLogger.log("Maya Uphold: No card for \(key), creating card and address")
        if let cardId = await createUpholdCard(currency: key) {
            if let address = await createUpholdAddress(cardId: cardId, network: network) {
                Self.upholdAddressCache[key] = address
                return address
            }
        }

        return nil
    }

    /// Maps a currency code to the Uphold network name for address creation.
    private func upholdNetwork(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH", "USDC", "USDT", "PEPE", "WSTETH": return "ethereum"
        case "DASH": return "dash"
        case "XRP": return "xrp-ledger"
        case "BCH": return "bitcoin-cash"
        case "BTG": return "bitcoin-gold"
        default: return currencyCode.lowercased()
        }
    }

    // MARK: - Uphold API Helpers

    /// Fetches all cards from the Uphold API, including non-Dash crypto cards.
    private func fetchUpholdCards() async -> [UpholdCard] {
        guard let token = getUpholdAccessToken() else {
            DSLogger.log("Maya Uphold: No access token available for fetching cards")
            return []
        }

        guard let url = URL(string: DWUpholdConstants.baseURLString())?.appendingPathComponent("v0/me/cards") else {
            return []
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            guard (200...299).contains(statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                DSLogger.log("Maya Uphold: Fetch cards failed (HTTP \(statusCode)): \(responseBody)")
                return []
            }

            return try JSONDecoder().decode([UpholdCard].self, from: data)
        } catch {
            DSLogger.log("Maya Uphold: Failed to fetch/decode cards: \(error)")
            return []
        }
    }

    /// Creates a new Uphold card for the given currency.
    /// - Returns: The card ID if successful, or `nil`.
    private func createUpholdCard(currency: String) async -> String? {
        guard let token = getUpholdAccessToken() else { return nil }

        guard let url = URL(string: DWUpholdConstants.baseURLString())?.appendingPathComponent("v0/me/cards") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["label": "\(currency) Card", "currency": currency]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let card = try JSONDecoder().decode(UpholdCard.self, from: data)
            DSLogger.log("Maya Uphold: Created card for \(currency): \(card.id)")
            return card.id
        } catch {
            DSLogger.log("Maya Uphold: Failed to create card for \(currency): \(error)")
            return nil
        }
    }

    /// Creates a new address on an existing Uphold card.
    /// - Returns: The address string if successful, or `nil`.
    private func createUpholdAddress(cardId: String, network: String) async -> String? {
        guard let token = getUpholdAccessToken() else {
            DSLogger.log("Maya Uphold: No access token available for address creation")
            return nil
        }

        guard let url = URL(string: DWUpholdConstants.baseURLString())?.appendingPathComponent("v0/me/cards/\(cardId)/addresses") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["network": network]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let address = json["id"] as? String {
                DSLogger.log("Maya Uphold: Created address on card \(cardId) (HTTP \(statusCode)): \(address)")
                return address
            }

            // Log the full response for debugging
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            DSLogger.log("Maya Uphold: Address creation failed (HTTP \(statusCode)). Response: \(responseBody)")
            return nil
        } catch {
            DSLogger.log("Maya Uphold: Failed to create address on card \(cardId): \(error)")
            return nil
        }
    }

    private func getUpholdAccessToken() -> String? {
        getKeychainString("DW_UPHOLD_ACCESS_TOKEN", nil)
    }

    // MARK: - Coinbase

    /// Whether the user is currently logged in to Coinbase.
    var isCoinbaseAuthorized: Bool {
        Coinbase.shared.isAuthorized
    }

    /// In-memory session cache for Coinbase addresses, keyed by uppercase currency code.
    /// Cleared automatically on app restart. Call `clearCoinbaseCache()` on app launch for safety.
    private static var coinbaseAddressCache: [String: String] = [:]

    /// Clears the Coinbase address cache.
    static func clearCoinbaseCache() {
        coinbaseAddressCache.removeAll()
    }

    /// Clears all exchange address caches (Uphold and Coinbase).
    static func clearAllCaches() {
        clearUpholdCache()
        clearCoinbaseCache()
    }

    /// Returns the cached Coinbase address for the currency, or creates a new one if none is cached.
    ///
    /// - Parameter currencyCode: The uppercase currency code (e.g., "BTC", "ETH").
    /// - Returns: The deposit address string, or `nil` if the currency is not available.
    func fetchCoinbaseAddress(for currencyCode: String) async -> String? {
        DSLogger.log("Maya Coinbase: fetchCoinbaseAddress for \(currencyCode), authorized=\(isCoinbaseAuthorized)")
        guard isCoinbaseAuthorized else { return nil }

        let key = currencyCode.uppercased()

        // Return cached address if available
        if let cached = Self.coinbaseAddressCache[key] {
            DSLogger.log("Maya Coinbase: Returning cached address for \(key)")
            return cached
        }

        DSLogger.log("Maya Coinbase: No cache for \(key), creating new address")
        // No cached address — create a new one
        return await createAndCacheCoinbaseAddress(for: currencyCode)
    }

    /// Creates a new Coinbase address (POST) and caches it for the session.
    /// Called on login and when no cached address exists.
    ///
    /// Uses direct account lookup by currency code first (`GET /v2/accounts/{code}`),
    /// which is more reliable than listing all accounts. Falls back to listing if direct lookup fails.
    ///
    /// - Parameter currencyCode: The uppercase currency code (e.g., "BTC", "ETH").
    /// - Returns: The newly created deposit address string, or `nil` if the currency is not available.
    func createAndCacheCoinbaseAddress(for currencyCode: String) async -> String? {
        guard isCoinbaseAuthorized else { return nil }

        let key = currencyCode.uppercased()

        // Step 1: Try direct account lookup by currency code (most reliable)
        if let address = await fetchCoinbaseAddressViaDirectLookup(currencyCode: key) {
            Self.coinbaseAddressCache[key] = address
            return address
        }

        // Step 2: Fallback — list all accounts and search (handles edge cases where
        // the currency code doesn't work as a direct account identifier)
        if let address = await fetchCoinbaseAddressViaAccountList(currencyCode: key) {
            Self.coinbaseAddressCache[key] = address
            return address
        }

        DSLogger.log("Maya Coinbase: Currency \(key) not available on Coinbase (tried direct lookup and account list)")
        return nil
    }

    /// Fetches the account directly via `GET /v2/accounts/{currencyCode}` and creates an address.
    private func fetchCoinbaseAddressViaDirectLookup(currencyCode: String) async -> String? {
        do {
            DSLogger.log("Maya Coinbase: Trying direct account lookup for \(currencyCode)")
            let account = try await Coinbase.shared.account(byCurrencyCode: currencyCode)
            DSLogger.log("Maya Coinbase: Direct lookup found account for \(currencyCode): \(account.info.currency.code)")
            let address = try await account.retrieveAddress()
            DSLogger.log("Maya Coinbase: Created address for \(currencyCode) via direct lookup: \(address)")
            return address
        } catch {
            DSLogger.log("Maya Coinbase: Direct lookup failed for \(currencyCode): \(error)")
            return nil
        }
    }

    /// Lists all accounts and searches for the currency, then creates an address.
    private func fetchCoinbaseAddressViaAccountList(currencyCode: String) async -> String? {
        do {
            DSLogger.log("Maya Coinbase: Falling back to account list for \(currencyCode)")
            let accounts = try await Coinbase.shared.accountsIncludingEmpty()
            let availableCurrencies = accounts.map { $0.info.currency.code.uppercased() }
            DSLogger.log("Maya Coinbase: Got \(accounts.count) accounts, looking for \(currencyCode)")

            guard let account = accounts.first(where: { $0.info.currency.code.uppercased() == currencyCode }) else {
                DSLogger.log("Maya Coinbase: \(currencyCode) not found in \(accounts.count) accounts")
                return nil
            }

            let address = try await account.retrieveAddress()
            DSLogger.log("Maya Coinbase: Created address for \(currencyCode) via account list: \(address)")
            return address
        } catch {
            DSLogger.log("Maya Coinbase: Account list fallback failed for \(currencyCode): \(error)")
            return nil
        }
    }
}

// MARK: - Uphold Card Model (lightweight, for Maya only)

/// Lightweight Codable model for Uphold card responses.
/// Unlike `DWUpholdCardObject`, this preserves all currencies and address networks.
struct UpholdCard: Decodable {
    let id: String
    let currency: String
    let label: String?
    let available: String?
    let address: [String: String]?

    /// Returns the first address from the address dictionary, regardless of network key.
    var firstAddress: String? {
        address?.values.first
    }
}

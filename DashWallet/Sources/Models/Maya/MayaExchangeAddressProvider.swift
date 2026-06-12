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

struct MayaExchangeAddressLookupContext: Hashable {
    let currencyCode: String
    let chain: String
    let mayaAsset: String

    init(coin: MayaCryptoCurrency) {
        self.currencyCode = coin.code.uppercased()
        self.chain = coin.chain.uppercased()
        self.mayaAsset = coin.mayaAsset.uppercased()
    }

    var cacheKey: String {
        "\(currencyCode)|\(normalizedNetworkKey)"
    }

    var normalizedNetworkKey: String {
        switch chain {
        case "ARB": return "arbitrum"
        case "AVAX": return "avalanche"
        case "BASE": return "base"
        case "BERA": return "berachain"
        case "BSC": return "bsc"
        case "ETH": return "ethereum"
        case "GNO": return "gnosis"
        case "MONAD": return "monad"
        case "OP": return "optimism"
        case "POL": return "polygon"
        case "TRON": return "tron"
        case "XLAYER": return "xlayer"
        default: return chain.lowercased()
        }
    }

    var acceptedCoinbaseNetworkKeys: Set<String> {
        switch normalizedNetworkKey {
        case "arbitrum":
            return ["arb", "arbitrum", "arbitrum one"]
        case "avalanche":
            return ["avax", "avalanche", "avalanche c-chain", "c-chain"]
        case "base":
            return ["base"]
        case "berachain":
            return ["bera", "berachain"]
        case "bsc":
            return ["binance smart chain", "bnb", "bnb smart chain", "bsc"]
        case "ethereum":
            return ["erc20", "eth", "ethereum"]
        case "gnosis":
            return ["gno", "gnosis", "xdai"]
        case "monad":
            return ["monad"]
        case "optimism":
            return ["op", "optimism"]
        case "polygon":
            return ["matic", "polygon", "polygon pos", "polygon-pos"]
        case "tron":
            return ["tron", "trx", "trc20"]
        case "xlayer":
            return ["x layer", "x-layer", "xlayer"]
        default:
            return [normalizedNetworkKey]
        }
    }

    func normalizedCoinbaseReportedNetwork(_ reportedNetwork: String) -> String {
        reportedNetwork
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
    }

    func matchesCoinbaseReportedNetwork(_ reportedNetwork: String) -> Bool {
        acceptedCoinbaseNetworkKeys.contains(normalizedCoinbaseReportedNetwork(reportedNetwork))
    }

    var usesAmbiguousCurrencyCode: Bool {
        MayaCryptoCurrency.supportedCoins.contains {
            $0.code.caseInsensitiveCompare(currencyCode) == .orderedSame &&
                $0.chain.caseInsensitiveCompare(chain) != .orderedSame
        }
    }

    var tokenIdentifier: String? {
        let parts = mayaAsset.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return parts[1]
    }

    var coinbaseMatchHints: [String] {
        var hints = [currencyCode, chain, normalizedNetworkKey]
        if let tokenIdentifier {
            hints.append(tokenIdentifier)
            if let symbolOnly = tokenIdentifier.split(separator: "-", maxSplits: 1).first {
                hints.append(String(symbolOnly))
            }
        }
        let chainLabel = MayaCryptoCurrency.chainDisplayName(chain).uppercased()
        if !chainLabel.isEmpty {
            hints.append(chainLabel)
        }
        return Array(Set(hints.map { $0.uppercased() }))
    }
}

/// Provides deposit addresses from Uphold and Coinbase for a given cryptocurrency.
/// Used by the Maya swap flow to let users select a destination address from their exchange accounts.
@MainActor
class MayaExchangeAddressProvider {

    // MARK: - Uphold

    /// Whether the user is currently logged in to Uphold.
    var isUpholdAuthorized: Bool {
        DWUpholdClient.sharedInstance().isAuthorized
    }

    /// In-memory session cache for Uphold addresses, keyed by currency + destination network.
    /// Cleared automatically on app restart.
    private static var upholdAddressCache: [String: String] = [:]

    /// Clears the Uphold address cache. Call this on app launch.
    static func clearUpholdCache() {
        upholdAddressCache.removeAll()
    }

    /// Returns the cached Uphold address for the destination coin, or fetches from API if none is cached.
    ///
    /// - Parameter coin: The selected Maya destination coin.
    /// - Returns: The deposit address string, or `nil` if the currency is not available.
    func fetchUpholdAddress(for coin: MayaCryptoCurrency) async -> String? {
        let context = MayaExchangeAddressLookupContext(coin: coin)
        DSLogger.log("Maya Uphold: fetchUpholdAddress for \(context.currencyCode) on \(context.normalizedNetworkKey), authorized=\(isUpholdAuthorized)")
        guard isUpholdAuthorized else { return nil }

        // Return cached address if available
        if let cached = Self.upholdAddressCache[context.cacheKey] {
            DSLogger.log("Maya Uphold: Returning cached address for \(context.cacheKey)")
            return cached
        }

        DSLogger.log("Maya Uphold: No cache for \(context.cacheKey), fetching from API")
        // No cached address — fetch from API and cache
        return await fetchAndCacheUpholdAddress(for: coin)
    }

    /// Fetches address from Uphold API and caches it for the session.
    /// If no card exists for the currency, creates one and generates an address.
    /// Called on login and when no cached address exists.
    ///
    /// - Parameter coin: The selected Maya destination coin.
    /// - Returns: The deposit address string, or `nil` if the currency is not available.
    func fetchAndCacheUpholdAddress(for coin: MayaCryptoCurrency) async -> String? {
        guard isUpholdAuthorized else { return nil }

        let context = MayaExchangeAddressLookupContext(coin: coin)
        let network = upholdNetwork(for: context)

        // Step 1: Try to find an existing card
        let cards = await fetchUpholdCards()
        let availableCurrencies = cards.map { $0.currency.uppercased() }
        DSLogger.log("Maya Uphold: Got \(cards.count) cards: \(availableCurrencies), looking for \(context.currencyCode) on \(network)")

        if let matchingCard = cards.first(where: { $0.currency.uppercased() == context.currencyCode }) {
            // Look for the real crypto address by network key (e.g., "bitcoin", "ethereum").
            // The card's address dictionary can also contain internal Uphold identifiers
            // (e.g., "UH1D8C10A5") under non-network keys — skip those.
            if let networkAddress = matchingCard.address?[network], !networkAddress.isEmpty {
                DSLogger.log("Maya Uphold: Found network address for \(context.currencyCode) on network '\(network)': \(networkAddress)")
                Self.upholdAddressCache[context.cacheKey] = networkAddress
                return networkAddress
            }

            // No address for this network — create one via POST
            DSLogger.log("Maya Uphold: No '\(network)' address on card \(matchingCard.id), creating one")
            if let address = await createUpholdAddress(cardId: matchingCard.id, network: network) {
                Self.upholdAddressCache[context.cacheKey] = address
                return address
            }
            return nil
        }

        // Step 2: No card exists — create card then address
        DSLogger.log("Maya Uphold: No card for \(context.currencyCode), creating card and address")
        if let cardId = await createUpholdCard(currency: context.currencyCode) {
            if let address = await createUpholdAddress(cardId: cardId, network: network) {
                Self.upholdAddressCache[context.cacheKey] = address
                return address
            }
        }

        return nil
    }

    /// Maps the selected Maya chain to the Uphold network name used during address creation.
    private func upholdNetwork(for context: MayaExchangeAddressLookupContext) -> String {
        switch context.chain {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "ARB": return "arbitrum"
        case "AVAX": return "avalanche"
        case "BASE": return "base"
        case "BSC": return "bsc"
        case "DASH": return "dash"
        case "GNO": return "gnosis"
        case "OP": return "optimism"
        case "POL": return "polygon"
        case "SOL": return "solana"
        case "TON": return "ton"
        case "TRON": return "tron"
        case "XRP": return "xrp-ledger"
        case "BCH": return "bitcoin-cash"
        case "BTG": return "bitcoin-gold"
        default: return context.normalizedNetworkKey
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
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                DSLogger.log("Maya Uphold: Create card failed with status \(statusCode) for \(currency)")
                return nil
            }
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

    /// In-memory session cache for Coinbase addresses, keyed by currency + destination network.
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

    /// Returns the cached Coinbase address for the destination coin, or creates a new one if none is cached.
    ///
    /// - Parameter coin: The selected Maya destination coin.
    /// - Returns: The deposit address string, or `nil` if the currency is not available.
    func fetchCoinbaseAddress(for coin: MayaCryptoCurrency) async -> String? {
        let context = MayaExchangeAddressLookupContext(coin: coin)
        DSLogger.log("Maya Coinbase: fetchCoinbaseAddress for \(context.currencyCode) on \(context.normalizedNetworkKey), authorized=\(isCoinbaseAuthorized)")
        guard isCoinbaseAuthorized else { return nil }

        // Return cached address if available
        if let cached = Self.coinbaseAddressCache[context.cacheKey] {
            DSLogger.log("Maya Coinbase: Returning cached address for \(context.cacheKey)")
            return cached
        }

        DSLogger.log("Maya Coinbase: No cache for \(context.cacheKey), creating new address")
        // No cached address — create a new one
        return await createAndCacheCoinbaseAddress(for: coin)
    }

    /// Creates a new Coinbase address (POST) and caches it for the session.
    /// Called on login and when no cached address exists.
    ///
    /// Uses direct account lookup by currency code first (`GET /v2/accounts/{code}`),
    /// which is more reliable than listing all accounts. Falls back to listing if direct lookup fails.
    ///
    /// - Parameter coin: The selected Maya destination coin.
    /// - Returns: The newly created deposit address string, or `nil` if the currency is not available.
    func createAndCacheCoinbaseAddress(for coin: MayaCryptoCurrency) async -> String? {
        guard isCoinbaseAuthorized else { return nil }

        let context = MayaExchangeAddressLookupContext(coin: coin)

        // Prefer the account list for multi-network symbols so ETH.USDC and ARB.USDC
        // do not silently collapse onto the same default Coinbase account.
        if context.usesAmbiguousCurrencyCode {
            if let address = await fetchCoinbaseAddressViaAccountList(context: context) {
                Self.coinbaseAddressCache[context.cacheKey] = address
                return address
            }
        } else if let address = await fetchCoinbaseAddressViaDirectLookup(context: context) {
            Self.coinbaseAddressCache[context.cacheKey] = address
            return address
        } else if let address = await fetchCoinbaseAddressViaAccountList(context: context) {
            Self.coinbaseAddressCache[context.cacheKey] = address
            return address
        }

        DSLogger.log("Maya Coinbase: Currency \(context.currencyCode) on \(context.normalizedNetworkKey) not available on Coinbase")
        return nil
    }

    /// Fetches the account directly via `GET /v2/accounts/{currencyCode}` and creates an address.
    private func fetchCoinbaseAddressViaDirectLookup(context: MayaExchangeAddressLookupContext) async -> String? {
        do {
            DSLogger.log("Maya Coinbase: Trying direct account lookup for \(context.currencyCode)")
            let account = try await Coinbase.shared.account(byCurrencyCode: context.currencyCode)
            DSLogger.log("Maya Coinbase: Direct lookup found account for \(context.currencyCode): \(account.info.currency.code)")
            let addressInfo = try await account.retrieveAddressInfo()
            guard let address = validatedCoinbaseAddress(addressInfo: addressInfo, context: context, source: "direct lookup") else {
                return nil
            }
            DSLogger.log("Maya Coinbase: Created address for \(context.currencyCode) via direct lookup: \(address)")
            return address
        } catch {
            DSLogger.log("Maya Coinbase: Direct lookup failed for \(context.currencyCode): \(error)")
            return nil
        }
    }

    /// Lists all accounts and searches for the currency, then creates an address.
    private func fetchCoinbaseAddressViaAccountList(context: MayaExchangeAddressLookupContext) async -> String? {
        do {
            DSLogger.log("Maya Coinbase: Falling back to account list for \(context.currencyCode) on \(context.normalizedNetworkKey)")
            let accounts = try await Coinbase.shared.accountsIncludingEmpty()
            let availableCurrencies = accounts.map { $0.info.currency.code.uppercased() }
            DSLogger.log("Maya Coinbase: Got \(accounts.count) accounts, looking for \(context.currencyCode)")

            let candidateAccounts = accounts.filter {
                $0.info.currency.code.uppercased() == context.currencyCode && $0.info.allowDeposits
            }

            guard let account = preferredCoinbaseAccount(from: candidateAccounts, context: context) else {
                DSLogger.log("Maya Coinbase: \(context.currencyCode) not found in \(accounts.count) depositable accounts")
                return nil
            }

            let addressInfo = try await account.retrieveAddressInfo()
            guard let address = validatedCoinbaseAddress(addressInfo: addressInfo, context: context, source: "account list") else {
                return nil
            }
            DSLogger.log("Maya Coinbase: Created address for \(context.currencyCode) via account list: \(address)")
            return address
        } catch {
            DSLogger.log("Maya Coinbase: Account list fallback failed for \(context.currencyCode): \(error)")
            return nil
        }
    }

    private func preferredCoinbaseAccount(from accounts: [CBAccount], context: MayaExchangeAddressLookupContext) -> CBAccount? {
        accounts.max { lhs, rhs in
            let leftScore = scoreCoinbaseAccount(lhs, context: context)
            let rightScore = scoreCoinbaseAccount(rhs, context: context)
            if leftScore == rightScore {
                return lhs.info.primary == false && rhs.info.primary == true
            }
            return leftScore < rightScore
        }
    }

    private func scoreCoinbaseAccount(_ account: CBAccount, context: MayaExchangeAddressLookupContext) -> Int {
        var score = account.info.primary ? 5 : 0
        let haystack = [
            account.info.name,
            account.info.currency.name,
            account.info.currency.slug,
            account.info.currency.assetID,
            account.info.resourcePath
        ]
            .compactMap { $0?.uppercased() }
            .joined(separator: " ")

        for hint in context.coinbaseMatchHints where haystack.contains(hint) {
            score += 10
        }

        return score
    }

    private func validatedCoinbaseAddress(
        addressInfo: CoinbaseAccountAddress,
        context: MayaExchangeAddressLookupContext,
        source: String
    ) -> String? {
        guard let reportedNetwork = addressInfo.network?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reportedNetwork.isEmpty else {
            return addressInfo.address
        }

        let normalizedReported = context.normalizedCoinbaseReportedNetwork(reportedNetwork)
        guard !context.matchesCoinbaseReportedNetwork(reportedNetwork) else {
            return addressInfo.address
        }

        DSLogger.log(
            "Maya Coinbase: Rejecting address due to network mismatch via \(source). " +
            "Requested \(context.currencyCode) on \(context.normalizedNetworkKey), Coinbase reported \(normalizedReported)"
        )

        return nil
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

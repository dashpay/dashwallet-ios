//
//  SelectCoinViewModel.swift
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

import Combine
import Foundation

struct CoinDisplayItem: Identifiable {
    let id: String
    let coin: MayaCryptoCurrency
    /// Effective display name for the coin row.
    /// Equals `coin.name` today; structured to accept an API-provided override in future.
    let displayName: String
    let fiatPrice: String?
    let isHalted: Bool
}

@MainActor
class SelectCoinViewModel: ObservableObject {
    private let swapProvider: SwapProvider

    init(swapProvider: SwapProvider = MayaSwapProvider()) {
        self.swapProvider = swapProvider
    }
    // MARK: - Published State

    @Published var coins: [CoinDisplayItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasHaltedCoins: Bool = false
    @Published var showHaltedToast: Bool = false

    /// ID of the last coin the user tapped; used to restore scroll position on back-navigation.
    private(set) var scrollAnchorID: String?

    var filteredCoins: [CoinDisplayItem] {
        guard !searchText.isEmpty else { return coins }
        return coins.filter { matchesSearch($0, query: searchText) }
    }

    var showSearchEmptyState: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        filteredCoins.isEmpty &&
        !isLoading &&
        errorMessage == nil
    }

    // MARK: - Selection

    /// Records the tapped coin so `SelectCoinView` can restore scroll position on back-navigation.
    func willSelectCoin(_ item: CoinDisplayItem) {
        scrollAnchorID = item.id
    }

    // MARK: - Loading

    /// Loads coins from the network.
    /// Skips the network call if coins are already loaded and there is no pending error,
    /// which prevents the `.task` re-fire on back-navigation from resetting the scroll position.
    func loadCoins(force: Bool = false) async {
        guard force || coins.isEmpty || errorMessage != nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let poolsRequest = swapProvider.fetchPools()
            async let inboundRequest = swapProvider.fetchInboundAddresses()
            let (pools, inboundAddresses) = try await (poolsRequest, inboundRequest)

            let fiatCurrency = App.fiatCurrency
            let formatter = makePriceFormatter(for: fiatCurrency)
            let items = makeCoinItems(
                pools: pools,
                inboundAddresses: inboundAddresses,
                fiatCurrency: fiatCurrency,
                formatter: formatter
            )

            let disambiguated = disambiguateDisplayNames(items)
            coins = sortCoins(disambiguated)
            hasHaltedCoins = disambiguated.contains { $0.isHalted }
            showHaltedToast = hasHaltedCoins
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private: Item Creation

    private func makeCoinItems(
        pools: [MayaPool],
        inboundAddresses: [MayaInboundAddress],
        fiatCurrency: String,
        formatter: NumberFormatter
    ) -> [CoinDisplayItem] {
        let inboundChains = Set(inboundAddresses.map { $0.chain.uppercased() })
        let haltedChains = Set(inboundAddresses.filter { $0.halted }.map { $0.chain.uppercased() })

        return pools.compactMap { pool in
            guard pool.isAvailable else { return nil }
            guard pool.asset.uppercased() != "DASH.DASH" else { return nil }
            guard let coin = MayaCryptoCurrency.knownCoin(for: pool.asset) else { return nil }
            guard inboundChains.contains(coin.chain.uppercased()) else { return nil }

            return CoinDisplayItem(
                id: coin.id,
                coin: coin,
                displayName: coin.name,   // API-override point: swap in pool.name when available
                fiatPrice: priceForCoin(pool, fiatCurrency: fiatCurrency, formatter: formatter),
                isHalted: isCoinHalted(coin, haltedChains: haltedChains)
            )
        }
    }

    private func makePriceFormatter(for fiatCurrency: String) -> NumberFormatter {
        // Reuse the app-wide fiat formatter (currency style) so prices render with the locale
        // currency *symbol* — "$0.18", "₴44,54", "€0,18" — consistent with the rest of the wallet,
        // instead of an ISO-code prefix. iOS falls back to the ISO code for currencies that have
        // no symbol. The amount is always shown with 2 fraction digits so sub-unit prices stay legible.
        let formatter = NumberFormatter.fiatFormatter(currencyCode: fiatCurrency)
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    // MARK: - Private: Disambiguation

    /// Adds a "(ChainName)" suffix to `displayName` for every item whose coin code is shared
    /// by at least one other item and whose name doesn't already carry a parenthetical qualifier.
    /// This disambiguates e.g. two USDC pools: "USD Coin (Ethereum)" vs "USD Coin (Arbitrum)".
    private func disambiguateDisplayNames(_ items: [CoinDisplayItem]) -> [CoinDisplayItem] {
        let codeGroups = Dictionary(grouping: items, by: { $0.coin.code })
        return items.map { item in
            guard (codeGroups[item.coin.code]?.count ?? 0) > 1 else { return item }
            guard !item.displayName.contains("(") else { return item }
            let chainLabel = MayaCryptoCurrency.chainDisplayName(item.coin.chain)
            let qualifiedName = chainLabel.isEmpty
                ? item.displayName
                : "\(item.displayName) (\(chainLabel))"
            return CoinDisplayItem(
                id: item.id, coin: item.coin,
                displayName: qualifiedName,
                fiatPrice: item.fiatPrice, isHalted: item.isHalted
            )
        }
    }

    // MARK: - Private: Filtering and Sorting

    private func matchesSearch(_ item: CoinDisplayItem, query: String) -> Bool {
        item.displayName.localizedCaseInsensitiveContains(query) ||
        item.coin.code.localizedCaseInsensitiveContains(query) ||
        item.coin.name.localizedCaseInsensitiveContains(query)  // fallback for static name
    }

    private func sortCoins(_ items: [CoinDisplayItem]) -> [CoinDisplayItem] {
        items.sorted { a, b in
            let codeComparison = a.coin.code.localizedCaseInsensitiveCompare(b.coin.code)
            if codeComparison != .orderedSame { return codeComparison == .orderedAscending }
            // Match Android's primary sort by code while keeping equal-code rows stable.
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    // MARK: - Private: Helpers

    private func isCoinHalted(_ coin: MayaCryptoCurrency, haltedChains: Set<String>) -> Bool {
        haltedChains.contains(coin.chain.uppercased())
    }

    private func priceForCoin(_ pool: MayaPool, fiatCurrency: String, formatter: NumberFormatter) -> String? {
        guard let priceUSD = pool.priceUSD, priceUSD > 0 else { return nil }
        guard let fiatAmount = convertUSDToFiat(usdAmount: priceUSD, fiatCurrency: fiatCurrency) else { return nil }
        // Locale currency symbol + amount (e.g. "$0.18", "₴44,54"); the shared fiat formatter
        // positions the symbol per the user's locale.
        return formatter.string(from: NSNumber(value: fiatAmount))
    }

    private func convertUSDToFiat(usdAmount: Double, fiatCurrency: String) -> Double? {
        if fiatCurrency == "USD" { return usdAmount }
        do {
            let result = try CurrencyExchanger.shared.convert(
                to: fiatCurrency,
                amount: Decimal(usdAmount),
                amountCurrency: "USD"
            )
            return NSDecimalNumber(decimal: result).doubleValue
        } catch {
            return nil
        }
    }
}

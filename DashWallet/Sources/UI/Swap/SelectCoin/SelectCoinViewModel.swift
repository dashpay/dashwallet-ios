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
    let coin: SwapCryptoCurrency
    /// Effective display name for the coin row.
    /// Equals `coin.name` today; structured to accept an API-provided override in future.
    let displayName: String
    let fiatPrice: String?
    let isHalted: Bool
    /// Routing network label shown in the coin row (e.g. "Maya", "NEAR", "Multiple networks").
    /// Nil for non-SwapKit providers that don't have multi-provider routing.
    let network: String?
}

@MainActor
class SelectCoinViewModel: ObservableObject {
    private var swapProvider: SwapProvider
    private let direction: SwapDirection
    private var lastLoadedCoinSignature: [String] = []
    private let networkStatus: NetworkStatusProviding
    private var networkCancellable: AnyCancellable?

    init(swapProvider: SwapProvider = MayaSwapProvider(), direction: SwapDirection = .sell, networkStatus: NetworkStatusProviding = NetworkStatusService.shared) {
        self.swapProvider = swapProvider
        self.direction = direction
        self.networkStatus = networkStatus
        self.isOnline = networkStatus.isOnline
        if direction == .buy {
            self.swapProvider.onBuyRoutabilityChanged = { [weak self] in
                Task { await self?.loadCoins(force: true) }
            }
        }
        subscribeToNetworkStatus()
    }

    deinit {
        swapProvider.onBuyRoutabilityChanged = nil
    }
    // MARK: - Published State

    @Published var coins: [CoinDisplayItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasHaltedCoins: Bool = false
    @Published var showHaltedToast: Bool = false
    @Published private(set) var isOnline: Bool

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

    // MARK: - Network Status

    private func subscribeToNetworkStatus() {
        networkCancellable = networkStatus.statusPublisher
            .sink { [weak self] status in
                guard let self else { return }
                self.isOnline = status == .online
                if status == .online {
                    Task { await self.loadCoins() }
                }
            }
    }

    // MARK: - Loading

    /// Loads coins from the network.
    /// Skips the network call if coins are already loaded and there is no pending error,
    /// which prevents the `.task` re-fire on back-navigation from resetting the scroll position.
    func loadCoins(force: Bool = false) async {
        guard isOnline else { return }
        guard force || coins.isEmpty || errorMessage != nil else { return }
        let shouldShowLoading = coins.isEmpty || errorMessage != nil
        if shouldShowLoading {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if shouldShowLoading {
                isLoading = false
            }
        }

        do {
            // Pools must resolve first: fetchInboundAddresses() reads the provider's cached pools,
            // so running both concurrently can hit the empty-cache fallback and return [] — which
            // would then filter out every pool via inboundChains.
            let pools = try await swapProvider.fetchPools(direction: direction)
            let inboundAddresses = try await swapProvider.fetchInboundAddresses()

            let fiatCurrency = App.fiatCurrency
            let formatter = makePriceFormatter(for: fiatCurrency)
            let networkLabels = normalizedNetworkLabels(await swapProvider.networkLabels(for: pools))
            let haltedAssets = await swapProvider.haltedAssets(from: inboundAddresses, pools: pools)
            let items = makeCoinItems(
                pools: pools,
                inboundAddresses: inboundAddresses,
                fiatCurrency: fiatCurrency,
                formatter: formatter,
                networkLabels: networkLabels,
                haltedAssets: haltedAssets
            )

            let disambiguated = appendChainLabels(items)
            let sorted = sortCoins(disambiguated)
            let signature = coinSignature(sorted)
            guard signature != lastLoadedCoinSignature else { return }
            lastLoadedCoinSignature = signature
            coins = sorted
            hasHaltedCoins = sorted.contains { $0.isHalted }
            showHaltedToast = hasHaltedCoins
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private: Item Creation

    private func makeCoinItems(
        pools: [SwapPool],
        inboundAddresses: [SwapInboundAddress],
        fiatCurrency: String,
        formatter: NumberFormatter,
        networkLabels: [String: String] = [:],
        haltedAssets: Set<String> = []
    ) -> [CoinDisplayItem] {
        let inboundChains = Set(inboundAddresses.map { $0.chain.uppercased() })
        let haltedChains = Set(inboundAddresses.filter { $0.halted }.map { $0.chain.uppercased() })

        return pools.compactMap { pool in
            guard pool.isAvailable else { return nil }
            guard pool.asset.uppercased() != "DASH.DASH" else { return nil }
            guard var coin = SwapCryptoCurrency.knownCoin(for: pool.asset) else { return nil }
            guard inboundChains.contains(coin.chain.uppercased()) else { return nil }
            coin.iconURL = swapProvider.logoURL(for: pool.asset)?.absoluteString

            let isHalted = haltedAssets.contains(pool.asset.uppercased())
                || isCoinHalted(coin, haltedChains: haltedChains)

            return CoinDisplayItem(
                id: coin.id,
                coin: coin,
                displayName: coin.name,
                fiatPrice: priceForCoin(pool, fiatCurrency: fiatCurrency, formatter: formatter),
                isHalted: isHalted,
                network: networkLabels[pool.asset.uppercased()]
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

    private func normalizedNetworkLabels(_ labels: [String: String]) -> [String: String] {
        // Both Buy and Sell now route exclusively through NEAR intents (mayaOnly coins are
        // hidden and the quote layer forces NEAR), so a "Multiple networks" label is never
        // accurate — a both-routable coin effectively resolves to a single provider (NEAR).
        return labels.mapValues { $0 == RouteProvider.multiple.shortLabel ? RouteProvider.near.shortLabel : $0 }
    }

    // MARK: - Private: Chain label

    /// Appends ` (ChainName)` to every coin's display name.
    /// Only skipped when the name already contains `(` (avoids double-suffix on manual qualifiers
    /// like "NEAR (Alice)") or when the chain has no display name (DASH only).
    private func appendChainLabels(_ items: [CoinDisplayItem]) -> [CoinDisplayItem] {
        items.map { item in
            guard !item.displayName.contains("(") else { return item }
            let chainLabel = SwapCryptoCurrency.chainDisplayName(item.coin.chain)
            guard !chainLabel.isEmpty else { return item }
            return CoinDisplayItem(
                id: item.id, coin: item.coin,
                displayName: "\(item.displayName) (\(chainLabel))",
                fiatPrice: item.fiatPrice, isHalted: item.isHalted,
                network: item.network
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

    private func coinSignature(_ items: [CoinDisplayItem]) -> [String] {
        items.map { item in
            [
                item.id,
                item.network ?? "",
                item.isHalted ? "1" : "0",
                item.fiatPrice ?? ""
            ].joined(separator: "|")
        }
    }

    // MARK: - Private: Helpers

    private func isCoinHalted(_ coin: SwapCryptoCurrency, haltedChains: Set<String>) -> Bool {
        haltedChains.contains(coin.chain.uppercased())
    }

    private func priceForCoin(_ pool: SwapPool, fiatCurrency: String, formatter: NumberFormatter) -> String? {
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

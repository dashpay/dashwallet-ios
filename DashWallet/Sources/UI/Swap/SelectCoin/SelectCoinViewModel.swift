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
    private let swapProvider: SwapProvider
    private let direction: SwapDirection
    private var lastLoadedCoinSignature: [String] = []
    /// What the last successful load fetched, so a live-availability change re-labels the list
    /// without fetching pools again.
    private var loadedPools: [SwapPool]?
    private var loadedInboundAddresses: [SwapInboundAddress] = []
    /// The loaded pools in display order — the order the live checks walk.
    private var displayedPools: [SwapPool] = []
    private let networkStatus: NetworkStatusProviding
    private var networkCancellable: AnyCancellable?
    private var routeAvailabilityCancellable: AnyCancellable?
    /// The halted toast is shown once per picker: live answers keep re-rendering the list, and a
    /// dismissed toast must not come back with them.
    private var haltedToastShown = false
    /// Identifies the `keepRouteAvailabilityFresh` run of the picker on screen; 0 when none runs.
    /// A run that ends after a newer one started must not stop the newer one's checks.
    private var routeFreshnessRun = 0
    private var routeFreshnessRuns = 0
    /// Identifies the latest render, so a slower older one does not publish over it.
    private var renderGeneration = 0
    /// Identifies the latest load: loads can overlap (the view's `.task` and a reconnect), and only
    /// the latest one commits what it fetched.
    private var loadGeneration = 0

    /// How often the live checks are re-run while the picker is on screen. Only answers that are due
    /// are asked again, so most ticks send nothing.
    private let routeRefreshInterval: UInt64 = 60_000_000_000

    init(swapProvider: SwapProvider = MayaSwapProvider(), direction: SwapDirection = .sell, networkStatus: NetworkStatusProviding = NetworkStatusService.shared) {
        self.swapProvider = swapProvider
        self.direction = direction
        self.networkStatus = networkStatus
        self.isOnline = networkStatus.isOnline
        // Answers arrive one by one while a refresh runs; re-render once they pause.
        routeAvailabilityCancellable = swapProvider.routeAvailabilityChanges
            .filter { $0 == direction }
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.reloadRouteAvailability() }
            }
        subscribeToNetworkStatus()
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
        loadGeneration += 1
        let generation = loadGeneration
        let shouldShowLoading = coins.isEmpty || errorMessage != nil
        if shouldShowLoading {
            isLoading = true
        }
        errorMessage = nil
        defer {
            if shouldShowLoading, generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            // Pools must resolve first: fetchInboundAddresses() reads the provider's cached pools,
            // so running both concurrently can hit the empty-cache fallback and return [] — which
            // would then filter out every pool via inboundChains.
            let pools = try await swapProvider.fetchPools(direction: direction)
            let inboundAddresses = try await swapProvider.fetchInboundAddresses()
            guard generation == loadGeneration else { return }
            loadedPools = pools
            loadedInboundAddresses = inboundAddresses
            let sorted = await render(pools: pools, inboundAddresses: inboundAddresses)
            guard generation == loadGeneration else { return }
            let poolsByAsset = Dictionary(pools.map { ($0.asset.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
            displayedPools = sorted.compactMap { poolsByAsset[$0.coin.swapAsset.uppercased()] }
            // A load that lands while the picker is on screen (after reconnecting, say) starts the
            // checks now rather than at the next tick.
            if routeFreshnessRun != 0 {
                swapProvider.refreshRouteAvailability(for: displayedPools, direction: direction)
            }
        } catch {
            let detail = SwapKitFailureDetail.describe(error)
            DWLogger.log("Swap: \(type(of: swapProvider)) coin list (\(direction)) failed to load — \(detail)")
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Keeps the live route checks running while the picker is on screen: once now, then every
    /// `routeRefreshInterval`. Runs until the calling task is cancelled — the view's `.task`, which
    /// SwiftUI cancels when the picker leaves the screen — and then stops the checks, so they do
    /// not spend the SwapKit quota while the user is on another screen.
    func keepRouteAvailabilityFresh() async {
        // A `.task` cancelled while its load was still running must not stop the refresh that the
        // re-shown picker's own `.task` has started meanwhile.
        guard !Task.isCancelled else { return }
        routeFreshnessRuns += 1
        let run = routeFreshnessRuns
        routeFreshnessRun = run
        defer {
            if routeFreshnessRun == run {
                routeFreshnessRun = 0
                swapProvider.stopRouteAvailabilityRefresh(direction: direction)
            }
        }
        while !Task.isCancelled {
            if !displayedPools.isEmpty {
                swapProvider.refreshRouteAvailability(for: displayedPools, direction: direction)
            }
            try? await Task.sleep(nanoseconds: routeRefreshInterval)
        }
    }

    /// Re-labels the loaded coins after live route answers changed. Nothing loaded yet (or a failed
    /// load) means there is nothing to re-label: the next load renders the current answers.
    private func reloadRouteAvailability() async {
        guard let pools = loadedPools, errorMessage == nil else { return }
        await render(pools: pools, inboundAddresses: loadedInboundAddresses)
    }

    /// Builds the rows for `pools` with the provider's current labels and halts and publishes them
    /// when they changed. Returns the rows in display order.
    @discardableResult
    private func render(pools: [SwapPool], inboundAddresses: [SwapInboundAddress]) async -> [CoinDisplayItem] {
        renderGeneration += 1
        let generation = renderGeneration
        let fiatCurrency = App.fiatCurrency
        let formatter = makePriceFormatter(for: fiatCurrency)
        let networkLabels = await swapProvider.networkLabels(for: pools, direction: direction)
        let haltedAssets = await swapProvider.haltedAssets(from: inboundAddresses, pools: pools, direction: direction)
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
        guard generation == renderGeneration, signature != lastLoadedCoinSignature else { return sorted }
        lastLoadedCoinSignature = signature
        coins = sorted
        hasHaltedCoins = sorted.contains { $0.isHalted }
        if !hasHaltedCoins {
            showHaltedToast = false
        } else if !haltedToastShown {
            haltedToastShown = true
            showHaltedToast = true
        }
        return sorted
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

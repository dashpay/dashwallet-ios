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
    let fiatPrice: String?
    let isHalted: Bool
}

@MainActor
class SelectCoinViewModel: ObservableObject {
    // MARK: - Published State

    @Published var coins: [CoinDisplayItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasHaltedCoins: Bool = false
    @Published var showHaltedToast: Bool = false

    var filteredCoins: [CoinDisplayItem] {
        guard !searchText.isEmpty else { return coins }
        return coins.filter { matchesSearch($0, query: searchText) }
    }

    // MARK: - Loading

    func loadCoins() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let poolsRequest = MayaAPIService.shared.fetchPools()
            async let inboundRequest = MayaAPIService.shared.fetchInboundAddresses()
            let (pools, inboundAddresses) = try await (poolsRequest, inboundRequest)

            let fiatCurrency = App.fiatCurrency
            let formatter = makePriceFormatter(for: fiatCurrency)
            let items = makeCoinItems(
                pools: pools,
                inboundAddresses: inboundAddresses,
                fiatCurrency: fiatCurrency,
                formatter: formatter
            )

            coins = sortCoins(items)
            hasHaltedCoins = items.contains { $0.isHalted }
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
            guard let coin = MayaCryptoCurrency.coin(for: pool.asset) else { return nil }
            guard inboundChains.contains(coin.chain.uppercased()) else { return nil }

            return CoinDisplayItem(
                id: coin.id,
                coin: coin,
                fiatPrice: priceForCoin(pool, fiatCurrency: fiatCurrency, formatter: formatter),
                isHalted: isCoinHalted(coin, haltedChains: haltedChains)
            )
        }
    }

    private func makePriceFormatter(for fiatCurrency: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = fiatCurrency
        formatter.maximumFractionDigits = 2
        return formatter
    }

    // MARK: - Private: Filtering and Sorting

    private func matchesSearch(_ item: CoinDisplayItem, query: String) -> Bool {
        item.coin.name.localizedCaseInsensitiveContains(query) ||
        item.coin.code.localizedCaseInsensitiveContains(query)
    }

    private func sortCoins(_ items: [CoinDisplayItem]) -> [CoinDisplayItem] {
        items.sorted { a, b in
            let codeComparison = a.coin.code.localizedCaseInsensitiveCompare(b.coin.code)
            if codeComparison != .orderedSame { return codeComparison == .orderedAscending }
            return a.coin.name.localizedCaseInsensitiveCompare(b.coin.name) == .orderedAscending
        }
    }

    // MARK: - Private: Helpers

    private func isCoinHalted(_ coin: MayaCryptoCurrency, haltedChains: Set<String>) -> Bool {
        haltedChains.contains(coin.chain.uppercased())
    }

    private func priceForCoin(_ pool: MayaPool, fiatCurrency: String, formatter: NumberFormatter) -> String? {
        guard let priceUSD = pool.priceUSD, priceUSD > 0 else { return nil }
        guard let fiatAmount = convertUSDToFiat(usdAmount: priceUSD, fiatCurrency: fiatCurrency) else { return nil }
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

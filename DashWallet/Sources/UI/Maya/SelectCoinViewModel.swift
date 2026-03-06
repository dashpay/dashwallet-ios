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

import Foundation
import Combine

struct CoinDisplayItem: Identifiable {
    let id: String
    let coin: MayaCryptoCurrency
    let fiatPrice: String?
    let isHalted: Bool
}

@MainActor
class SelectCoinViewModel: ObservableObject {
    @Published var coins: [CoinDisplayItem] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasHaltedCoins: Bool = false
    @Published var showHaltedToast: Bool = false

    var filteredCoins: [CoinDisplayItem] {
        if searchText.isEmpty {
            return coins
        }
        return coins.filter { item in
            item.coin.name.localizedCaseInsensitiveContains(searchText) ||
            item.coin.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadCoins() async {
        isLoading = true
        errorMessage = nil

        do {
            async let poolsRequest = MayaAPIService.shared.fetchPools()
            async let inboundRequest = MayaAPIService.shared.fetchInboundAddresses()

            let (pools, inboundAddresses) = try await (poolsRequest, inboundRequest)

            let poolsByAsset = Dictionary(pools.map { ($0.asset, $0) }, uniquingKeysWith: { first, _ in first })
            let haltedChains = Set(inboundAddresses.filter { $0.halted }.map { $0.chain })

            let fiatCurrency = App.fiatCurrency
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = fiatCurrency
            formatter.maximumFractionDigits = 2

            var items: [CoinDisplayItem] = []

            for coin in MayaCryptoCurrency.supportedCoins {
                guard let pool = poolsByAsset[coin.mayaAsset] else { continue }

                let isHalted = haltedChains.contains(coin.chain)
                var priceString: String?

                if let priceUSD = pool.priceUSD, priceUSD > 0 {
                    let fiatAmount = convertUSDToFiat(usdAmount: priceUSD, fiatCurrency: fiatCurrency)
                    if let fiatAmount {
                        priceString = formatter.string(from: NSNumber(value: fiatAmount))
                    }
                }

                items.append(CoinDisplayItem(
                    id: coin.id,
                    coin: coin,
                    fiatPrice: priceString,
                    isHalted: isHalted
                ))
            }

            // Sort: available coins first, then halted; alphabetically within each group
            items.sort { a, b in
                if a.isHalted != b.isHalted {
                    return !a.isHalted
                }
                return a.coin.name < b.coin.name
            }

            coins = items
            hasHaltedCoins = items.contains { $0.isHalted }
            showHaltedToast = hasHaltedCoins
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func convertUSDToFiat(usdAmount: Double, fiatCurrency: String) -> Double? {
        if fiatCurrency == "USD" {
            return usdAmount
        }

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

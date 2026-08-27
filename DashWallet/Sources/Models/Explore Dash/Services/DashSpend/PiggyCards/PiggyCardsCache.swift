//
//  Created by Dash Core Group
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

/// In-memory cache for PiggyCards gift cards and exchange rates
/// Matches Android implementation for consistent behavior
class PiggyCardsCache {
    static let shared = PiggyCardsCache()

    // Cache for gift cards by merchant ID
    private var giftCardCache: [String: [PiggyCardsGiftcard]] = [:]
    private let giftCardQueue = DispatchQueue(label: "piggyCardsCache.giftCard", attributes: .concurrent)

    // Cache for exchange rates
    private var exchangeRateCache: [String: PiggyCardsExchangeRateResult] = [:]
    private let exchangeRateQueue = DispatchQueue(label: "piggyCardsCache.exchangeRate", attributes: .concurrent)

    // Cache for disabled gift cards (brandId -> [names])
    private let disabledGiftCards: [Int: [String]] = [
        174: ["Xbox Live", "Xbox Game Pass"]
    ]

    private init() {}

    // MARK: - Gift Card Cache

    func storeGiftCards(_ cards: [PiggyCardsGiftcard], forMerchant merchantId: String) {
        giftCardQueue.async(flags: .barrier) {
            self.giftCardCache[merchantId] = cards
        }
    }

    func getGiftCards(forMerchant merchantId: String) -> [PiggyCardsGiftcard]? {
        giftCardQueue.sync {
            return giftCardCache[merchantId]
        }
    }

    func clearGiftCardCache() {
        giftCardQueue.async(flags: .barrier) {
            self.giftCardCache.removeAll()
        }
    }

    // MARK: - Exchange Rate Cache

    func storeExchangeRate(_ rate: PiggyCardsExchangeRateResult, forCurrency currency: String) {
        exchangeRateQueue.async(flags: .barrier) {
            self.exchangeRateCache[currency] = rate
        }
    }

    func getExchangeRate(forCurrency currency: String) -> PiggyCardsExchangeRateResult? {
        exchangeRateQueue.sync {
            return exchangeRateCache[currency]
        }
    }

    func clearExchangeRateCache() {
        exchangeRateQueue.async(flags: .barrier) {
            self.exchangeRateCache.removeAll()
        }
    }

    // MARK: - Gift Card Selection

    /// Find the best gift card for a given denomination
    /// Priority: Instant delivery fixed > Regular fixed > Range > Option
    func selectGiftCard(from cards: [PiggyCardsGiftcard], forAmount amount: Double) -> PiggyCardsGiftcard? {
        // Filter out disabled cards
        let enabledCards = cards.filter { card in
            guard let disabledNames = disabledGiftCards[card.brandId] else { return true }
            return !disabledNames.contains { card.name.contains($0) }
        }.filter { $0.quantity > 0 } // Only available cards

        // Priority 1: Instant delivery fixed cards with exact denomination
        if let instantCard = enabledCards.first(where: { card in
            card.priceType.trimmingCharacters(in: .whitespaces).lowercased() == PiggyCardsPriceType.fixed.rawValue &&
            card.name.contains("INSTANT DELIVERY") &&
            Double(card.denomination) == amount
        }) {
            return instantCard
        }

        // Priority 2: Regular fixed cards with exact denomination
        if let fixedCard = enabledCards.first(where: { card in
            card.priceType.trimmingCharacters(in: .whitespaces).lowercased() == PiggyCardsPriceType.fixed.rawValue &&
            Double(card.denomination) == amount
        }) {
            return fixedCard
        }

        // Priority 3: Range cards that include the amount
        if let rangeCard = enabledCards.first(where: { card in
            card.priceType.trimmingCharacters(in: .whitespaces).lowercased() == PiggyCardsPriceType.range.rawValue &&
            amount >= card.minDenomination &&
            amount <= card.maxDenomination
        }) {
            return rangeCard
        }

        // Priority 4: Option cards that include the denomination
        if let optionCard = enabledCards.first(where: { card in
            card.priceType.trimmingCharacters(in: .whitespaces).lowercased() == PiggyCardsPriceType.option.rawValue &&
            card.denomination.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.contains(amount)
        }) {
            return optionCard
        }

        return nil
    }

    // MARK: - Cleanup

    func clearAllCaches() {
        clearGiftCardCache()
        clearExchangeRateCache()
    }
}
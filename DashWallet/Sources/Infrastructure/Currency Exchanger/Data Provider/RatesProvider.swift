//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - RatesProvider

protocol RatesProvider: AnyObject {
    var updateHandler: (([DSCurrencyPriceObject]) -> Void)? { get set }

    func startExchangeRateFetching()
}

// MARK: - RatesProviderFactory

enum RatesProviderFactory {
    static var base: RatesProvider { BaseRatesProvider() }
}

// MARK: - BaseRatesProvider

final class BaseRatesProvider: NSObject, RatesProvider {
    private let kRefreshTimeInterval: TimeInterval = 60
    private let kPriceByCodeKey = "DS_PRICEMANAGER_PRICESBYCODE"
    var updateHandler: (([DSCurrencyPriceObject]) -> Void)?

    private var lastPriceSourceInfo: String!
    private var pricesByCode: [String: DSCurrencyPriceObject]!
    private var plainPricesByCode: [String: NSNumber]!

    private let operationQueue: DSOperationQueue

    override init() {
        operationQueue = DSOperationQueue()

        super.init()
    }

    func startExchangeRateFetching() {
        updatePrices()
    }

    @objc
    func updatePrices() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Int(kRefreshTimeInterval))) { [weak self] in
            self?.updatePrices()
        }

        let priceOperation = DSPriceOperationProvider.fetchPrices { [weak self] prices, priceSource in
            guard let self, let prices else { return }

            var pricesByCode: [String: DSCurrencyPriceObject] = [:]
            var plainPricesByCode: [String: NSNumber] = [:]

            for rate in prices {
                pricesByCode[rate.code] = rate
                plainPricesByCode[rate.code] = rate.price
            }

            self.lastPriceSourceInfo = priceSource
            self.pricesByCode = pricesByCode
            self.plainPricesByCode = plainPricesByCode

            UserDefaults.standard.set(plainPricesByCode, forKey: self.kPriceByCodeKey)

            var array = pricesByCode
                .map { $0.value }
                .sorted(by: { $0.code < $1.code })

            let euroObj = pricesByCode["EUR"]!
            let usdObj = pricesByCode["USD"]!

            array.removeAll(where: { $0 == euroObj || $0 == usdObj })
            array.insert(euroObj, at: 0)
            array.insert(usdObj, at: 0)

            self.updateHandler?(array)
        }

        operationQueue.addOperation(priceOperation)
    }
}

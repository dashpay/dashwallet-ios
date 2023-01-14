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

            // TODO: save prices in different way
            var plainPricesByCode: [String: NSNumber] = [:]

            for rate in prices {
                plainPricesByCode[rate.code] = rate.price
            }

            UserDefaults.standard.set(plainPricesByCode, forKey: self.kPriceByCodeKey)

            self.lastPriceSourceInfo = priceSource
            self.updateHandler?(prices)
        }

        operationQueue.addOperation(priceOperation)
    }
}

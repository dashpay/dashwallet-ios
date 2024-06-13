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
import Combine

// MARK: - RateObject

struct RateObject {
    let code: String
    let name: String
    let price: Decimal
}

// MARK: Equatable

extension RateObject: Equatable {
    static func == (rhs: RateObject, lhs: RateObject) -> Bool {
        let haveEqualCodeObjects = rhs.code == lhs.code

        if !haveEqualCodeObjects {
            return false
        }

        let haveEqualNameObjects = rhs.name == lhs.name
        if !haveEqualNameObjects {
            return false
        }

        let haveEqualPriceObjects = rhs.price == lhs.price

        if !haveEqualPriceObjects {
            return false
        }

        return true
    }
}

// MARK: - RatesProvider

protocol RatesProvider: AnyObject {
    var updateHandler: (([RateObject]) -> Void)? { get set }

    func startExchangeRateFetching()
}

// MARK: - RatesProviderFactory

enum RatesProviderFactory {
    static var base: RatesProvider = BaseRatesProvider.shared
}

// MARK: - BaseRatesProvider

final class BaseRatesProvider: NSObject, RatesProvider {
    private var cancellableBag = Set<AnyCancellable>()
    static var shared: BaseRatesProvider = BaseRatesProvider()
    
    private var lastPriceSourceInfo: String!
    private let operationQueue: DSOperationQueue

    var updateHandler: (([RateObject]) -> Void)? {
        didSet {
            self.emitRates()
        }
    }
    
    var lastUpdated: Int {
        get { UserDefaults.standard.integer(forKey: LAST_RATES_RETRIEVAL_TIME) }
    }
    
    @Published private(set) var hasFetchError: Bool = false
    @Published private(set) var isVolatile: Bool = false

    override init() {
        operationQueue = DSOperationQueue()
        super.init()
    }

    func startExchangeRateFetching() {
        // TODO: migrate rate fetching from DashSync to here
        NotificationCenter.default.publisher(for: NSNotification.Name.DSExchangeRatesReported)
            .sink { [weak self] notification in
                if let error = notification.userInfo?[DSExchangeRatesErrorKey] as? NSError {
                    if error.domain == NSURLErrorDomain {
                        self?.hasFetchError = true
                    }
                } else {
                    self?.hasFetchError = false
                    self?.emitRates()
                    self?.isVolatile = DSPriceManager.sharedInstance().isVolatile
                }
            }
            .store(in: &cancellableBag)
    }
    
    private func emitRates() {
        if let plainPricesByCode = UserDefaults.standard.object(forKey: PRICESBYCODE_KEY) as? [String : NSNumber] {
            let rates = plainPricesByCode.map { code, rate in
                RateObject(code: code, name: currencyName(fromCode: code), price: rate.decimalValue)
            }
            updateHandler?(rates)
        }
    }
    
    func currencyName(fromCode code: String) -> String {
        let locale = Locale.current
        let currencyName = locale.localizedString(forCurrencyCode: code)
        
        return currencyName ?? code
    }
}

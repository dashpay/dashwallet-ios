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

import XCTest
@testable import dashwallet

// MARK: - MockRatesProvider

class MockRatesProvider: RatesProvider {
    var updateHandler: (([DSCurrencyPriceObject]) -> Void)?

    func startExchangeRateFetching() {
        if let path = Bundle.main.path(forResource: "rates", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                let rates = try JSONDecoder().decode(BaseDataResponse<CoinbaseExchangeRate>.self, from: data).data.rates!

                var array: [DSCurrencyPriceObject] = []
                array.reserveCapacity(rates.count)

                for rate in rates {
                    let key = rate.key
                    let price = Decimal(string: rate.value)! as NSNumber
                    array.append(DSCurrencyPriceObject(code: key, name: key, price: price)!)
                }

                updateHandler?(array)
            } catch {
                fatalError("Cannot read json")
            }
        }
    }
}

// MARK: - AmountObjectTests

final class AmountObjectTests: XCTestCase {

    private var currencyExchanger = CurrencyExchanger(dataProvider: MockRatesProvider())

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }


    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testRetrieveLocalAmount() {
        let inputFormats: [String] = [
            "0%@0",
            "3%@",
            "4%@0",
            "56%@00",
            "123%@45",
            "34%@70",
        ]

        let weirdLocaleIdentifiers: Set<String> = ["fr_CH", "kea_CV", "pt_CV", "en_CV"]

        for item in Locale.availableIdentifiers {
            if weirdLocaleIdentifiers.contains(item) { continue }

            let locale = Locale(identifier: item)
            if locale.isNonArabicDigitsLocale { continue }
            guard let currencyCode = locale.currencyCode else { continue }

            for inputFormat in inputFormats {
                let input = String(format: inputFormat, locale.decimalSeparator!)
                let inputNumber = Decimal(string: input, locale: locale)!

                let mainAmount = AmountObject(plainAmount: inputNumber.plainDashAmount,
                                              fiatCurrencyCode: currencyCode,
                                              localFormatter: NumberFormatter.fiatFormatter(currencyCode: currencyCode),
                                              currencyExchanger: currencyExchanger)
                XCTAssert(mainAmount.localAmount.plainAmount == mainAmount.plainAmount)
            }
        }
    }

    func testRetrieveDashAmount() {
        let inputFormats: [String] = [
            "0%@0",
            "3%@",
            "4%@0",
            "56%@00",
            "123%@45",
            "34%@70",
        ]

        let weirdLocaleIdentifiers: Set<String> = ["fr_CH", "kea_CV", "pt_CV", "en_CV"]

        for item in Locale.availableIdentifiers {
            if weirdLocaleIdentifiers.contains(item) { continue }

            let locale = Locale(identifier: item)
            if locale.isNonArabicDigitsLocale { continue }
            guard let currencyCode = locale.currencyCode else { continue }

            for inputFormat in inputFormats {
                let input = String(format: inputFormat, locale.decimalSeparator!)
                let inputNumber = Decimal(string: input, locale: locale)!

                let mainAmount = AmountObject(plainAmount: inputNumber.plainDashAmount,
                                              fiatCurrencyCode: currencyCode,
                                              localFormatter: NumberFormatter.fiatFormatter(currencyCode: currencyCode),
                                              currencyExchanger: currencyExchanger)
                XCTAssert(mainAmount.localAmount.dashAmount.plainAmount == mainAmount.plainAmount)
            }
        }
    }

    func testSwaping() {
        let numbers: [String] = ["0", "2", "300", "0.1", "0.09", "1.0", "1.0003", "10.79", "0.00054321"]
        let currencyCode = "USD"

        for item in numbers {
            let amount = AmountObject(dashAmountString: item,
                                      fiatCurrencyCode: currencyCode,
                                      localFormatter: NumberFormatter.fiatFormatter(currencyCode: currencyCode),
                                      currencyExchanger: currencyExchanger)

            XCTAssert(amount.plainAmount == Decimal(string: item)!.plainDashAmount)

            let localAmount = amount.localAmount
            XCTAssert(amount.plainAmount == localAmount.plainAmount)
            XCTAssert(amount.supplementaryFormatted == localAmount.supplementaryFormatted)
        }
    }
}

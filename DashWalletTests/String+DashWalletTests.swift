//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - String_DashWallet

final class String_DashWallet: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testAssumptionThatCurrencySymbolIsEitherAtTheBeginningOrAtTheEnd() throws {
        let currencySymbol = "¤"
        let nullAndLeftToRight = "\u{0000200e}"
        let identifiers = Locale.availableIdentifiers
        for item in identifiers {
            let locale = Locale(identifier: item)
            let numberFormatter = NumberFormatter.formatter(for: locale)
            let format = numberFormatter.positiveFormat!

            let currencySymbolRange = format.nsRange(of: currencySymbol)
            XCTAssert(currencySymbolRange.location != NSNotFound, "Invalid number format")

            let isCurrencySymbolAtTheBeginning = currencySymbolRange.location == 0;
            let isCurrencySymbolAtTheEnd = (currencySymbolRange.location + currencySymbolRange.length) == format.count

            if !isCurrencySymbolAtTheBeginning && !isCurrencySymbolAtTheEnd {
                // skip check for Persian formats "fa", "fa_IR"

                if format.hasPrefix(nullAndLeftToRight) {
                    XCTAssert(item == "fa" || item == "fa_IR");
                    continue;
                }
            }

            XCTAssert(isCurrencySymbolAtTheBeginning || isCurrencySymbolAtTheEnd, "Invalid number format \(format) for locale \(item)");
        }
    }

    func testCurrencySymbolExtraction() {
        let numbers: [Double] = [0, 2, 300, 0.1, 0.09, 1.0, 1.0003, 10.79, 0.00054321]
        for item in Locale.availableIdentifiers {
            let locale = Locale(identifier: item)
            let numberFormatter = NumberFormatter.formatter(for: locale)

            for number in numbers {
                let number = Decimal(number)

                let formattedNumber = numberFormatter.string(from: number as NSNumber)!
                let currencySymbol = formattedNumber.extractCurrencySymbol(using: numberFormatter)!

                if currencySymbol.isEmpty, item.hasSuffix("_CV") {
                    continue
                }

                XCTAssert(!currencySymbol.isEmpty,
                          "Failed for \(item) \(number): '\(formattedNumber)' (symbol \(String(describing: numberFormatter.currencySymbol)))")
                XCTAssert(currencySymbol.count < formattedNumber.count,
                          "Failed for \(item) \(number): '\(formattedNumber)' (symbol \(String(describing: numberFormatter.currencySymbol)))")
            }
        }
    }

    func testWYSIWYGForInputWithFractions() {
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

            let numberFormatter = NumberFormatter.formatter(for: locale)
            numberFormatter.roundingMode = .down

            for inputFormat in inputFormats {
                let input = String(format: inputFormat, locale.decimalSeparator!)

                let inputNumber = Decimal(string: input, locale: locale)!
                let wysiwygResult = numberFormatter.inputString(from: inputNumber as NSNumber, and: input, locale: locale)!

                let inputStringRange = wysiwygResult.nsRange(of: input)
                XCTAssert(inputStringRange.location != NSNotFound,
                          "Failed with input \(input) result \(wysiwygResult) for \(item)")
            }
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}

extension NumberFormatter {
    static func formatter(for locale: Locale) -> NumberFormatter {
        let numberFormatter = NumberFormatter()
        numberFormatter.isLenient = true
        numberFormatter.numberStyle = .currency
        numberFormatter.generatesDecimalNumbers = true
        numberFormatter.locale = locale

        return numberFormatter
    }
}

extension Locale {
    var isNonArabicDigitsLocale: Bool {
        let arabicDigitsSet = CharacterSet(charactersIn: "1234567890")
        let decimal = Decimal(string: "1234567890", locale: self)!

        let testNumberFormatter = NumberFormatter()
        testNumberFormatter.locale = self

        let string = testNumberFormatter.string(from: decimal as NSNumber)!
        let testResultSet = CharacterSet(charactersIn: string)

        return !testResultSet.isSuperset(of: arabicDigitsSet)
    }
}

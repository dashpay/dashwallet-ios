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
    var updateHandler: (([RateObject]) -> Void)?

    func startExchangeRateFetching() {
        if let path = Bundle(for: Self.self).path(forResource: "rates", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
                let rates = try JSONDecoder().decode(BaseDataResponse<CoinbaseExchangeRate>.self, from: data).data.rates!

                var array: [RateObject] = []
                array.reserveCapacity(rates.count)

                for rate in rates {
                    let key = rate.key
                    let price = Decimal(string: rate.value)! as NSNumber
                    array.append(RateObject(code: key, name: key, price: price.decimalValue))
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
        currencyExchanger.startExchangeRateFetching()
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
            "3412323234%@70",
        ]

        let weirdLocaleIdentifiers: Set<String> = ["fr_CH", "kea_CV", "pt_CV", "en_CV"]

        for item in Locale.availableIdentifiers {
            if weirdLocaleIdentifiers.contains(item) { continue }

            let locale = Locale(identifier: item)
            if locale.isNonArabicDigitsLocale { continue }
            guard let currencyCode = locale.currencyCode else { continue }

            let localFormatter = NumberFormatter.fiatFormatter(currencyCode: currencyCode)
            for inputFormat in inputFormats {
                let input = String(format: inputFormat, locale.decimalSeparator!)
                let inputNumber = Decimal(string: input, locale: locale)!

                let amount = AmountObject(plainAmount: inputNumber.plainDashAmount,
                                          fiatCurrencyCode: currencyCode,
                                          localFormatter: localFormatter,
                                          currencyExchanger: currencyExchanger)

                let numberFormatter = localFormatter.copy() as! NumberFormatter
                numberFormatter.numberStyle = .none
                numberFormatter.minimumFractionDigits = localFormatter.minimumFractionDigits
                numberFormatter.maximumFractionDigits = localFormatter.maximumFractionDigits
                let inputValue = numberFormatter.string(from: amount.supplementaryAmount as NSDecimalNumber)!

                XCTAssert(amount.localAmount.amountInternalRepresentation == inputValue)
            }
        }
    }

    func testSwapingFromMainToLocal() {
        let numbers = ["1234.43"]
        let currencyCode = "USD"

        for (i, item) in numbers.enumerated() {
            let localFormatter = NumberFormatter.fiatFormatter(currencyCode: currencyCode)

            let amount = AmountObject(dashAmountString: item,
                                      fiatCurrencyCode: currencyCode,
                                      localFormatter: localFormatter,
                                      currencyExchanger: currencyExchanger)

            XCTAssert(amount.plainAmount == Decimal(string: item)!.plainDashAmount)

            let localAmount = amount.localAmount
            XCTAssert(amount.plainAmount == localAmount.plainAmount)

            let numberFormatter = localFormatter.copy() as! NumberFormatter
            numberFormatter.numberStyle = .none
            numberFormatter.minimumFractionDigits = localFormatter.minimumFractionDigits
            numberFormatter.maximumFractionDigits = localFormatter.maximumFractionDigits
            let input = numberFormatter.string(from: amount.supplementaryAmount as NSDecimalNumber)!

            XCTAssert(localAmount.amountInternalRepresentation == input)
        }
    }
}

// MARK: - BaseAmountModelKeyboardInputTests

final class BaseAmountModelKeyboardInputTests: XCTestCase {

    private func makeModel(localeIdentifier: String) -> BaseAmountModel {
        BaseAmountModel(inputLocale: Locale(identifier: localeIdentifier))
    }

    private func expectedPlainAmount(for input: String, locale: Locale) -> UInt64 {
        guard !input.isEmpty else { return 0 }

        let decimalSeparator = locale.decimalSeparator ?? "."
        let sanitizedInput = input.hasSuffix(decimalSeparator)
            ? String(input.dropLast(decimalSeparator.count))
            : input

        guard !sanitizedInput.isEmpty else { return 0 }
        return Decimal(string: sanitizedInput, locale: locale)?.plainDashAmount ?? 0
    }

    func testKeyboardInputAPIAcceptsDotLocaleValues() {
        let locale = Locale(identifier: "en_US")
        let model = makeModel(localeIdentifier: locale.identifier)

        model.updateKeyboardInputString("0.12345678")

        XCTAssertEqual(model.currentInputString, "0.12345678")
        XCTAssertEqual(model.currentKeyboardInputString, "0.12345678")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "0.12345678", locale: locale))
        XCTAssertTrue(model.isAllowedToContinue)
    }

    func testKeyboardInputAPIAcceptsCommaLocaleValues() {
        let locale = Locale(identifier: "de_DE")
        let model = makeModel(localeIdentifier: locale.identifier)

        model.updateKeyboardInputString("0,12345678")

        XCTAssertEqual(model.currentInputString, "0,12345678")
        XCTAssertEqual(model.currentKeyboardInputString, "0,12345678")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "0,12345678", locale: locale))
        XCTAssertTrue(model.isAllowedToContinue)
    }

    func testKeyboardInputAPIRejectsFractionOverflow() {
        let locale = Locale(identifier: "en_US")
        let model = makeModel(localeIdentifier: locale.identifier)

        model.updateKeyboardInputString("0.12345678")
        model.updateKeyboardInputString("0.123456789")

        XCTAssertEqual(model.currentInputString, "0.12345678")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "0.12345678", locale: locale))
    }

    func testKeyboardInputAPIPreservesDeleteStateIncludingEmptyString() {
        let locale = Locale(identifier: "en_US")
        let model = makeModel(localeIdentifier: locale.identifier)

        model.updateKeyboardInputString("1.2")
        model.updateKeyboardInputString("1.")
        XCTAssertEqual(model.currentInputString, "1.")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "1.", locale: locale))

        model.updateKeyboardInputString("1")
        XCTAssertEqual(model.currentInputString, "1")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "1", locale: locale))

        model.updateKeyboardInputString("")
        XCTAssertEqual(model.currentInputString, "")
        XCTAssertEqual(model.currentKeyboardInputString, "")
        XCTAssertEqual(model.amount.plainAmount, 0)
        XCTAssertFalse(model.isAllowedToContinue)
    }

    func testKeyboardInputAPINormalizesLeadingZerosAndRejectsMaximumOverflow() {
        let locale = Locale(identifier: "en_US")
        let model = makeModel(localeIdentifier: locale.identifier)

        model.updateKeyboardInputString("01")
        XCTAssertEqual(model.currentInputString, "1")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "1", locale: locale))

        model.updateKeyboardInputString("21000000")
        XCTAssertEqual(model.currentInputString, "21000000")
        XCTAssertEqual(model.amount.plainAmount, expectedPlainAmount(for: "21000000", locale: locale))

        model.updateKeyboardInputString("210000001")
        XCTAssertEqual(model.currentInputString, "21000000")

        model.updateKeyboardInputString("21000000.1")
        XCTAssertEqual(model.currentInputString, "21000000")
    }
}

// MARK: - PastedAmountParserTests

final class PastedAmountParserTests: XCTestCase {

    private struct Case {
        let pasted: String
        let editable: String
        let display: String
    }

    private func groupedDisplayString(for decimal: Decimal, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 20
        return formatter.string(from: decimal as NSDecimalNumber)!
    }

    private func groupedExpectation(integer: String, fraction: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        let groupingSeparator = formatter.groupingSeparator ?? ","
        let decimalSeparator = formatter.decimalSeparator ?? "."

        let groupedInteger = Self.group(integer, separator: groupingSeparator)
        guard !fraction.isEmpty else { return groupedInteger }
        return groupedInteger + decimalSeparator + fraction
    }

    private static func group(_ integer: String, separator: String) -> String {
        let characters = Array(integer)
        guard characters.count > 3 else { return integer }

        var parts: [String] = []
        var index = characters.count

        while index > 3 {
            parts.insert(String(characters[index - 3..<index]), at: 0)
            index -= 3
        }

        if index > 0 {
            parts.insert(String(characters[0..<index]), at: 0)
        }

        return parts.joined(separator: separator)
    }

    private func assertParsed(
        _ pasted: String,
        localeIdentifier: String,
        editable expectedEditable: String,
        display expectedDisplay: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let locale = Locale(identifier: localeIdentifier)
        guard let parsed = PastedAmountParser.parse(pasted, locale: locale) else {
            XCTFail("Expected a parsed value for \(pasted)", file: file, line: line)
            return
        }

        let normalizedExpectedEditable = expectedEditable.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        XCTAssertEqual(
            parsed.decimalValue,
            Decimal(string: normalizedExpectedEditable, locale: Locale(identifier: "en_US_POSIX")),
            file: file,
            line: line
        )
        XCTAssertEqual(
            PastedAmountParser.editableString(from: parsed.decimalValue, locale: locale),
            expectedEditable,
            file: file,
            line: line
        )
        XCTAssertEqual(
            groupedDisplayString(for: parsed.decimalValue, locale: locale),
            expectedDisplay,
            file: file,
            line: line
        )
    }

    func testUnitedStatesAcceptanceCases() {
        let locale = Locale(identifier: "en_US")
        let cases: [Case] = [
            .init(pasted: "0.1234", editable: "0.1234", display: "0.1234"),
            .init(pasted: "3.26", editable: "3.26", display: "3.26"),
            .init(pasted: "5,26", editable: "5.26", display: "5.26"),
            .init(pasted: "1,234.56", editable: "1234.56", display: "1,234.56"),
            .init(pasted: "1234,56", editable: "1234.56", display: "1,234.56"),
            .init(pasted: "1.234.567", editable: "1234567", display: "1,234,567"),
            .init(pasted: "$1,000.50", editable: "1000.50", display: "1,000.50"),
        ]

        for testCase in cases {
            assertParsed(
                testCase.pasted,
                localeIdentifier: locale.identifier,
                editable: testCase.editable,
                display: testCase.display
            )
        }
    }

    func testGermanAcceptanceCases() {
        let locale = Locale(identifier: "de_DE")
        let cases: [Case] = [
            .init(pasted: "0.1234", editable: "0,1234", display: "0,1234"),
            .init(pasted: "3.26", editable: "3,26", display: "3,26"),
            .init(pasted: "5,26", editable: "5,26", display: "5,26"),
            .init(pasted: "1,234.56", editable: "1234,56", display: "1.234,56"),
            .init(pasted: "1234,56", editable: "1234,56", display: "1.234,56"),
            .init(pasted: "1.234.567", editable: "1234567", display: "1.234.567"),
            .init(pasted: "$1,000.50", editable: "1000,50", display: "1.000,50"),
        ]

        for testCase in cases {
            assertParsed(
                testCase.pasted,
                localeIdentifier: locale.identifier,
                editable: testCase.editable,
                display: testCase.display
            )
        }
    }

    func testFrenchAndSwissGrouping() {
        let frenchLocale = Locale(identifier: "fr_FR")
        let swissLocale = Locale(identifier: "de_CH")

        assertParsed(
            "1\u{202F}234,56",
            localeIdentifier: frenchLocale.identifier,
            editable: "1234,56",
            display: groupedExpectation(integer: "1234", fraction: "56", locale: frenchLocale)
        )

        assertParsed(
            "1 234,56",
            localeIdentifier: frenchLocale.identifier,
            editable: "1234,56",
            display: groupedExpectation(integer: "1234", fraction: "56", locale: frenchLocale)
        )

        assertParsed(
            "€1.234,56",
            localeIdentifier: frenchLocale.identifier,
            editable: "1234,56",
            display: groupedExpectation(integer: "1234", fraction: "56", locale: frenchLocale)
        )

        assertParsed(
            "CHF 1’234.56",
            localeIdentifier: swissLocale.identifier,
            editable: "1234.56",
            display: groupedExpectation(integer: "1234", fraction: "56", locale: swissLocale)
        )

        assertParsed(
            "1'234.56",
            localeIdentifier: swissLocale.identifier,
            editable: "1234.56",
            display: groupedExpectation(integer: "1234", fraction: "56", locale: swissLocale)
        )
    }

    func testUkrainianGrouping() {
        let locale = Locale(identifier: "uk_UA")

        assertParsed(
            "1 234,56",
            localeIdentifier: locale.identifier,
            editable: "1234,56",
            display: groupedExpectation(integer: "1234", fraction: "56", locale: locale)
        )
    }

    func testRejectsMalformedScientificNegativeAndTextInput() {
        let locale = Locale(identifier: "en_US")

        XCTAssertNil(PastedAmountParser.parse("1e3", locale: locale))
        XCTAssertNil(PastedAmountParser.parse("-123.45", locale: locale))
        XCTAssertNil(PastedAmountParser.parse("12abc34", locale: locale))
        XCTAssertNil(PastedAmountParser.parse("", locale: locale))
    }

    func testLeadingSeparatorsNormalizeToZeroPrefixedValues() {
        assertParsed(
            ".5",
            localeIdentifier: "en_US",
            editable: "0.5",
            display: "0.5"
        )

        assertParsed(
            ",5",
            localeIdentifier: "en_US",
            editable: "0.5",
            display: "0.5"
        )
    }
}

//
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

/// Tests for `BaseAmountModel.normalizedPastedNumberString(from:)`, which makes pasting
/// amounts work regardless of the decimal/grouping convention of the pasted text or the
/// user's regional settings.
final class PastedAmountNormalizationTests: XCTestCase {

    private func normalize(_ input: String) -> String? {
        BaseAmountModel.normalizedPastedNumberString(from: input)
    }

    private func assertParsedNormalized(
        _ input: String,
        localeIdentifier: String,
        expected expectedNormalizedString: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let locale = Locale(identifier: localeIdentifier)
        guard let parsed = PastedAmountParser.parse(input, locale: locale) else {
            XCTFail("Expected a parsed value for \(input) in \(localeIdentifier)", file: file, line: line)
            return
        }

        XCTAssertEqual(parsed.normalizedString, expectedNormalizedString, file: file, line: line)
    }

    func testDotDecimalSeparator() {
        // The originally reported bug: pasting "0.12345" produced "12345" in comma locales.
        XCTAssertEqual(normalize("0.12345"), "0.12345")
        XCTAssertEqual(normalize("3.26"), "3.26")
    }

    func testCommaDecimalSeparator() {
        XCTAssertEqual(normalize("3,26"), "3.26")
        XCTAssertEqual(normalize("0,12345"), "0.12345")
    }

    func testGroupingAndDecimalCombined() {
        XCTAssertEqual(normalize("1,234.56"), "1234.56")  // US convention
        XCTAssertEqual(normalize("1.234,56"), "1234.56")  // EU convention
    }

    func testGroupingOnly() {
        XCTAssertEqual(normalize("1.234.567"), "1234567")
        XCTAssertEqual(normalize("1,234,567"), "1234567")
    }

    func testPlainIntegers() {
        XCTAssertEqual(normalize("326"), "326")
        XCTAssertEqual(normalize("0"), "0")
    }

    func testLeadingSeparator() {
        XCTAssertEqual(normalize(".5"), "0.5")
        XCTAssertEqual(normalize(",5"), "0.5")
    }

    func testStripsSurroundingNoise() {
        XCTAssertEqual(normalize("$1,000.50"), "1000.50")
        XCTAssertEqual(normalize(" 3,26 "), "3.26")
    }

    func testArabicDigitsAndSeparators() {
        assertParsedNormalized("١٬٢٣٤٫٥٦", localeIdentifier: "ar_EG", expectedNormalizedString: "1234.56")
        assertParsedNormalized("١٢٫٣٤", localeIdentifier: "ar_EG", expectedNormalizedString: "12.34")
    }

    func testInvalidInput() {
        XCTAssertNil(normalize("abc"))
        XCTAssertNil(normalize(""))
    }

    func testRegionalParserNormalizationMatrix() {
        struct Case {
            let localeIdentifier: String
            let input: String
            let expected: String
        }

        let cases: [Case] = [
            // US
            .init(localeIdentifier: "en_US", input: "0.1234", expected: "0.1234"),
            .init(localeIdentifier: "en_US", input: "3.26", expected: "3.26"),
            .init(localeIdentifier: "en_US", input: "1,234.56", expected: "1234.56"),
            .init(localeIdentifier: "en_US", input: "1,234", expected: "1234"),
            .init(localeIdentifier: "en_US", input: "1.234", expected: "1.234"),
            .init(localeIdentifier: "en_US", input: "1,234,567", expected: "1234567"),

            // European
            .init(localeIdentifier: "de_DE", input: "3,26", expected: "3.26"),
            .init(localeIdentifier: "de_DE", input: "1234,56", expected: "1234.56"),
            .init(localeIdentifier: "de_DE", input: "0,1234", expected: "0.1234"),
            .init(localeIdentifier: "de_DE", input: "1.234,56", expected: "1234.56"),
            .init(localeIdentifier: "de_DE", input: "1,234", expected: "1.234"),
            .init(localeIdentifier: "de_DE", input: "1.234", expected: "1234"),
            .init(localeIdentifier: "de_DE", input: "1.234.567", expected: "1234567"),
            .init(localeIdentifier: "fr_FR", input: "1 234,56", expected: "1234.56"),
            .init(localeIdentifier: "fr_FR", input: "1.234", expected: "1234"),

            // Swiss
            .init(localeIdentifier: "de_CH", input: "1'234.56", expected: "1234.56"),
            .init(localeIdentifier: "de_CH", input: "1'234'567", expected: "1234567"),
            .init(localeIdentifier: "de_CH", input: "1’234.56", expected: "1234.56"),
            .init(localeIdentifier: "de_CH", input: "1’234’567", expected: "1234567"),
            .init(localeIdentifier: "de_CH", input: "0.1234", expected: "0.1234"),
            .init(localeIdentifier: "de_CH", input: "3.26", expected: "3.26"),
            .init(localeIdentifier: "de_CH", input: "1'234", expected: "1234"),
            .init(localeIdentifier: "fr_CH", input: "1'234.56", expected: "1234.56"),
            .init(localeIdentifier: "fr_CH", input: "1'234'567", expected: "1234567"),

            // Cross-format robustness
            .init(localeIdentifier: "en_US", input: "$1,000.50", expected: "1000.50"),
            .init(localeIdentifier: "en_US", input: " 3,26 ", expected: "3.26"),
            .init(localeIdentifier: "de_DE", input: "1,234.56", expected: "1234.56"),
            .init(localeIdentifier: "de_DE", input: "1.234,56", expected: "1234.56")
        ]

        for testCase in cases {
            assertParsedNormalized(
                testCase.input,
                localeIdentifier: testCase.localeIdentifier,
                expected: testCase.expected
            )
        }
    }
}

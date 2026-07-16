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

final class NumericKeyboardLocaleSupportTests: XCTestCase {

    private func locale(_ identifier: String) -> Locale {
        Locale(identifier: identifier)
    }

    func testDecimalSeparatorMatchesLocale() {
        XCTAssertEqual(NumericKeyboardLocaleSupport.decimalSeparator(for: locale("en_US")), ".")
        XCTAssertEqual(NumericKeyboardLocaleSupport.decimalSeparator(for: locale("de_DE")), ",")
        XCTAssertEqual(NumericKeyboardLocaleSupport.decimalSeparator(for: locale("uk_UA")), ",")
        XCTAssertEqual(NumericKeyboardLocaleSupport.decimalSeparator(for: locale("fr_FR")), ",")
    }

    func testRowsUseConfiguredLocaleSeparator() {
        XCTAssertEqual(
            NumericKeyboardLocaleSupport.rows(showDecimalSeparator: true, locale: locale("en_US")).last,
            [".", "0", "⌫"]
        )

        XCTAssertEqual(
            NumericKeyboardLocaleSupport.rows(showDecimalSeparator: true, locale: locale("de_DE")).last,
            [",", "0", "⌫"]
        )

        XCTAssertEqual(
            NumericKeyboardLocaleSupport.rows(showDecimalSeparator: false, locale: locale("fr_FR")).last,
            ["", "0", "⌫"]
        )
    }

    func testApplyKeyPressUsesLocaleDecimalSeparatorAndPreventsDuplicates() {
        let locale = locale("de_DE")

        var value = ""
        value = NumericKeyboardLocaleSupport.applyKeyPress(
            value: value,
            key: "1",
            showDecimalSeparator: true,
            locale: locale
        )
        value = NumericKeyboardLocaleSupport.applyKeyPress(
            value: value,
            key: ",",
            showDecimalSeparator: true,
            locale: locale
        )
        value = NumericKeyboardLocaleSupport.applyKeyPress(
            value: value,
            key: "2",
            showDecimalSeparator: true,
            locale: locale
        )
        let duplicate = NumericKeyboardLocaleSupport.applyKeyPress(
            value: value,
            key: ",",
            showDecimalSeparator: true,
            locale: locale
        )

        XCTAssertEqual(value, "1,2")
        XCTAssertEqual(duplicate, "1,2")
    }

    func testApplyKeyPressIgnoresGroupingSeparatorAndSupportsDelete() {
        let locale = locale("en_US")
        let groupingSeparator = locale.groupingSeparator ?? ","

        let afterGroupingSeparator = NumericKeyboardLocaleSupport.applyKeyPress(
            value: "1234",
            key: groupingSeparator,
            showDecimalSeparator: true,
            locale: locale
        )

        let afterDelete = NumericKeyboardLocaleSupport.applyKeyPress(
            value: "1234",
            key: "⌫",
            showDecimalSeparator: true,
            locale: locale
        )

        XCTAssertEqual(afterGroupingSeparator, "1234")
        XCTAssertEqual(afterDelete, "123")
    }
}

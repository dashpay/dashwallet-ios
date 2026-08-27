//
//  Created by Codex
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

final class DashAmountFormatterTests: XCTestCase {

    func testGeneralDashFormatterSupportsEightFractionDigitsWithoutTrailingZeros() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            DashAmountFormatter.formattedDashAmountWithoutCurrencySymbol(Decimal(string: "0.12345678")!, locale: locale),
            "0.12345678"
        )
        XCTAssertEqual(
            DashAmountFormatter.formattedDashAmountWithoutCurrencySymbol(Decimal(string: "1.50000000")!, locale: locale),
            "1.5"
        )
        XCTAssertEqual(NumberFormatter.dashFormatter.maximumFractionDigits, 8)
    }

    func testGeneralDashFormatterUsesLocalizedDecimalSeparators() {
        let locale = Locale(identifier: "de_DE")

        XCTAssertEqual(
            DashAmountFormatter.formattedDashAmountWithoutCurrencySymbol(Decimal(string: "0.12345678")!, locale: locale),
            "0,12345678"
        )
    }
}

final class MayaAmountFormatterTests: XCTestCase {

    func testMayaDashFormatterRoundsDownToFiveFractionDigits() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            MayaAmountFormatter.dashDisplayString(Decimal(string: "0.12345678")!, locale: locale),
            "0.12345"
        )
        XCTAssertEqual(
            MayaAmountFormatter.dashDisplayString(Decimal(string: "0.99999999")!, locale: locale),
            "0.99999"
        )
    }

    func testMayaDashFormatterUsesLocalizedDecimalSeparators() {
        let locale = Locale(identifier: "de_DE")

        XCTAssertEqual(
            MayaAmountFormatter.dashDisplayString(Decimal(string: "0.12345678")!, locale: locale),
            "0,12345"
        )
    }

    func testMayaCoinFormatterKeepsEightDecimalsAndUsesLocalizedSeparators() {
        let enLocale = Locale(identifier: "en_US")
        let deLocale = Locale(identifier: "de_DE")
        let amount = Decimal(string: "0.12345678")!

        XCTAssertEqual(MayaAmountFormatter.coinDisplayString(amount, locale: enLocale), "0.12345678")
        XCTAssertEqual(MayaAmountFormatter.coinDisplayString(amount, locale: deLocale), "0,12345678")
    }
}

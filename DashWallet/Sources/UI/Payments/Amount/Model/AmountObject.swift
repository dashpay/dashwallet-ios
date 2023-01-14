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

import Foundation

// MARK: - AmountObject

struct AmountObject {
    let amountInternalRepresentation: String
    let plainAmount: Int64
    let amountType: AmountType

    let mainFormatted: String
    let supplementaryFormatted: String

    let localFormatter: NumberFormatter
    let fiatCurrencyCode: String

    init(dashAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter) {
        var dashAmountString = dashAmountString

        if dashAmountString.isEmpty {
            dashAmountString = "0"
        }

        amountType = .main
        amountInternalRepresentation = dashAmountString
        self.fiatCurrencyCode = fiatCurrencyCode
        self.localFormatter = localFormatter

        let dashNumber = Decimal(string: dashAmountString, locale: .current)!
        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber

        self.plainAmount = NSDecimalNumber(decimal: plainAmount).int64Value

        mainFormatted = NumberFormatter.dashFormatter
            .inputString(from: dashNumber as NSNumber, and: dashAmountString) ??
            NSLocalizedString("Invalid Input", comment: "Invalid Amount Input")

        if let localAmount = try? CurrencyExchanger.shared.convertDash(amount: dashNumber, to: fiatCurrencyCode),
           let str = localFormatter.string(from: localAmount as NSNumber) {
            supplementaryFormatted = str
        } else {
            supplementaryFormatted = NSLocalizedString("Updating Price", comment: "Updating Price")
        }
    }

    init?(localAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter) {
        var localAmountString = localAmountString

        if localAmountString.isEmpty {
            localAmountString = "0"
        }

        amountType = .supplementary
        amountInternalRepresentation = localAmountString
        self.fiatCurrencyCode = fiatCurrencyCode
        self.localFormatter = localFormatter

        let localNumber = Decimal(string: localAmountString, locale: .current)!
        let localCurrencyFormatted = localFormatter.inputString(from: localNumber as NSNumber, and: localAmountString)!
        supplementaryFormatted = localCurrencyFormatted

        if let dashAmount = try? CurrencyExchanger.shared.convertToDash(amount: localNumber, currency: fiatCurrencyCode),
           let str = NumberFormatter.dashFormatter.string(from: dashAmount as NSNumber) {
            plainAmount = Int64(dashAmount.plainDashAmount)
            mainFormatted = str
        } else {
            plainAmount = 0
            mainFormatted = "Error"
        }
    }

    init(plainAmount: Int64, fiatCurrencyCode: String, localFormatter: NumberFormatter) {
        let plainNumber = Decimal(plainAmount)
        let duffsNumber = Decimal(DUFFS)
        let dashNumber = plainNumber/duffsNumber
        let dashAmounString = NSDecimalNumber(decimal: dashNumber).description(withLocale: Locale.current)

        self.init(dashAmountString: dashAmounString, fiatCurrencyCode: fiatCurrencyCode, localFormatter: localFormatter)
    }
}

extension AmountObject {
    func dashAmount(dashValidator: DWAmountInputValidator, localFormatter: NumberFormatter,
                    currencyCode: String)
        -> AmountObject {
        if amountType == .main { return self }

        let number = NumberFormatter.dashFormatter.number(from: mainFormatted)!
        let rawAmount = dashValidator.stringFromNumber(usingInternalFormatter: number)!

        return AmountObject(amountInternalRepresentation: rawAmount, plainAmount: plainAmount, amountType: .main,
                            mainFormatted: mainFormatted, supplementaryFormatted: supplementaryFormatted,
                            localFormatter: localFormatter, fiatCurrencyCode: currencyCode)
    }

    func localAmount(localValidator: DWAmountInputValidator, localFormatter: NumberFormatter,
                     currencyCode: String)
        -> AmountObject {
        if amountType == .supplementary { return self }

        let number = localFormatter.number(from: supplementaryFormatted)!
        let rawAmount = localValidator.stringFromNumber(usingInternalFormatter: number)!

        return AmountObject(amountInternalRepresentation: rawAmount, plainAmount: plainAmount, amountType: .supplementary,
                            mainFormatted: mainFormatted, supplementaryFormatted: supplementaryFormatted,
                            localFormatter: localFormatter, fiatCurrencyCode: currencyCode)
    }

    init(amountInternalRepresentation: String, plainAmount: Int64, amountType: AmountType, mainFormatted: String,
         supplementaryFormatted: String, localFormatter: NumberFormatter, fiatCurrencyCode: String) {
        self.amountInternalRepresentation = amountInternalRepresentation
        self.plainAmount = plainAmount
        self.amountType = amountType
        self.mainFormatted = mainFormatted
        self.supplementaryFormatted = supplementaryFormatted
        self.localFormatter = localFormatter
        self.fiatCurrencyCode = fiatCurrencyCode
    }
}

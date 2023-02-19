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
    let amountType: AmountType
    let amountInternalRepresentation: String

    let plainAmount: UInt64
    let mainFormatted: String

    let supplementaryAmount: Decimal
    let supplementaryFormatted: String

    let localFormatter: NumberFormatter
    let fiatCurrencyCode: String

    init(dashAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter, currencyExchanger: CurrencyExchanger) {
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

        self.plainAmount = NSDecimalNumber(decimal: plainAmount.whole).uint64Value

        mainFormatted = NumberFormatter.dashFormatter
            .inputString(from: dashNumber as NSNumber, and: dashAmountString) ??
            NSLocalizedString("Invalid Input", comment: "Invalid Amount Input")

        if plainAmount == 0 {
            supplementaryAmount = 0
            supplementaryFormatted = localFormatter.string(from: 0.0)!
        } else if let localAmount = try? currencyExchanger.convertDash(amount: dashNumber, to: fiatCurrencyCode),
                  let str = localFormatter.string(from: localAmount as NSNumber) {
            supplementaryAmount = localAmount
            supplementaryFormatted = str
        } else {
            supplementaryAmount = 0
            supplementaryFormatted = NSLocalizedString("Updating Price", comment: "Updating Price")
        }
    }

    init?(localAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter, currencyExchanger: CurrencyExchanger) {
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
        supplementaryAmount = localNumber

        if localNumber.isZero {
            plainAmount = 0
            mainFormatted = NumberFormatter.dashFormatter.string(from: 0)!
        } else if let dashAmount = try? currencyExchanger.convertToDash(amount: localNumber, currency: fiatCurrencyCode),
                  let str = NumberFormatter.dashFormatter.string(from: dashAmount as NSNumber) {
            plainAmount = dashAmount.plainDashAmount
            mainFormatted = str
        } else {
            plainAmount = 0
            mainFormatted = NSLocalizedString("Updating Price", comment: "Updating Price")
        }
    }

    init(plainAmount: UInt64, fiatCurrencyCode: String, localFormatter: NumberFormatter, currencyExchanger: CurrencyExchanger) {
        let plainNumber = Decimal(plainAmount)
        let duffsNumber = Decimal(DUFFS)
        let dashNumber = plainNumber/duffsNumber
        let dashAmounString = NSDecimalNumber(decimal: dashNumber).description(withLocale: Locale.current)

        self.init(dashAmountString: dashAmounString, fiatCurrencyCode: fiatCurrencyCode, localFormatter: localFormatter, currencyExchanger: currencyExchanger)
    }
}

extension AmountObject {
    var dashAmount: AmountObject {
        if amountType == .main { return self }

        let amountInternalRepresentation = plainAmount.formattedDashAmountWithoutCurrencySymbol
        return object(with: amountInternalRepresentation, amountType: .main)
    }

    var localAmount: AmountObject {
        if amountType == .supplementary { return self }

        let numberFormatter = localFormatter.copy() as! NumberFormatter
        numberFormatter.numberStyle = .none
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = localFormatter.maximumFractionDigits

        guard let amountInternalRepresentation = numberFormatter.string(from: supplementaryAmount as NSDecimalNumber) else {
            fatalError("Can't convert dash amount: \(plainAmount.formattedDashAmount) to local amount. Supplementary Amount = \(String(describing: supplementaryAmount))")
        }

        return object(with: amountInternalRepresentation, amountType: .supplementary)
    }

    private func object(with internalRepresentation: String, amountType: AmountType) -> AmountObject {
        AmountObject(amountInternalRepresentation: internalRepresentation,
                     plainAmount: plainAmount,
                     supplementaryAmount: supplementaryAmount,
                     amountType: amountType,
                     mainFormatted: mainFormatted,
                     supplementaryFormatted: supplementaryFormatted,
                     localFormatter: localFormatter,
                     fiatCurrencyCode: fiatCurrencyCode)
    }

    init(amountInternalRepresentation: String, plainAmount: UInt64, supplementaryAmount: Decimal, amountType: AmountType, mainFormatted: String,
         supplementaryFormatted: String, localFormatter: NumberFormatter, fiatCurrencyCode: String) {
        self.amountInternalRepresentation = amountInternalRepresentation
        self.plainAmount = plainAmount
        self.supplementaryAmount = supplementaryAmount
        self.amountType = amountType
        self.mainFormatted = mainFormatted
        self.supplementaryFormatted = supplementaryFormatted
        self.localFormatter = localFormatter
        self.fiatCurrencyCode = fiatCurrencyCode
    }
}

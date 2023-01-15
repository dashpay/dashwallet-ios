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

// MARK: - AmountType

enum AmountType {
    case main
    case supplementary
}

// MARK: - AmountInputItem

struct AmountInputItem: Equatable {
    let currencyName: String
    let currencySymbol: String
    let currencyCode: String

    var isMain: Bool { currencySymbol == "DASH" }

    static let dash = AmountInputItem(currencyName: "Dash", currencySymbol: kDashCurrency, currencyCode: kDashCurrency)
}


// MARK: - BaseAmountModel

class BaseAmountModel {
    var activeAmountType: AmountType { currentInputItem.isMain ? .main : .supplementary }

    var mainAmount: AmountObject!
    var supplementaryAmount: AmountObject!
    var amount: AmountObject {
        activeAmountType == .main ? mainAmount : supplementaryAmount
    }

    var localCurrency: String {
        let locale = Locale.current as NSLocale
        return locale.displayName(forKey: .currencySymbol, value: localCurrencyCode)!
    }

    var error: Error? {
        didSet {
            if let error {
                errorHandler?(error)
            }
        }
    }

    var currentInputItem: AmountInputItem
    var inputItems: [AmountInputItem] = []

    public var errorHandler: ((Error) -> Void)?
    public var amountChangeHandler: ((AmountObject) -> Void)?
    public var isEnteredAmountLessThenMinimumOutputAmount: Bool {
        let chain = DWEnvironment.sharedInstance().currentChain
        let amount = amount.plainAmount

        return amount < chain.minOutputAmount
    }

    public var minimumOutputAmountFormattedString: String {
        let chain = DWEnvironment.sharedInstance().currentChain
        return chain.minOutputAmount.formattedDashAmount
    }

    internal var mainAmountValidator: DWAmountInputValidator!
    internal var supplementaryAmountValidator: DWAmountInputValidator!

    internal var localFormatter: NumberFormatter
    var localCurrencyCode: String

    init() {
        localCurrencyCode = App.fiatCurrency
        localFormatter = NumberFormatter.fiatFormatter(currencyCode: localCurrencyCode)

        let nsLocale = Locale.current as NSLocale
        let localCurrencySymbol = nsLocale.displayName(forKey: .currencySymbol, value: localCurrencyCode) ?? localCurrencyCode

        currentInputItem = .dash
        inputItems = [
            .init(currencyName: localCurrencyCode, currencySymbol: localCurrencySymbol, currencyCode: localCurrencyCode),
            currentInputItem,
        ]

        mainAmountValidator = DWAmountInputValidator(type: .dash)
        supplementaryAmountValidator = DWAmountInputValidator(type: .localCurrency)

        updateAmountObjects(with: "0")
    }

    func select(inputItem: AmountInputItem) {
        currentInputItem = inputItem
    }

    func selectInputItem(at index: Int) {
        currentInputItem = inputItems[index]
    }

    func setupCurrencyCode(_ code: String) {
        guard let price = try? CurrencyExchanger.shared.rate(for: code) else { return }

        localFormatter.currencyCode = code
        localCurrencyCode = code

        let max = NSDecimalNumber(value: MAX_MONEY/DUFFS)
        localFormatter.maximum = NSDecimalNumber(decimal: price).multiplying(by: max)

        rebuildAmounts()
    }

    func updateAmountObjects(with inputString: String) {
        if activeAmountType == .main {
            mainAmount = AmountObject(dashAmountString: inputString, fiatCurrencyCode: localCurrencyCode,
                                      localFormatter: localFormatter)
            supplementaryAmount = nil
        } else if let amount = AmountObject(localAmountString: inputString, fiatCurrencyCode: localCurrencyCode,
                                            localFormatter: localFormatter) {
            supplementaryAmount = amount
            mainAmount = nil
        }

        amountDidChange()
    }

    internal func updateCurrentAmountObject(with amount: Int64) {
        let amountObject = AmountObject(plainAmount: Int64(amount), fiatCurrencyCode: localCurrencyCode,
                                        localFormatter: localFormatter)
        updateCurrentAmountObject(with: amountObject)
    }

    internal func updateCurrentAmountObject(with newObject: AmountObject) {
        if activeAmountType == .main {
            mainAmount = newObject
            supplementaryAmount = nil
        } else {
            mainAmount = nil
            supplementaryAmount = newObject.localAmount(localValidator: supplementaryAmountValidator,
                                                        localFormatter: localFormatter, currencyCode: localCurrencyCode)
        }

        amountDidChange()
    }

    internal func rebuildAmounts() {
        let amount = activeAmountType == .main
            ? mainAmount.amountInternalRepresentation
            : supplementaryAmount.amountInternalRepresentation
        updateAmountObjects(with: amount)
    }

    internal func amountDidChange() {
        checkAmountForErrors()
        amountChangeHandler?(amount)
    }

    internal func checkAmountForErrors() { }
}

extension BaseAmountModel {
    var validator: DWInputValidator? {
        activeAmountType == .supplementary ? supplementaryAmountValidator : mainAmountValidator
    }

    var isAmountValidForProceeding: Bool {
        amount.plainAmount > 0
    }

    var isLocalCurrencySelected: Bool {
        activeAmountType == .supplementary
    }

    var isSwapToLocalCurrencyAllowed: Bool {
        CurrencyExchanger.shared.hasRate(for: localCurrencyCode)
    }

    var walletBalance: UInt64 {
        DWEnvironment.sharedInstance().currentWallet.balance
    }

    var walletBalanceFormatted: String {
        walletBalance.formattedDashAmount
    }
}

// MARK: AmountInputControlDataSource

extension BaseAmountModel: AmountInputControlDataSource {
    var currentInputString: String {
        amount.amountInternalRepresentation
    }

    var mainAmountString: String {
        amount.mainFormatted
    }

    var supplementaryAmountString: String {
        amount.supplementaryFormatted
    }
}

extension BaseAmountModel {
    @objc var isCurrencySelectorHidden: Bool {
        false
    }

    func updateInputField(with replacementText: String, in range: NSRange) {
        let lastInputString = amount.amountInternalRepresentation

        guard let validatedString = validator?.validatedString(fromLastInputString: lastInputString, range: range,
                                                               replacementString: replacementText) else {
            return
        }

        updateAmountObjects(with: validatedString)
    }

    func amountInputControlDidSwapInputs() {
        assert(isSwapToLocalCurrencyAllowed, "Switching until price is not fetched is not allowed")

        if activeAmountType == .main {
            if supplementaryAmount == nil {
                supplementaryAmount = mainAmount.localAmount(localValidator: supplementaryAmountValidator,
                                                             localFormatter: localFormatter, currencyCode: localCurrencyCode)
            }
        } else {
            if mainAmount == nil {
                mainAmount = supplementaryAmount.dashAmount(dashValidator: mainAmountValidator, localFormatter: localFormatter,
                                                            currencyCode: localCurrencyCode)
            }
        }

        amountDidChange()
    }

    func pasteFromClipboard() {
        guard var string = UIPasteboard.general.string else { return }
        string = string.localizedAmount()

        guard let decimal = Decimal(string: string, locale: .current) else { return }
        let decimalNumber = NSDecimalNumber(decimal: decimal)

        let formattedString: String?

        var formatter: NumberFormatter

        if activeAmountType == .main {
            formatter = NumberFormatter.dashFormatter.copy() as! NumberFormatter
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = NumberFormatter.dashFormatter.minimumFractionDigits
            formatter.maximumFractionDigits = NumberFormatter.dashFormatter.maximumFractionDigits
            formattedString = formatter.string(from: decimalNumber)
        } else {
            formatter = localFormatter.copy() as! NumberFormatter
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = localFormatter.minimumFractionDigits
            formatter.maximumFractionDigits = localFormatter.maximumFractionDigits
            formattedString = formatter.string(from: decimalNumber)
        }

        guard let string = formattedString else { return }

        updateAmountObjects(with: string)
    }
}

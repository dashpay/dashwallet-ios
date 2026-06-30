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
import Combine

// MARK: - AmountType

enum AmountType {
    case main
    case supplementary
}

// MARK: - AmountInputItem

struct AmountInputItem: Equatable {
    let currencyName: String
    let currencyCode: String

    var isMain: Bool { currencyCode == kDashCurrency }

    static let dash = AmountInputItem(currencyName: kDashCurrency, currencyCode: kDashCurrency)
    static var app: AmountInputItem {
        .init(currencyName: App.fiatCurrency, currencyCode: App.fiatCurrency)
    }

    static func custom(currencyName: String, currencyCode: String) -> AmountInputItem {
        .init(currencyName: currencyName, currencyCode: currencyCode)
    }
}

// MARK: - BaseAmountModel

class BaseAmountModel: ObservableObject {
    var cancellableBag = Set<AnyCancellable>()
    var activeAmountType: AmountType { currentInputItem.isMain ? .main : .supplementary }
    internal let inputLocale: Locale
    var keyboardLocale: Locale { inputLocale }

    var mainAmount: AmountObject!
    var supplementaryAmount: AmountObject!
    @Published var amount: AmountObject!
    @Published var walletBalance: UInt64 = 0
    @Published var error: Error? {
        didSet {
            if let error {
                errorHandler?(error)
            }
        }
    }
    @Published var currentInputItem: AmountInputItem {
        didSet {
            inputsSwappedHandler?(activeAmountType)
        }
    }
    @Published var inputItems: [AmountInputItem] = [] {
        didSet {
            amountInputItemsChangeHandler?()
        }
    }
    @Published private(set) var currentKeyboardInputString: String

    var localCurrency: String {
        let locale = Locale.current as NSLocale
        return locale.displayName(forKey: .currencySymbol, value: localCurrencyCode) ?? localCurrencyCode
    }

    public var errorHandler: ((Error) -> Void)?
    public var presentCurrencyPickerHandler: (() -> Void)?
    public var inputsSwappedHandler: ((AmountType) -> Void)?
    public var amountInputItemsChangeHandler: (() -> Void)?

    public var isAllowedToContinue: Bool {
        isAmountValidForProceeding
    }

    var isAmountValidForProceeding: Bool {
        amount.plainAmount > 0
    }

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

    internal var supplementaryCurrencyCode: String {
        localCurrencyCode
    }

    internal var supplementaryNumberFormatter: NumberFormatter {
        localFormatter
    }

    internal var currencyExchanger: CurrencyExchanger {
        CurrencyExchanger.shared
    }

    init(inputLocale: Locale = .current) {
        self.inputLocale = inputLocale
        localCurrencyCode = App.fiatCurrency
        localFormatter = NumberFormatter.fiatFormatter(currencyCode: localCurrencyCode)
        localFormatter.locale = inputLocale

        currentInputItem = .dash
        currentKeyboardInputString = "0"
        inputItems = [
            .custom(currencyName: localCurrencyCode, currencyCode: localCurrencyCode),
            .dash,
        ]

        mainAmountValidator = DWAmountInputValidator(type: .dash, locale: inputLocale)
        supplementaryAmountValidator = DWAmountInputValidator(type: .localCurrency, locale: inputLocale)

        updateAmountObjects(with: "0")
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.refreshBalance() }
            .store(in: &cancellableBag)
        
        refreshBalance()
    }

    func select(inputItem: AmountInputItem) {
        let currentAmount = amount!

        currentInputItem = inputItem

        if activeAmountType == .supplementary {
            if supplementaryAmount == nil && currentAmount.fiatCurrencyCode == supplementaryCurrencyCode {
                supplementaryAmount = mainAmount.localAmount
            } else if currentAmount.fiatCurrencyCode != supplementaryCurrencyCode {
                let mainAmount = AmountObject(plainAmount: currentAmount.plainAmount,
                                              fiatCurrencyCode: supplementaryCurrencyCode,
                                              localFormatter: supplementaryNumberFormatter,
                                              currencyExchanger: currencyExchanger,
                                              inputLocale: inputLocale)
                supplementaryAmount = mainAmount.localAmount
            }
        } else {
            if mainAmount == nil || mainAmount.fiatCurrencyCode != currentAmount.fiatCurrencyCode {
                mainAmount = supplementaryAmount.dashAmount
            }
        }

        amountDidChange()
    }

    func selectInputItem(at index: Int) {
        select(inputItem: inputItems[index])
    }

    func setupCurrencyCode(_ code: String) {
        guard let price = try? CurrencyExchanger.shared.rate(for: code) else { return }

        localFormatter = NumberFormatter.fiatFormatter(currencyCode: code)
        localFormatter.locale = inputLocale
        localCurrencyCode = code

        let newInputItem = AmountInputItem.custom(currencyName: localCurrencyCode, currencyCode: localCurrencyCode)
        currentInputItem = currentInputItem.isMain ? .dash : newInputItem
        inputItems = [
            newInputItem,
            .dash,
        ]

        let max = NSDecimalNumber(value: MAX_MONEY/DUFFS)
        localFormatter.maximum = NSDecimalNumber(decimal: price).multiplying(by: max)

        rebuildAmounts()
    }

    func updateAmountObjects(with inputString: String, preserveKeyboardInput: Bool = false) {
        if activeAmountType == .main {
            mainAmount = AmountObject(dashAmountString: inputString,
                                      fiatCurrencyCode: supplementaryCurrencyCode,
                                      localFormatter: supplementaryNumberFormatter,
                                      currencyExchanger: currencyExchanger,
                                      inputLocale: inputLocale)
            supplementaryAmount = nil
        } else if let amount = AmountObject(localAmountString: inputString,
                                            fiatCurrencyCode: supplementaryCurrencyCode,
                                            localFormatter: supplementaryNumberFormatter,
                                            currencyExchanger: currencyExchanger,
                                            inputLocale: inputLocale) {
            supplementaryAmount = amount
            mainAmount = nil
        }

        amountDidChange(preserveKeyboardInput: preserveKeyboardInput)
    }

    internal func updateCurrentAmountObject(with amount: UInt64) {
        let amountObject = AmountObject(plainAmount: amount,
                                        fiatCurrencyCode: supplementaryCurrencyCode,
                                        localFormatter: supplementaryNumberFormatter,
                                        currencyExchanger: currencyExchanger,
                                        inputLocale: inputLocale)
        updateCurrentAmountObject(with: amountObject)
    }

    internal func updateCurrentAmountObject(with dashAmount: AmountObject) {
        if activeAmountType == .main {
            mainAmount = dashAmount
            supplementaryAmount = nil
        } else {
            mainAmount = nil
            supplementaryAmount = dashAmount.localAmount
        }

        amountDidChange()
    }

    internal func rebuildAmounts() {
        let amount = amount.amountInternalRepresentation
        updateAmountObjects(with: amount)
    }

    internal final func amountDidChange(preserveKeyboardInput: Bool = false) {
        amount = activeAmountType == .main ? mainAmount : supplementaryAmount
        if !preserveKeyboardInput {
            currentKeyboardInputString = amount.amountInternalRepresentation
        }
        error = nil
        checkAmountForErrors()
    }

    internal func checkAmountForErrors() { }
    internal func selectAllFunds() { }
    
    private func refreshBalance() {
        walletBalance = DWEnvironment.sharedInstance().currentWallet.balance
    }
}

extension BaseAmountModel {
    var isLocalCurrencySelected: Bool {
        activeAmountType == .supplementary
    }

    var isSwapToLocalCurrencyAllowed: Bool {
        CurrencyExchanger.shared.hasRate(for: localCurrencyCode)
    }

    var fiatWalletBalanceFormatted: String {
        guard let fiatAmount = try? Coinbase.shared.currencyExchanger.convertDash(amount: walletBalance.dashAmount, to: App.fiatCurrency) else {
            return "Invalid"
        }

        let nf = supplementaryNumberFormatter
        return nf.string(from: fiatAmount as NSNumber) ?? fiatAmount.string
    }

    var walletBalanceFormatted: String {
        walletBalance.formattedDashAmount
    }
}

// MARK: AmountInputControlDataSource

extension BaseAmountModel: AmountInputControlDataSource {
    var currentInputString: String {
        currentKeyboardInputString
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

    func updateKeyboardInputString(_ value: String) {
        // SwiftUI keyboards send the full intended string, so validate it as a fresh value.
        guard let validatedString = validatedInputString(from: "",
                                                         range: NSRange(location: 0, length: 0),
                                                         replacementText: value) else {
            return
        }

        applyValidatedInputString(validatedString)
    }

    func updateInputField(with replacementText: String, in range: NSRange) {
        guard let validatedString = validatedInputString(from: currentKeyboardInputString,
                                                         range: range,
                                                         replacementText: replacementText) else {
            return
        }

        applyValidatedInputString(validatedString)
    }

    private func validatedInputString(from lastInputString: String, range: NSRange, replacementText: String) -> String? {
        let validator: DWInputValidator
        let numberFormatter: NumberFormatter

        if activeAmountType == .main {
            validator = mainAmountValidator
            numberFormatter = (NumberFormatter.dashFormatter.copy() as? NumberFormatter) ?? NumberFormatter.dashFormatter
            numberFormatter.locale = inputLocale
        } else {
            validator = supplementaryAmountValidator
            numberFormatter = supplementaryNumberFormatter
        }

        return validator.validatedString(fromLastInputString: lastInputString,
                                         range: range,
                                         replacementString: replacementText,
                                         numberFormatter: numberFormatter)
    }

    private func applyValidatedInputString(_ validatedString: String) {
        currentKeyboardInputString = validatedString
        updateAmountObjects(with: validatedString, preserveKeyboardInput: true)
    }

    func amountInputControlDidSwapInputs() {
        assert(inputItems.count == 2, "Swap only if we have two input types")

        let inputItem = inputItems[0] == currentInputItem ? inputItems[1] : inputItems[0]
        select(inputItem: inputItem)
    }

    func pasteFromClipboard() {
        guard let rawString = UIPasteboard.general.string else { return }
        guard let parsedAmount = PastedAmountParser.parse(rawString, locale: inputLocale) else { return }

        // Clamp the pasted value's fraction digits to what the active input type accepts
        // (Dash = 8, local currency per its formatter — usually 2), rounding down. Otherwise a
        // value with too many decimals (e.g. pasting "0.1234" into a 2-dp fiat field) is
        // rejected by the validator and the paste silently does nothing.
        let maxFractionDigits = activeAmountType == .main ? 8 : supplementaryNumberFormatter.maximumFractionDigits
        var value = parsedAmount.decimalValue
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, maxFractionDigits, .down)

        guard let editableValue = PastedAmountParser.editableString(from: rounded, locale: inputLocale) else { return }

        updateKeyboardInputString(editableValue)
    }

    /// Backward-compatible helper used by existing tests. The new paste flow uses
    /// `PastedAmountParser` directly.
    static func normalizedPastedNumberString(from string: String) -> String? {
        PastedAmountParser.parse(string, locale: Locale(identifier: "en_US"))?.normalizedString
    }
}

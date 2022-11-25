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

enum AmountType {
    case main
    case supplementary
}

class BaseAmountModel {
    var showMaxButton: Bool { true }
    var activeAmountType: AmountType = .main
    
    var mainAmount: AmountObject!
    var supplementaryAmount: AmountObject!
    var amount: AmountObject {
        return activeAmountType == .main ? mainAmount : supplementaryAmount
    }
    
    public var amountChangeHandler: ((AmountObject) -> Void)?
    public var presentCurrencyPickerHandler: (() -> Void)?
    public var isEnteredAmountLessThenMinimumOutputAmount: Bool {
        let chain = DWEnvironment.sharedInstance().currentChain
        let amount = amount.plainAmount
        
        return amount < chain.minOutputAmount
    }
    
    public var minimumOutputAmountFormattedString: String {
        let chain = DWEnvironment.sharedInstance().currentChain
        return DSPriceManager.sharedInstance().string(forDashAmount: Int64(chain.minOutputAmount)) ?? "Unknown".localized()
    }


    
    internal var mainAmountValidator: DWAmountInputValidator!
    internal var supplementaryAmountValidator: DWAmountInputValidator!
    
    internal var localFormatter: NumberFormatter
    var localCurrencyCode: String
    
    init() {
        localFormatter = DSPriceManager.sharedInstance().localFormat.copy() as! NumberFormatter
        localCurrencyCode = DSPriceManager.sharedInstance().localCurrencyCode
        
        mainAmountValidator = DWAmountInputValidator(type: .dash)
        supplementaryAmountValidator = DWAmountInputValidator(type: .localCurrency)
        
        updateAmountObjects(with: "0")
    }
    
    func setupCurrencyCode(_ code: String) {
        guard let price = DSPriceManager.sharedInstance().price(forCurrencyCode: code) else { return }
        
        localFormatter.currencyCode = code
        localCurrencyCode = code
        
        let max = NSDecimalNumber(value: MAX_MONEY/DUFFS)
        localFormatter.maximum = NSDecimalNumber(decimal: price.price.decimalValue).multiplying(by: max)
        
        rebuildAmounts()
    }

    func updateAmount(with replacementString: String, range: NSRange) {
    }
    
    internal func rebuildAmounts() {
        if activeAmountType == .main {
            mainAmount = AmountObject(dashAmountString: mainAmount.amountInternalRepresentation, fiatCurrencyCode: localCurrencyCode, localFormatter: localFormatter)
            supplementaryAmount = nil
        } else {
            supplementaryAmount = AmountObject(localAmountString: supplementaryAmount.amountInternalRepresentation, fiatCurrencyCode: localCurrencyCode, localFormatter: localFormatter)
            mainAmount = nil
        }
        
        amountChangeHandler?(mainAmount ?? supplementaryAmount)
    }
}

extension BaseAmountModel {
    var validator: DWInputValidator? {
        return activeAmountType == .supplementary ? supplementaryAmountValidator : mainAmountValidator
    }
    
    var isAmountValidForProceeding: Bool {
        amount.plainAmount > 0
    }
    
    var isLocalCurrencySelected: Bool {
        activeAmountType == .supplementary
    }
    
    var isSwapToLocalCurrencyAllowed: Bool {
        return DSPriceManager.sharedInstance().localCurrencyDashPrice != nil
    }
}

extension BaseAmountModel: AmountViewDataSource {
    var localCurrency: String {
        let locale = Locale.current as NSLocale
        return locale.displayName(forKey: .currencySymbol, value: localCurrencyCode)!
    }
    
    var currentInputString: String {
        return amount.amountInternalRepresentation
    }
    
    var mainAmountString: String {
        return amount.mainFormatted
    }
    
    var supplementaryAmountString: String {
        return amount.supplementaryFormatted
    }
}

extension BaseAmountModel: AmountViewDelegate {
    var amountInputStyle: AmountInputControl.Style {
        .oppositeAmount
    }
    
    func updateInputField(with replacementText: String, in range: NSRange) {
        let lastInputString = amount.amountInternalRepresentation
        
        guard let validatedString = validator?.validatedString(fromLastInputString: lastInputString, range: range, replacementString: replacementText) else {
            return
        }
        
        updateAmountObjects(with: validatedString)
    }
    
    func updateAmountObjects(with inputString: String) {
        if activeAmountType == .main {
            mainAmount = AmountObject(dashAmountString: inputString, fiatCurrencyCode: localCurrencyCode, localFormatter: localFormatter)
            supplementaryAmount = nil
        }else if let amount = AmountObject(localAmountString: inputString, fiatCurrencyCode: localCurrencyCode, localFormatter: localFormatter) {
            supplementaryAmount = amount
            mainAmount = nil
        }
        
        amountChangeHandler?(amount)
    }
    
    func amountInputControlDidSwapInputs() {
        assert(isSwapToLocalCurrencyAllowed, "Switching until price is not fetched is not allowed")
        
        if activeAmountType == .main {
            if supplementaryAmount == nil {
                supplementaryAmount = mainAmount.localAmount(localValidator: supplementaryAmountValidator, localFormatter: localFormatter, currencyCode: localCurrencyCode)
            }
            activeAmountType = .supplementary
        } else {
            if mainAmount == nil {
                mainAmount = supplementaryAmount.dashAmount(dashValidator: mainAmountValidator, localFormatter: localFormatter, currencyCode: localCurrencyCode)
            }
            activeAmountType = .main
        }
        
        amountChangeHandler?(amount)
    }
    
    func amountInputControlChangeCurrencyDidTap() {
        presentCurrencyPickerHandler?()
    }
}

//  
//  Created by Pavel Tikhonenko
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

@objc class TxDetailModel: NSObject {
    var transaction: DSTransaction
    var transactionId: String
    var dataProvider: DWTransactionListDataProviderProtocol //weak
    var dataItem: DWTransactionListDataItem
    var txTaxCategory: TxUserInfoTaxCategory
    
    var direction: DSTransactionDirection {
        return dataItem.direction
    }
    
    var dashAmountString: String {
        return self.dataProvider.dashAmountString(from: dataItem)
    }
    
    var fiatAmountString: String {
        return self.dataItem.fiatAmount;
    }
    
    
    @objc init(transaction: DSTransaction, dataProvider: DWTransactionListDataProviderProtocol) {
        let txHashData = transaction.txHashData
        let txHashDataReversed = Data(txHashData.reversed())
        self.transactionId = txHashDataReversed.hexEncodedString()
        self.transaction = transaction
        self.dataProvider = dataProvider
        self.dataItem = dataProvider.transactionData(for: transaction)
        self.txTaxCategory = Taxes.shared.taxCategory(for: transaction)
    }
    
    func toggleTaxCategoryOnCurrentTransaction() {
        txTaxCategory = txTaxCategory.nextTaxCategory
        let txHash = self.transaction.txHashData
        TxUserInfoDAOImpl.shared.update(dto: TxUserInfo(hash: txHash, taxCategory: txTaxCategory))
    }
    
    func copyTransactionIdToPasteboard() -> Bool {
        UIPasteboard.general.string = self.transactionId
        return true
    }
}

extension TxDetailModel {
    func dashAmountString(with font: UIFont, tintColor: UIColor) -> NSAttributedString {
        let dashFormat = NumberFormatter()
        dashFormat.locale = Locale(identifier: "ru_RU")
        dashFormat.isLenient = true
        dashFormat.numberStyle = .currency
        dashFormat.generatesDecimalNumbers = true
        
        if let positiveFormatRange = dashFormat.positiveFormat.range(of: "#") {
            var positiveFormat: String = dashFormat.positiveFormat
            positiveFormat.replaceSubrange(positiveFormatRange, with: "-#")
            dashFormat.negativeFormat = positiveFormat
        }
    
        dashFormat.currencyCode = "DASH"
        dashFormat.currencySymbol = DASH
        
        dashFormat.maximumFractionDigits = 8;
        dashFormat.minimumFractionDigits = 0; // iOS 8 bug, minimumFractionDigits now has to be set after currencySymbol
        let maxAmount = MAX_MONEY/Int64(NSDecimalNumber(decimal: pow(10.0, dashFormat.maximumFractionDigits)).intValue)
        dashFormat.maximum = NSNumber(value: maxAmount)
        
        let dashAmount = self.dataItem.dashAmount;
        
        let number = NSDecimalNumber(value: dashAmount).multiplying(byPowerOf10: -Int16(dashFormat.maximumFractionDigits))
        let formattedNumber: String = dashFormat.string(from: number)!
        let symbol = self.dataItem.directionSymbol;
        let amount = symbol + formattedNumber
        
        return NSAttributedString.dw_dashAttributedString(forFormattedAmount: amount, tintColor: tintColor, font: font)
    }
 
    func dashAmountString(with font: UIFont) -> NSAttributedString {
        return self.dataProvider.dashAmountString(from: self.dataItem, font: font)
    }
    
    var explorerURL: URL? {
        if DWEnvironment.sharedInstance().currentChain.isTestnet() {
            return URL(string: "https://testnet-insight.dashevo.org/insight/tx/\(self.transactionId)")
        }else if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return URL(string: "https://insight.dashevo.org/insight/tx/\(self.transactionId)")
        }
        
        return nil;
    }
}

extension TxDetailModel {
    var hasSourceUser: Bool {
        return !self.transaction.sourceBlockchainIdentities.isEmpty
    }
    
    var hasDestinationUser: Bool {
        return !self.transaction.destinationBlockchainIdentities.isEmpty
    }
    
    var hasFee: Bool {
        if self.direction == .received {
            return false
        }
        
        let feeValue = self.transaction.feeUsed
        if feeValue == 0 {
            return false
        }
        
        return true
    }
    
    var hasDate: Bool {
        return true
    }
    
    var shouldDisplayInputAddresses: Bool {
        if self.hasSourceUser {
            // Don't show item "Sent from <my username>"
            if (self.dataItem.direction == .sent) {
                return false
            }
            else {
                return true
            }
        }
        return self.dataItem.direction != .received || (self.transaction is DSCoinbaseTransaction)
    }
    
    var shouldDisplayOutputAddresses: Bool {
        if (self.dataItem.direction == .received && self.hasDestinationUser) {
            return false
        }
        return true
    }
    
    private func plainInputAddresses(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        var models: [DWTitleDetailItem] = []

        var addresses = Array(Set(self.dataItem.inputSendAddresses))
        addresses.sort()
        
        let firstAddress = addresses.first
        for address in addresses {
            let detail = NSAttributedString.dw_dashAddressAttributedString(address, with: font, showingLogo: false)
            let hasTitle = address == firstAddress
            
            let model = DWTitleDetailCellModel(style: .truncatedSingleLine, title: hasTitle ? title : "", attributedDetail: detail, copyableData: address)
            models.append(model)
        }
        
        return models
    }
    
    private func plainOutputAddresses(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        var models: [DWTitleDetailItem] = []
        
        var addresses = Array(Set(self.dataItem.outputReceiveAddresses))
        addresses.sort()
        
        let firstAddress = addresses.first
        for address in addresses {
            let detail = NSAttributedString.dw_dashAddressAttributedString(address, with: font, showingLogo: false)
            let hasTitle = address == firstAddress
            
            let model = DWTitleDetailCellModel(style: .truncatedSingleLine, title: hasTitle ? title : "", attributedDetail: detail, copyableData: address)
            models.append(model)
        }
        
        return models
    }
    
    private func sourceUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        guard let blockchainIdentity = self.transaction.sourceBlockchainIdentities.first else {
            return []
        }
        
        let user = DWDPUserObject(blockchainIdentity: blockchainIdentity)
        let model = DWTitleDetailCellModel(title: title, userItem: user, copyableData: nil)
        return [model]
    }
    
    private func destinationUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        guard let blockchainIdentity = self.transaction.destinationBlockchainIdentities.first else {
            return []
        }
        
        let user = DWDPUserObject(blockchainIdentity: blockchainIdentity)
        let model = DWTitleDetailCellModel(title: title, userItem: user, copyableData: nil)
        return [model]
    }
        
    func inputAddresses(with font: UIFont) -> [DWTitleDetailItem] {
        if !self.shouldDisplayInputAddresses {
            return []
        }
        
        let title: String
        switch (self.dataItem.direction) {
        case .sent:
            title = NSLocalizedString("Sent from", comment: "");
        case .received:
            title = NSLocalizedString("Received from", comment: "");
        case .moved:
            title = NSLocalizedString("Moved from", comment: "");
        case .notAccountFunds:
            title = NSLocalizedString("Registered from", comment: "");
        @unknown default:
            title = ""
        }
        
        if self.hasSourceUser {
            return self.sourceUsers(with: title, font: font)
        }
        else {
            return self.plainInputAddresses(with: title, font: font)
        }
    }
    
    func outputAddresses(with font: UIFont) -> [DWTitleDetailItem] {
        if !self.shouldDisplayOutputAddresses {
            return []
        }
        
        let title: String
        switch (self.dataItem.direction) {
        case .sent:
            title = NSLocalizedString("Sent to", comment: "")
        case .received:
            title = NSLocalizedString("Received at", comment: "")
        case .moved:
            title = NSLocalizedString("Internally moved to", comment: "")
        case .notAccountFunds: // this should not be possible
            title = ""
        @unknown default:
            title = ""
        }
        
        if self.hasDestinationUser {
            return self.destinationUsers(with: title, font: font)
        }
        else {
            return self.plainOutputAddresses(with: title, font: font)
        }
        
    }
      
    func specialInfo(with font: UIFont) -> [DWTitleDetailItem] {
        var models: [DWTitleDetailItem] = []
        let addresses = self.dataItem.specialInfoAddresses
        
        for address in addresses.keys {
            let detail = NSAttributedString.dw_dashAddressAttributedString(address, with: font)
            let type = addresses[address]!.intValue
            var title: String;
            switch (type) {
            case 0:
                title = NSLocalizedString("Owner Address", comment: "")
            case 1:
                title = NSLocalizedString("Provider Address", comment: "")
            case 2:
                title = NSLocalizedString("Voting Address", comment: "")
            default:
                title = ""
            }
            let model = DWTitleDetailCellModel(style: .truncatedSingleLine, title: title, attributedDetail: detail, copyableData: address)
            models.append(model)
        }
        
        return models
        
    }
    
    func fee(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem? {
        guard hasFee else { return nil }
        
        let title = NSLocalizedString("Network fee", comment: "")
        let feeValue = self.transaction.feeUsed
        let detail = NSAttributedString.dw_dashAttributedString(forAmount: feeValue, tintColor: tintColor, font: font)
        
        return DWTitleDetailCellModel(style: .default, title: title, attributedDetail: detail)
    }
    
    var date: DWTitleDetailCellModel {
        let title = NSLocalizedString("Date", comment: "")
        let detail = self.dataProvider.longDateString(for: self.transaction)
        let model = DWTitleDetailCellModel(style: .default, title: title, plainDetail: detail)
        return model
    }
    
    var taxCategory: DWTitleDetailCellModel {
        let title = NSLocalizedString("Tax Category", comment: "")
        let detail = txTaxCategory.stringValue
        let model = DWTitleDetailCellModel(style: .default, title: title, plainDetail: detail)
        return model
    }
}

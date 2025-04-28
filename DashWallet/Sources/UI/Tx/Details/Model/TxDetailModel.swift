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
import Combine

// MARK: - TxDetailModel

@objc(DWTxDetailModel)
class TxDetailModel: NSObject {
    private var cancellableBag = Set<AnyCancellable>()
    
    var metadataDao: TransactionMetadataDAOImpl
    var transaction: Transaction
    var transactionId: String
    var txTaxCategory: TxMetadataTaxCategory
    var metadataPrivateNote: String
    var metadataUpdated: (() -> Void)? = nil

    var title: String {
        direction.title
    }

    var direction: DSTransactionDirection {
        transaction.direction
    }

    var dashAmountString: String {
        transaction.formattedDashAmountWithDirectionalSymbol
    }

    var fiatAmountString: String {
        transaction.fiatAmount
    }

    @objc
    convenience init(transaction: DSTransaction) {
        self.init(transaction: Transaction(transaction: transaction))
    }

    init(transaction: Transaction) {
        self.metadataDao = TransactionMetadataDAOImpl.shared
        self.transaction = transaction
        self.transactionId = transaction.txHashHexString
        self.txTaxCategory = Taxes.shared.taxCategory(for: transaction)
        self.metadataPrivateNote = metadataDao.get(by: transaction.txHashData)?.memo ?? ""
        super.init()
        
        self.metadataDao.$lastChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self = self, let change = change else { return }
                
                switch change {
                case .created(let metadata), .updated(let metadata, _), .deleted(let metadata):
                    if metadata.txHash == self.transaction.txHashData {
                        self.metadataPrivateNote = metadata.memo ?? ""
                        self.txTaxCategory = metadata.taxCategory
                    }
                case .deletedAll:
                    self.metadataPrivateNote = ""
                    self.txTaxCategory = .unknown
                }
                
                self.metadataUpdated?()
            }
            .store(in: &cancellableBag)
    }

    func toggleTaxCategoryOnCurrentTransaction() {
        var updatedTaxCategory = txTaxCategory
        
        if updatedTaxCategory == .unknown {
            updatedTaxCategory = transaction.tx.defaultTaxCategory()
        }

        updatedTaxCategory = updatedTaxCategory.nextTaxCategory
        let txHash = transaction.txHashData
        var txUserInfo = TransactionMetadata(txHash: txHash, taxCategory: updatedTaxCategory)
        
        TransactionMetadataDAOImpl.shared.update(dto: txUserInfo)
    }

    func copyTransactionIdToPasteboard() -> Bool {
        UIPasteboard.general.string = transactionId
        return true
    }
}

extension TxDetailModel {
    func dashAmountString(with font: UIFont) -> NSAttributedString {
        NSAttributedString.dashAttributedString(for: transaction.formattedDashAmountWithDirectionalSymbol,
                                                tintColor: transaction.dashAmountTintColor,
                                                font: font)
    }

    func getExplorerURL(explorer: BlockExplorer) -> URL? {
        switch explorer {
        case .insight:
            if DWEnvironment.sharedInstance().currentChain.isTestnet() {
                return URL(string: "https://insight.testnet.networks.dash.org:3002/insight/tx/\(transactionId)")
            } else if DWEnvironment.sharedInstance().currentChain.isMainnet() {
                return URL(string: "https://insight.dash.org/insight/tx/\(transactionId)")
            }
        case .blockchair:
            return URL(string: "https://blockchair.com/dash/transaction/\(transactionId)")
        }
        
        return nil
    }
}

extension TxDetailModel {
    var hasSourceUser: Bool {
        !transaction.tx.sourceIdentities.isEmpty
    }

    var hasDestinationUser: Bool {
        !transaction.tx.destinationIdentities.isEmpty
    }

    var hasFee: Bool {
        if direction == .received {
            return false
        }

        let feeValue = transaction.feeUsed
        if feeValue == 0 {
            return false
        }

        return true
    }

    var hasDate: Bool {
        true
    }

    var shouldDisplayInputAddresses: Bool {
        if hasSourceUser {
            // Don't show item "Sent from <my username>"
            if direction == .sent {
                return false
            }
            else {
                return true
            }
        }
        return direction != .received || transaction.isCoinbaseTransaction
    }

    var shouldDisplayOutputAddresses: Bool {
        if direction == .received && hasDestinationUser {
            return false
        }
        return true
    }

    private func plainInputAddresses(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        var models: [DWTitleDetailItem] = []

        var addresses = transaction.inputSendAddresses
        addresses.sort()

        let firstAddress = addresses.first
        for address in addresses {
            let detail = NSAttributedString.dashAddressAttributedString(address, with: font, showingLogo: false)
            let hasTitle = address == firstAddress

            let model = DWTitleDetailCellModel(style: .truncatedSingleLine, title: hasTitle ? title : "",
                                               attributedDetail: detail, copyableData: address)
            models.append(model)
        }

        return models
    }

    private func plainOutputAddresses(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        var models: [DWTitleDetailItem] = []

        var addresses = Array(Set(transaction.outputReceiveAddresses))
        addresses.sort()

        let firstAddress = addresses.first
        for address in addresses {
            let detail = NSAttributedString.dashAddressAttributedString(address, with: font, showingLogo: false)
            let hasTitle = address == firstAddress

            let model = DWTitleDetailCellModel(style: .truncatedSingleLine, title: hasTitle ? title : "",
                                               attributedDetail: detail, copyableData: address)
            models.append(model)
        }

        return models
    }

    private func sourceUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        guard let identity = transaction.tx.sourceIdentities.first else {
            return []
        }

        #if DASHPAY
        let user = DWDPUserObject(identity: identity)
        let model = DWTitleDetailCellModel(title: title, userItem: user, copyableData: nil)
        return [model]
        #else
        return []
        #endif
    }

    private func destinationUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        guard let identity = transaction.tx.destinationIdentities.first else {
            return []
        }

        #if DASHPAY
        let user = DWDPUserObject(identity: identity)
        let model = DWTitleDetailCellModel(title: title, userItem: user, copyableData: nil)
        return [model]
        #else
        return []
        #endif
    }


    func inputAddresses(with font: UIFont) -> [DWTitleDetailItem] {
        if !shouldDisplayInputAddresses {
            return []
        }

        let title: String
        switch transaction.direction {
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

        if hasSourceUser {
            return sourceUsers(with: title, font: font)
        }
        else {
            return plainInputAddresses(with: title, font: font)
        }
    }

    func outputAddresses(with font: UIFont) -> [DWTitleDetailItem] {
        if !shouldDisplayOutputAddresses {
            return []
        }

        let title: String
        switch transaction.direction {
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

        if hasDestinationUser {
            return destinationUsers(with: title, font: font)
        }
        else {
            return plainOutputAddresses(with: title, font: font)
        }
    }

    func specialInfo(with font: UIFont) -> [DWTitleDetailItem] {
        var models: [DWTitleDetailItem] = []
        guard let addresses = transaction.specialInfoAddresses else { return [] }

        for address in addresses.keys {
            let detail = NSAttributedString.dashAddressAttributedString(address, with: font)
            let type = addresses[address]
            var title: String;
            switch type {
            case 0:
                title = NSLocalizedString("Owner Address", comment: "")
            case 1:
                title = NSLocalizedString("Provider Address", comment: "")
            case 2:
                title = NSLocalizedString("Voting Address", comment: "")
            default:
                title = ""
            }
            let model = DWTitleDetailCellModel(style: .truncatedSingleLine, title: title, attributedDetail: detail,
                                               copyableData: address)
            models.append(model)
        }

        return models
    }

    func fee(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem {
        let title = NSLocalizedString("Network fee", comment: "")
        var feeValue: UInt64 = 0
        
        if hasFee {
            feeValue = transaction.feeUsed
            feeValue = feeValue == UInt64.max ? 0 : feeValue
        }
        
        let detail = NSAttributedString.dashAttributedString(for: feeValue, tintColor: tintColor, font: font)

        return DWTitleDetailCellModel(style: .default, title: title, attributedDetail: detail)
    }

    var date: DWTitleDetailCellModel {
        let title = NSLocalizedString("Date", comment: "")
        let detail = transaction.tx.formattedLongTxDate
        let model = DWTitleDetailCellModel(style: .default, title: title, plainDetail: detail)
        return model
    }

    var taxCategory: DWTitleDetailCellModel {
        let title = NSLocalizedString("Tax Category", comment: "")
        let detail = txTaxCategory.stringValue
        let model = DWTitleDetailCellModel(style: .default, title: title, plainDetail: detail)
        return model
    }
    
    var privateNote: DWTitleDetailCellModel {
        let title = NSLocalizedString("Private Note", comment: "Private Note")
        let detail = metadataPrivateNote
        let model = DWTitleDetailCellModel(style: .default, title: title, plainDetail: detail)
        return model
    }
}

// MARK: TxDetailHeaderCellDataProvider

extension TxDetailModel: TxDetailHeaderCellDataProvider {
    var fiatAmount: String {
        transaction.fiatAmount
    }

    var icon: UIImage {
        transaction.direction.icon
    }

    var tintColor: UIColor {
        transaction.direction.tintColor
    }
}

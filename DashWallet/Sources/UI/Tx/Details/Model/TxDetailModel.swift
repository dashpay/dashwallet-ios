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

// MARK: - TxDetailModel

@objc
class TxDetailModel: NSObject {
    var transaction: Transaction
    var transactionId: String
    var txTaxCategory: TxUserInfoTaxCategory

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
        self.transaction = transaction

        transactionId = transaction.txHashHexString
        txTaxCategory = Taxes.shared.taxCategory(for: transaction)
    }

    func toggleTaxCategoryOnCurrentTransaction() {
        txTaxCategory = txTaxCategory.nextTaxCategory
        let txHash = transaction.txHashData

        // TODO: Move it to Domain layer
        TxUserInfoDAOImpl.shared.update(dto: TxUserInfo(hash: txHash, taxCategory: txTaxCategory))
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

    var explorerURL: URL? {
        if DWEnvironment.sharedInstance().currentChain.isTestnet() {
            return URL(string: "https://insight.testnet.networks.dash.org:3002/insight/tx/\(transactionId)")
        } else if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return URL(string: "https://insight.dash.org/insight/tx/\(transactionId)")
        }

        return nil;
    }
}

extension TxDetailModel {
    var hasSourceUser: Bool {
        !transaction.tx.sourceBlockchainIdentities.isEmpty
    }

    var hasDestinationUser: Bool {
        !transaction.tx.destinationBlockchainIdentities.isEmpty
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
        guard let blockchainIdentity = transaction.tx.sourceBlockchainIdentities.first else {
            return []
        }

        let user = DWDPUserObject(blockchainIdentity: blockchainIdentity)
        let model = DWTitleDetailCellModel(title: title, userItem: user, copyableData: nil)
        return [model]
    }

    private func destinationUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        guard let blockchainIdentity = transaction.tx.destinationBlockchainIdentities.first else {
            return []
        }

        let user = DWDPUserObject(blockchainIdentity: blockchainIdentity)
        let model = DWTitleDetailCellModel(title: title, userItem: user, copyableData: nil)
        return [model]
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

    func fee(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem? {
        guard hasFee else { return nil }

        let title = NSLocalizedString("Network fee", comment: "")

        var feeValue = transaction.feeUsed
        feeValue = feeValue == UInt64.max ? 0 : feeValue

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

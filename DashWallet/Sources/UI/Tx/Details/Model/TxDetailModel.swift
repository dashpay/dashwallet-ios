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

@objc(DWTxDetailModel)
class TxDetailModel: NSObject {
    var transaction: Transaction
    var transactionId: String
    var txTaxCategory: TxMetadataTaxCategory

    /// Memoization for `computedRawFee` (extensions can't store properties).
    /// Two flags so a nil result isn't recomputed on every table reload.
    private var didComputeRawFee = false
    fileprivate var rawFeeCache: UInt64?

    var title: String {
        // Shielded transfers carry their own identity — the generic
        // direction titles ("Moved to Address" / "Amount received") hide
        // what actually happened.
        if transaction.isShieldedTransfer {
            return transaction.isPendingShieldedTransfer
                ? NSLocalizedString("Shielded transfer (pending)",
                                    comment: "A to-Shielded transfer whose asset lock is committed but the shield hasn't completed yet")
                : NSLocalizedString("Shielded transfer",
                                    comment: "Transfer of own funds into the private shielded balance")
        }
        if transaction.isShieldedWithdrawalReceipt {
            return NSLocalizedString("Shielded withdrawal",
                                     comment: "Transfer of own funds from the private shielded balance back to the transparent wallet")
        }
        if transaction.isPlatformFundingTransfer {
            return NSLocalizedString("Platform transfer",
                                     comment: "Transfer of own funds into the Platform balance")
        }
        return direction.title
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

    /// Send-success resolver: the delegate chain hands over the broadcast
    /// transaction's wire-order txid; resolve it to an SDK-backed
    /// `Transaction` — the persisted row when it exists, else the recent-sends
    /// registry (a just-broadcast send the Rust persister hasn't written yet).
    @objc(initWithTxidWire:)
    convenience init(txidWire: Data) {
        self.init(transaction: Self.resolve(txidWire: txidWire))
    }

    private static func resolve(txidWire: Data) -> Transaction {
        if let row = SwiftDashSDKWalletSource.fetch(txid: txidWire) {
            return row
        }
        if let sent = WalletSendService.shared.recentSends.entry(forTxidWire: txidWire) {
            return Transaction(
                syntheticTxid: txidWire,
                directionRaw: 1, // outgoing — the registry records only our own sends
                netAmount: -Int64(sent.amount + sent.fee),
                fee: sent.fee,
                contextRaw: 0, // mempool — just broadcast
                date: sent.date,
                externalSentAddresses: sent.address.map { [$0] } ?? [])
        }
        // Last resort — in practice unreachable: every synced tx has a row and
        // every fresh send has a registry entry. Render the txid honestly; the
        // unknown amount is modeled as 0/mempool rather than fabricated.
        return Transaction(
            syntheticTxid: txidWire,
            directionRaw: 1,
            netAmount: 0,
            fee: nil,
            contextRaw: 0,
            date: Date())
    }

    init(transaction: Transaction) {
        self.transaction = transaction

        transactionId = transaction.txHashHexString
        txTaxCategory = Taxes.shared.taxCategory(for: transaction)
    }

    func toggleTaxCategoryOnCurrentTransaction() {
        if txTaxCategory == .unknown {
            txTaxCategory = transaction.direction.defaultTaxCategory
        }

        txTaxCategory = txTaxCategory.nextTaxCategory
        let txHash = transaction.txHashData

        var txUserInfo = transaction.userInfo ?? TransactionMetadata(txHash: txHash, taxCategory: txTaxCategory)
        txUserInfo.taxCategory = txTaxCategory

        // TODO: Move it to Domain layer
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
            if WalletEnvironment.isTestnet {
                return URL(string: "https://insight.testnet.networks.dash.org:3002/insight/tx/\(transactionId)")
            } else if WalletEnvironment.isMainnet {
                return URL(string: "https://insight.dash.org/insight/tx/\(transactionId)")
            }
        case .blockchair:
            return URL(string: "https://blockchair.com/dash/transaction/\(transactionId)?from=dash")
        }
        
        return nil
    }
}

extension TxDetailModel {
    // TODO(dashpay-e2e): contact attribution for a tx (source/destination
    // identity) returns once the DashPay migration models it on SDK rows.
    // Constant false is today's actual behavior — the legacy reads went
    // through the DSTransaction escape hatch, which was nil for every
    // reachable row.
    var hasSourceUser: Bool {
        false
    }

    var hasDestinationUser: Bool {
        false
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
        // An asset-lock funding's owned outputs are only its change —
        // labeling them "Internally moved to" reads like the transfer's
        // destination. The From/To route rows carry that instead, and the
        // raw transaction inspector shows every output for the curious.
        if transaction.isShieldedTransfer || transaction.isPlatformFundingTransfer {
            return false
        }
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

    // TODO(dashpay-e2e): user rows come back with contact attribution —
    // unreachable today (`hasSourceUser`/`hasDestinationUser` are false).
    private func sourceUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        []
    }

    private func destinationUsers(with title: String, font: UIFont) -> [DWTitleDetailItem] {
        []
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

    /// Extra rows for shielded transfers: the balance-to-balance route and,
    /// for a Core → Shielded funding, the live on-chain asset-lock status.
    /// Empty for every other transaction.
    func shieldedInfo() -> [DWTitleDetailItem] {
        let transparent = NSLocalizedString("Transparent balance", comment: "The transparent (Core) balance of the Dash Wallet")
        let shielded = NSLocalizedString("Shielded balance", comment: "")
        if transaction.isShieldedTransfer {
            var rows: [DWTitleDetailItem] = [
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("From", comment: ""), plainDetail: transparent),
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("To", comment: ""), plainDetail: shielded),
            ]
            if let status = shieldedStatusText {
                rows.append(DWTitleDetailCellModel(
                    style: .default,
                    title: NSLocalizedString("Status", comment: "Transaction details"),
                    plainDetail: status))
            }
            return rows
        }
        if transaction.isShieldedWithdrawalReceipt {
            return [
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("From", comment: ""), plainDetail: shielded),
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("To", comment: ""), plainDetail: transparent),
            ]
        }
        if transaction.isPlatformFundingTransfer {
            var rows: [DWTitleDetailItem] = [
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("From", comment: ""), plainDetail: transparent),
                DWTitleDetailCellModel(
                    style: .default,
                    title: NSLocalizedString("To", comment: ""),
                    plainDetail: NSLocalizedString("Platform balance", comment: "The Dash Platform credits balance")),
            ]
            if let statusRaw = transaction.platformFundingLockInfo?.statusRaw,
               let status = Self.lockStatusText(statusRaw) {
                rows.append(DWTitleDetailCellModel(
                    style: .default,
                    title: NSLocalizedString("Status", comment: "Transaction details"),
                    plainDetail: status))
            }
            return rows
        }
        return []
    }

    /// User-facing name of the funding asset lock's live status
    /// (`PersistentAssetLock.statusRaw` via `ShieldedTxLookup`): 0/1 =
    /// built/broadcast, 2/3 = IS/CL-locked awaiting the shield transition,
    /// 4 = consumed (transfer complete). Nil when the lookup has no entry.
    private var shieldedStatusText: String? {
        guard let statusRaw = ShieldedTxLookup.shared.info(forTxidHex: transactionId)?.statusRaw else {
            return nil
        }
        return Self.lockStatusText(statusRaw)
    }

    /// User-facing name of an asset-lock status (shared by the shielded and
    /// platform funding routes).
    private static func lockStatusText(_ statusRaw: Int) -> String? {
        switch statusRaw {
        case 0, 1:
            return NSLocalizedString("Broadcasting", comment: "")
        case 2, 3:
            return NSLocalizedString("Funds locked — finishing transfer", comment: "Shielded transfer status")
        case 4:
            return NSLocalizedString("Completed", comment: "Shielded transfer status")
        default:
            return nil
        }
    }

    /// Below this (0.0001 DASH) a fee renders as plain duffs — the
    /// DASH-formatted form reads as zero at a glance.
    private static let duffsDisplayThreshold: UInt64 = 10_000

    func fee(with font: UIFont, tintColor: UIColor) -> DWTitleDetailItem {
        let title = NSLocalizedString("Network fee", comment: "")
        var feeValue: UInt64 = 0

        if hasFee {
            feeValue = transaction.feeUsed
            feeValue = feeValue == UInt64.max ? 0 : feeValue
        }
        if feeValue == 0, direction != .received, let computed = computedRawFee {
            // Rows without a persisted fee (asset-lock fundings) still have a
            // real one — recover it from the raw transaction.
            feeValue = computed
        }

        if feeValue > 0, feeValue < Self.duffsDisplayThreshold {
            let detail = String(format: NSLocalizedString("%d duffs", comment: "Network fee in duffs (1 DASH = 100,000,000 duffs)"), feeValue)
            return DWTitleDetailCellModel(style: .default, title: title, plainDetail: detail)
        }

        let detail = NSAttributedString.dashAttributedString(for: feeValue, tintColor: tintColor, font: font)

        return DWTitleDetailCellModel(style: .default, title: title, attributedDetail: detail)
    }

    /// Fee derived from the stored raw transaction as Σ(input values) −
    /// Σ(output values) — the consensus definition, computable exactly when
    /// every input value is known (all inputs are the wallet's own TXOs,
    /// which holds for any tx we authored). Nil when any input value is
    /// unknown, the bytes are unavailable, or the difference is negative
    /// (mis-matched data — never guessed). Memoized: the detail sheet
    /// reloads on tax-category toggles and the parse isn't free.
    private var computedRawFee: UInt64? {
        if !didComputeRawFee {
            didComputeRawFee = true
            rawFeeCache = Self.computeRawFee(txidWire: transaction.txHashData)
        }
        return rawFeeCache
    }

    private static func computeRawFee(txidWire: Data) -> UInt64? {
        let details = MainActor.assumeIsolated {
            RawTransactionInspector.load(txidWire: txidWire)
        }
        guard let details, !details.inputs.isEmpty else { return nil }
        let inputAmounts = details.inputs.compactMap(\.amountDuffs)
        guard inputAmounts.count == details.inputs.count else { return nil }
        let inSum = inputAmounts.reduce(0, +)
        let outSum = details.outputs.reduce(UInt64(0)) { $0 + $1.valueDuffs }
        return inSum >= outSum ? inSum - outSum : nil
    }

    var date: DWTitleDetailCellModel {
        let title = NSLocalizedString("Date", comment: "")
        let detail = DWDateFormatter.sharedInstance.longString(from: transaction.date)
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

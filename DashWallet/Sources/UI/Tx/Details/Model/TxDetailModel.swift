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
        // Identity fundings and balance transfers carry their own identity —
        // the generic direction titles ("Moved to Address") hide what
        // actually happened. Identity fundings name their purpose (matching
        // the home row); other transfer routes read "Internal Transfer" with
        // the From/To/Status rows naming the route.
        if transaction.isIdentityFundingTransfer {
            return transaction.stateTitle
        }
        if let route = transaction.internalTransferRoute, route != .coreToCore {
            return NSLocalizedString("Internal Transfer", comment: "Transaction within the wallet, transfer of own funds")
        }
        return direction.title
    }

    var direction: TransactionDirection {
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
            txTaxCategory = transaction.defaultTaxCategory
        }

        txTaxCategory = nextTaxCategory(after: txTaxCategory)
        let txHash = transaction.txHashData

        var txUserInfo = transaction.userInfo ?? TransactionMetadata(txHash: txHash, taxCategory: txTaxCategory)
        txUserInfo.taxCategory = txTaxCategory

        // TODO: Move it to Domain layer
        TransactionMetadataDAOImpl.shared.update(dto: txUserInfo)
    }

    /// The category a tap on the Tax Category row moves to. Regular
    /// transactions keep the two-state direction pair (Income ↔ Transfer In,
    /// Expense ↔ Transfer Out); an internal transfer cycles through its
    /// direction pair plus the Internal Transfer default, so a reclassified
    /// transfer can be put back.
    private func nextTaxCategory(after category: TxMetadataTaxCategory) -> TxMetadataTaxCategory {
        guard transaction.internalTransferRoute != nil else {
            // A stored Internal Transfer on a transaction no longer detected
            // as one steps back to its direction default.
            return category == .internalTransfer
                ? transaction.direction.defaultTaxCategory
                : category.nextTaxCategory
        }
        // Only the Shielded → Core payout leg is `.received`; every other
        // route is an outgoing/moved leg.
        let cycle: [TxMetadataTaxCategory] = transaction.direction == .received
            ? [.internalTransfer, .transferIn, .income]
            : [.internalTransfer, .transferOut, .expense]
        guard let index = cycle.firstIndex(of: category) else {
            return .internalTransfer
        }
        return cycle[(index + 1) % cycle.count]
    }

    func copyTransactionIdToPasteboard() -> Bool {
        UIPasteboard.general.string = transactionId
        return true
    }

    // MARK: - Dash DEX (swap) explorer

    /// A "View NEAR/Maya Explorer" action for a transaction that belongs to a Dash DEX swap.
    struct SwapExplorerLink {
        let title: String
        let url: URL
    }

    /// Resolved on demand (see `resolveSwapExplorerLink`); nil until resolved or when this
    /// transaction is not part of a swap order.
    private(set) var swapExplorerLink: SwapExplorerLink?

    /// Looks up whether this transaction is the on-chain leg of a stored swap order and, if so,
    /// builds the provider explorer link. Runs off the main actor (DAO reads), then calls
    /// `completion` on the main actor so the caller can rebuild its rows.
    func resolveSwapExplorerLink(completion: @escaping () -> Void) {
        let transaction = self.transaction
        let transactionId = self.transactionId
        Task {
            let link = await Self.swapExplorerLink(transaction: transaction, transactionId: transactionId)
            await MainActor.run {
                self.swapExplorerLink = link
                completion()
            }
        }
    }

    private static func swapExplorerLink(transaction: Transaction, transactionId: String) async -> SwapExplorerLink? {
        let dao = SwapOrdersDAOImpl.shared

        // Sell: the swap order id IS the Dash deposit tx id (display-order hex == transactionId).
        if let order = await dao.get(byId: transactionId), order.direction == "sell" {
            return link(for: order, dashTxId: transactionId)
        }

        // Buy: the incoming Dash tx is matched to a buy order by address + amount + time.
        let orders = await dao.all()
        if let order = orders.first(where: { candidate in
            candidate.direction == "buy"
                && SwapBuyTransactionMatcher.matchedTransaction(for: candidate, in: [transaction]) != nil
        }) {
            return link(for: order, dashTxId: transactionId)
        }

        return nil
    }

    private static func link(for order: SwapOrder, dashTxId: String) -> SwapExplorerLink? {
        let provider = order.provider?.lowercased() ?? ""

        // Maya-routed legacy orders (retired for new swaps) link to the Maya explorer by Dash txid.
        if provider.contains("maya") || order.service == "maya" {
            return SwapExplorerLink(
                title: NSLocalizedString("View Maya Explorer", comment: "Dash DEX / tx details action"),
                url: MayaConstants.mayaScanTransactionURL(txHash: dashTxId.uppercased()))
        }

        // NEAR intents: tracked by the deposit address, not the Dash txid.
        let title = NSLocalizedString("View NEAR Explorer", comment: "Dash DEX / tx details action")
        if let deposit = order.depositAddress?.trimmingCharacters(in: .whitespacesAndNewlines), !deposit.isEmpty {
            return SwapExplorerLink(title: title, url: NearConstants.explorerTransactionURL(depositAddress: deposit))
        }
        return SwapExplorerLink(title: title, url: NearConstants.explorerHomeURL)
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
        if transaction.isShieldedTransfer || transaction.isPlatformFundingTransfer
            || transaction.isIdentityFundingTransfer {
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
            let source = transaction.isCoinJoinFundedTransfer
                ? NSLocalizedString("CoinJoin balance", comment: "The wallet's mixed (CoinJoin) funds as the source of an internal transfer")
                : transparent
            var rows: [DWTitleDetailItem] = [
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("From", comment: ""), plainDetail: source),
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
        if transaction.isIdentityFundingTransfer {
            var rows: [DWTitleDetailItem] = [
                DWTitleDetailCellModel(style: .default, title: NSLocalizedString("From", comment: ""), plainDetail: transparent),
                DWTitleDetailCellModel(
                    style: .default,
                    title: NSLocalizedString("To", comment: ""),
                    plainDetail: NSLocalizedString("Identity credits", comment: "Destination of an identity funding asset lock")),
            ]
            if let statusRaw = transaction.identityFundingLockInfo?.statusRaw,
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
    /// 4 = consumed (transfer complete), 5 = recovered from chain after a
    /// restore. Nil when the lookup has no entry.
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
        case 5:
            // RecoveredFromChain: the lock is final on Core, but whether it
            // completed on Platform is unknown after a restore or an
            // unauthenticated already-consumed report. Claiming neither
            // "Pending" nor "Completed" is deliberate.
            return NSLocalizedString("Completion unknown", comment: "Status of a chain-locked asset lock whose Platform-side consumption cannot be authenticated")
        default:
            return nil
        }
    }

    // MARK: Stuck asset-lock retry

    struct StuckAssetLockRetry {
        let fundingTypeRaw: Int
        let statusRaw: Int
        let vout: UInt32

        /// Button title matching what actually remains: an unlocked
        /// transaction is re-broadcast; a locked one only needs the
        /// Platform side finished.
        var actionTitle: String {
            statusRaw <= 1
                ? NSLocalizedString("Rebroadcast", comment: "Retry a stuck balance transfer whose transaction never confirmed")
                : NSLocalizedString("Complete Transfer", comment: "Retry a stuck balance transfer whose transaction confirmed but whose Platform side never finished")
        }

        /// Local removal is offered only while the network has shown no
        /// acceptance at all (built/broadcast). An IS/CL-locked lock is
        /// proven on-chain — removing it locally could only corrupt state.
        var supportsRemoval: Bool { statusRaw <= 1 }
    }

    /// Non-nil when this transaction is a funding asset lock parked in a
    /// non-terminal state (built/broadcast/IS-locked/CL-locked but never
    /// consumed) on a route `AssetLockRecoveryService` can retry. Status
    /// 4 (consumed) and 5 (restored, completion unknown) never qualify:
    /// 4 is done, and a restored lock has no tracked local state to
    /// resume from.
    var stuckAssetLockRetry: StuckAssetLockRetry? {
        let info = transaction.identityFundingLockInfo
            ?? transaction.platformFundingLockInfo
            ?? ShieldedTxLookup.shared.info(forTxidHex: transactionId)
        guard let info,
              (0...3).contains(info.statusRaw),
              AssetLockRecoveryService.supportsRetry(fundingTypeRaw: info.fundingTypeRaw)
        else { return nil }
        return StuckAssetLockRetry(
            fundingTypeRaw: info.fundingTypeRaw,
            statusRaw: info.statusRaw,
            vout: info.vout)
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

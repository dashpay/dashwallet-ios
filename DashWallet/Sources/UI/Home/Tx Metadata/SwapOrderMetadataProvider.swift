//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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
import DashUIKit

/// Enriches transaction-history rows for DEX swap orders.
///
/// Keying strategy:
/// - **Sell**: `order.id` is `tx.txHashHexString` (reversed-byte Bitcoin display form).
///   `tx.txHashData` (the metadata dict key) equals the byte-reversed form of that hex.
///   Convert: `Data(hex: order.id).map { Data($0.reversed()) }`.
/// - **Buy**: the incoming Dash tx assigned to the order by
///   `SwapBuyTransactionMatcher.payoutResolution` — the tx the order names as its payout
///   (`outboundTxHash`) when that tx fits it, otherwise a match by address + time +
///   approximate amount, one order per transaction; none while it is not settled which of
///   several orders a tx belongs to. Return that tx's `txHashData`.
///   Re-resolves on `SwiftDashSDKWalletState.balanceDidChangeNotification` so a buy that
///   lands after the order is stored still gets labelled.
class SwapOrderMetadataProvider: MetadataProvider, @unchecked Sendable {
    static let shared = SwapOrderMetadataProvider()

    private let dao = SwapOrdersDAOImpl.shared
    private var cancellables = Set<AnyCancellable>()
    private let metadataQueue = DispatchQueue(label: "SwapOrderMetadataProvider.metadata", qos: .utility)
    /// Where the payout assignment is worked out: off the main thread — it reads a range of
    /// the wallet's transactions — and one update at a time.
    private let assignmentQueue = DispatchQueue(label: "SwapOrderMetadataProvider.assignments", qos: .utility)
    /// Updates run one after another, each reading the orders when it starts. One asked
    /// for while another runs is not queued: it makes the running one go round once more
    /// when it is done — during a sync they arrive faster than a wallet read takes, and
    /// only the last result is kept anyway. Both guarded by `metadataQueue`.
    private var isUpdating = false
    private var updateRequested = false

    private var _availableMetadata: [Data: TxRowMetadata] = [:]
    var availableMetadata: [Data: TxRowMetadata] {
        metadataQueue.sync { _availableMetadata }
    }
    let metadataUpdated = PassthroughSubject<Data, Never>()

    /// Wire-order txid → id of the swap order that transaction belongs to. The one
    /// assignment the row label, the details screen and Home all read, so they cannot
    /// disagree about which order a payout is.
    private var _orderIdByTx: [Data: String] = [:]
    /// Ids of the completed orders that share possible payouts with others, one for each
    /// (`PayoutResolution.contestedWithEnough`).
    private var _unsettledOrderIds: Set<String> = []
    /// The wallet and network the assignment was read from; nil while that wallet could
    /// not be read.
    private var _readWallet: (walletId: String?, network: String?)?
    /// Fires after the assignment — or what is known about it — changed.
    let assignmentsChanged = PassthroughSubject<Void, Never>()

    func orderID(forTxHashData txHashData: Data) -> String? {
        metadataQueue.sync { _orderIdByTx[txHashData] }
    }

    /// What the wallet `walletId` on `network` says about the order's Dash payout.
    /// A payout that is assigned is in the wallet whatever else is known; anything short
    /// of that is `.unknown` while the assignment at hand is not a reading of that wallet
    /// that may be relied on for absence.
    func walletPayout(forOrderID orderID: String, walletId: String?, network: String?) -> BuySwapWalletPayout {
        metadataQueue.sync {
            if _orderIdByTx.values.contains(orderID) { return .inWallet }
            guard let read = _readWallet, read.walletId == walletId, read.network == network else {
                return .unknown
            }
            return _unsettledOrderIds.contains(orderID) ? .unsettled : .notFound
        }
    }

    private init() {
        dao.observeAll()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMetadata() }
            .store(in: &cancellables)

        // Re-resolve buy orders when the wallet state changes (the incoming DASH landing is
        // what lets the matcher key a buy order to its tx). Uses the SwiftDashSDK balance
        // notification — the legacy DSWalletBalanceDidChange is frozen post-migration and
        // never fires, so buy metadata never attached.
        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.balanceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMetadata() }
            .store(in: &cancellables)

        // …and when the wallet's transactions are saved: the balance can change before the
        // payout's row is in the store, and an order that has ended is not written again,
        // so nothing else would bring a read that finds it.
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { HomeViewModel.saveTouchesFeedRows($0) }
            .map { _ in () }
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.updateMetadata() }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func updateMetadata() {
        let starts = metadataQueue.sync { () -> Bool in
            if isUpdating {
                updateRequested = true
                return false
            }
            isUpdating = true
            return true
        }
        guard starts else { return }
        Task { [weak self] in
            var again = true
            while again, let self {
                let orders = await self.dao.all()
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    self.assignmentQueue.async {
                        self.computeMetadata(from: orders)
                        done.resume()
                    }
                }
                again = self.metadataQueue.sync {
                    let requested = self.updateRequested
                    self.updateRequested = false
                    self.isUpdating = requested
                    return requested
                }
            }
        }
    }

    private func computeMetadata(from orders: [SwapOrder]) {
        // One payout, one order: decided across all the active wallet's orders, over one
        // shared, `firstSeen`-ranged wallet read, so a transaction is labelled by the order
        // it belongs to and not by another one for the same amount. No label while the
        // wallet cannot be read.
        // The strict read is what "the wallet holds nothing for this order" may be said
        // on. When it fails, the lenient one still serves the labels, and nothing is said
        // about absence.
        let walletId = SwapOrder.currentOwnerWalletId
        let network = SwapOrder.currentOwnerNetwork
        let read = SwapBuyTransactionMatcher.walletAssignments(
            among: orders, walletId: walletId, network: network, strict: true)
        let resolution = read ?? SwapBuyTransactionMatcher.walletAssignments(
            among: orders, walletId: walletId, network: network, strict: false)
        let payouts = resolution?.assigned ?? [:]
        let unsettled = read?.contestedWithEnough ?? []
        let readWallet = read.map { _ in (walletId: walletId, network: network) }
        var current: [Data: TxRowMetadata] = [:]
        var owners: [Data: String] = [:]
        for order in orders {
            if let key = metadataKey(for: order, payouts: payouts) {
                current[key] = makeMetadata(for: order)
                owners[key] = order.id
            }
        }

        metadataQueue.sync {
            let previous = self._availableMetadata
            let staleKeys = Set(previous.keys).subtracting(current.keys)
            let changedKeys = Set(current.filter { previous[$0.key] != $0.value }.keys).union(staleKeys)
            self._availableMetadata = current
            let ownersChanged = self._orderIdByTx != owners
                || self._unsettledOrderIds != unsettled
                || self._readWallet?.walletId != readWallet?.walletId
                || self._readWallet?.network != readWallet?.network
                || (self._readWallet == nil) != (readWallet == nil)
            self._orderIdByTx = owners
            self._unsettledOrderIds = unsettled
            self._readWallet = readWallet
            DispatchQueue.main.async {
                for key in changedKeys {
                    self.metadataUpdated.send(key)
                }
                if ownersChanged { self.assignmentsChanged.send() }
            }
        }
    }

    private func metadataKey(for order: SwapOrder, payouts: [String: Transaction]) -> Data? {
        if order.direction == "sell" {
            return Data(hex: order.id).map { Data($0.reversed()) }
        } else {
            return payouts[order.id]?.txHashData
        }
    }

    private func makeMetadata(for order: SwapOrder) -> TxRowMetadata {
        let title = Self.convertedTitle(for: order)
        return TxRowMetadata(
            title: title,
            details: Self.statusLabel(for: order.status),
            iconName: .custom(DashIcon.Transaction.convert.assetName, bundle: .dashUIKit),
            secondaryIcon: Self.secondaryIcon(for: order.status)
        )
    }

    /// Three visual states drive the row:
    /// - **Processing** (not started / pending / swapping / unknown): text label, no corner badge.
    /// - **Success** (completed): nothing extra — the convert icon alone reads as done.
    /// - **Failed** (refunded / failed / expired): error corner badge, no text label.
    static func secondaryIcon(for status: SwapOrderStatus) -> IconName? {
        switch status {
        case .refunded, .failed, .expired:
            return .custom(DashIcon.AdditionalInfo.error.assetName, bundle: .dashUIKit)
        case .notStarted, .pending, .swapping, .unknown, .completed:
            return nil
        }
    }

    /// "Converted · USDT/DASH" — the row title of a swap whose Dash transaction exists.
    static func convertedTitle(for order: SwapOrder) -> String {
        String(
            format: NSLocalizedString("Converted · %@", comment: "Dash DEX / tx history row title"),
            pairLabel(for: order))
    }

    /// "USDT/DASH" — the order's pair in short tickers.
    static func pairLabel(for order: SwapOrder) -> String {
        "\(shortSymbol(from: order.fromAsset))/\(shortSymbol(from: order.toAsset))"
    }

    /// Extracts the short ticker symbol from a full THORChain asset path.
    /// "ARB.USDC-0X-AF88D065E77C8C-C2239327C5ED-B3A432268E5831" → "USDC"
    /// "DASH" → "DASH"
    /// Internal static: `SwapNotificationProducer` names the pair with it too.
    static func shortSymbol(from asset: String) -> String {
        let afterDot = asset.split(separator: ".").last.map(String.init) ?? asset
        return afterDot.split(separator: "-").first.map(String.init) ?? afterDot
    }

    /// Text badge — shown only for the **Processing** states. Success and Failed carry no label
    /// (Success shows nothing; Failed is conveyed by the error corner badge).
    /// Internal static: the order's own row (`BuySwapOrderItem`) words the same states the
    /// same way.
    static func statusLabel(for status: SwapOrderStatus) -> String? {
        switch status {
        case .notStarted, .pending:
            return NSLocalizedString("Pending", comment: "Dash DEX")
        case .swapping:
            return NSLocalizedString("Swapping", comment: "Dash DEX")
        case .unknown:
            return NSLocalizedString("In progress", comment: "Dash DEX")
        case .completed, .refunded, .failed, .expired:
            return nil
        }
    }
}

// MARK: - BuySwapOrderItem

/// A Buy order as a Home history row, before its Dash transaction exists. It appears once its
/// deposit is on record — seen on the source chain, or reported by the provider.
struct BuySwapOrderItem: Identifiable {
    let order: SwapOrder

    var id: String { "swap-order-\(order.id)" }

    /// When the order entered the history: the moment its deposit was first on record,
    /// otherwise its creation.
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(order.depositSeenAt ?? order.timestamp / 1000))
    }

    var fromSymbol: String { SwapOrderMetadataProvider.shortSymbol(from: order.fromAsset) }
    var pair: String { SwapOrderMetadataProvider.pairLabel(for: order) }

    /// Row title, in the voice of the finished swap's "Converted · USDT/DASH".
    var title: String {
        switch order.status {
        case .completed:
            return SwapOrderMetadataProvider.convertedTitle(for: order)
        case .refunded, .failed, .expired:
            return String(
                format: NSLocalizedString("Not converted · %@", comment: "Dash DEX / tx history row title"), pair)
        case .notStarted, .pending, .swapping, .unknown:
            return String(
                format: NSLocalizedString("Converting · %@", comment: "Dash DEX / tx history row title"), pair)
        }
    }

    /// Whether the row carries the error corner badge: for the statuses the finished-swap
    /// row badges (one rule, `secondaryIcon(for:)`), plus a stuck deposit.
    var showsErrorBadge: Bool {
        order.buyPhase == .stuck || SwapOrderMetadataProvider.secondaryIcon(for: order.status) != nil
    }

    /// "150 USDT" — what the user was asked to send.
    var sendAmountText: String? {
        guard let amount = order.fromAmount?.trimmingCharacters(in: .whitespacesAndNewlines), !amount.isEmpty else {
            return nil
        }
        return "\(amount) \(fromSymbol)"
    }

    /// Expected DASH, in duffs, for the row's amount column. Zero once the order has ended
    /// without a payout — a refunded row must not read as Dash received.
    var expectedDuffs: Int64 {
        switch order.status {
        case .refunded, .failed, .expired: return 0
        case .notStarted, .pending, .swapping, .unknown, .completed: break
        }
        // Bounded by the Dash supply: beyond it the value is not an amount, and the duff
        // conversion below is only defined inside 64 bits.
        guard let dash = SwapBuyTransactionMatcher.expectedDashAmount(for: order),
              dash > 0, dash <= Decimal(21_000_000) else { return 0 }
        return Int64(dash.plainDashAmount)
    }

    var shortTimeString: String {
        DWDateFormatter.sharedInstance.timeOnly(from: date)
    }

    var statusText: String {
        switch order.buyPhase {
        // Never shown: an unpaid order has no row. Present only to keep the switch total.
        case .awaitingPayment: return NSLocalizedString("Pending", comment: "Dash DEX")
        case .waitingForProvider: return NSLocalizedString("Waiting for the provider", comment: "Dash DEX")
        // The provider's own in-progress states, worded as on the finished swap's row.
        case .processing:
            return SwapOrderMetadataProvider.statusLabel(for: order.status)
                ?? NSLocalizedString("In progress", comment: "Dash DEX")
        case .stuck: return NSLocalizedString("Stuck", comment: "Dash DEX")
        case .completed: return NSLocalizedString("Completed", comment: "Dash DEX")
        case .refunded: return NSLocalizedString("Refunded", comment: "Dash DEX")
        case .failed: return NSLocalizedString("Failed", comment: "Dash DEX")
        case .expired: return NSLocalizedString("Not confirmed", comment: "Dash DEX")
        }
    }
}

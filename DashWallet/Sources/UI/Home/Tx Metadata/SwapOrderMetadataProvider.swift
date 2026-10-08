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
/// - **Buy**: prefer `order.outboundTxHash` once tracking has resolved it, but re-validate
///   that hash against the precise buy matcher before trusting it. Otherwise walk
///   `SwiftDashSDKWalletSource.fetchAll()` and match the incoming Dash tx by address + time
///   + approximate amount. Return that tx's `txHashData`. Re-resolves on
///   `SwiftDashSDKWalletState.balanceDidChangeNotification` so a buy that lands after the
///   order is stored still gets labelled.
class SwapOrderMetadataProvider: MetadataProvider, @unchecked Sendable {
    static let shared = SwapOrderMetadataProvider()

    private let dao = SwapOrdersDAOImpl.shared
    private var cancellables = Set<AnyCancellable>()
    private let metadataQueue = DispatchQueue(label: "SwapOrderMetadataProvider.metadata", qos: .utility)

    private var _availableMetadata: [Data: TxRowMetadata] = [:]
    var availableMetadata: [Data: TxRowMetadata] {
        metadataQueue.sync { _availableMetadata }
    }
    let metadataUpdated = PassthroughSubject<Data, Never>()

    /// Wire-order txid → id of the swap order that transaction belongs to. The one
    /// assignment the row label, the details screen and Home all read, so they cannot
    /// disagree about which order a payout is.
    private var _orderIdByTx: [Data: String] = [:]
    /// Fires after the assignment changed.
    let assignmentsChanged = PassthroughSubject<Void, Never>()

    func orderID(forTxHashData txHashData: Data) -> String? {
        metadataQueue.sync { _orderIdByTx[txHashData] }
    }

    /// Whether the order's Dash transaction is in the wallet.
    func hasWalletTransaction(forOrderID orderID: String) -> Bool {
        metadataQueue.sync { _orderIdByTx.values.contains(orderID) }
    }

    private init() {
        dao.observeAll()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orders in
                self?.updateMetadata(from: orders)
            }
            .store(in: &cancellables)

        // Re-resolve buy orders when the wallet state changes (the incoming DASH landing is
        // what lets the matcher key a buy order to its tx). Uses the SwiftDashSDK balance
        // notification — the legacy DSWalletBalanceDidChange is frozen post-migration and
        // never fires, so buy metadata never attached.
        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.balanceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMetadata() }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func updateMetadata(from orders: [SwapOrder]) {
        // One shared, `firstSeen`-ranged fetch feeds every order that needs
        // the address+time buy matcher (the previous shape walked the ENTIRE
        // wallet once per order, on every balance tick).
        let matcherTransactions = buyMatcherTransactions(for: orders)
        // One payout, one order: decided across all orders, so a transaction is labelled by
        // the order it belongs to and not by another one for the same amount.
        let payouts = SwapBuyTransactionMatcher.payoutAssignments(among: orders, in: matcherTransactions)
        var current: [Data: TxRowMetadata] = [:]
        var owners: [Data: String] = [:]
        for order in orders {
            if let key = metadataKey(for: order, payouts: payouts) {
                current[key] = makeMetadata(for: order)
                owners[key] = order.id
            }
        }

        metadataQueue.async { [weak self] in
            guard let self else { return }
            let staleKeys = Set(self._availableMetadata.keys).subtracting(current.keys)
            let changedKeys = Set(current.keys).union(staleKeys)
            self._availableMetadata = current
            let ownersChanged = self._orderIdByTx != owners
            self._orderIdByTx = owners
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
            // `outboundTxHash` is display-order hex; the row lives under its
            // wire-order reversal — a point lookup on the txid index (the
            // previous shape scanned the whole wallet for the hex match).
            if let outboundTxHash = order.outboundTxHash?.trimmingCharacters(in: .whitespacesAndNewlines),
               !outboundTxHash.isEmpty,
               let txHashData = Data(hex: outboundTxHash),
               let matchingTx = SwiftDashSDKWalletSource.fetch(txid: Data(txHashData.reversed())),
               SwapBuyTransactionMatcher.matchedTransaction(for: order, in: [matchingTx]) != nil {
                return Data(txHashData.reversed())
            }

            return payouts[order.id]?.txHashData
        }
    }

    /// Candidate pool for the buy matcher: wallet transactions first seen at/
    /// after the oldest buy order's fetch cutoff. Empty (and fetch-free) when
    /// no order needs matching. SwiftDashSDK tx set; DashSync's
    /// allTransactions is frozen (empty) post-migration.
    private func buyMatcherTransactions(for orders: [SwapOrder]) -> [Transaction] {
        let cutoffs = orders
            .filter { $0.direction != "sell" }
            .map(SwapBuyTransactionMatcher.fetchCutoff(for:))
        guard let oldest = cutoffs.min() else { return [] }
        return SwiftDashSDKWalletSource.fetchRecent(firstSeenSince: oldest)?.transactions ?? []
    }

    private func refreshMetadata() {
        Task {
            let orders = await dao.all()
            updateMetadata(from: orders)
        }
    }

    private func makeMetadata(for order: SwapOrder) -> TxRowMetadata {
        let title = String(
            format: NSLocalizedString("Converted · %@", comment: "Dash DEX / tx history row title"),
            Self.pairLabel(for: order)
        )
        return TxRowMetadata(
            title: title,
            details: Self.statusLabel(for: order.status),
            iconName: .custom(DashIcon.Transaction.convert.assetName, bundle: .dashUIKit),
            secondaryIcon: secondaryIcon(for: order.status)
        )
    }

    /// Three visual states drive the row:
    /// - **Processing** (not started / pending / swapping / unknown): text label, no corner badge.
    /// - **Success** (completed): nothing extra — the convert icon alone reads as done.
    /// - **Failed** (refunded / failed / expired): error corner badge, no text label.
    private func secondaryIcon(for status: SwapOrderStatus) -> IconName? {
        switch status {
        case .refunded, .failed, .expired:
            return .custom(DashIcon.AdditionalInfo.error.assetName, bundle: .dashUIKit)
        case .notStarted, .pending, .swapping, .unknown, .completed:
            return nil
        }
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
        let format: String
        switch order.status {
        case .refunded, .failed, .expired:
            format = NSLocalizedString("Not converted · %@", comment: "Dash DEX / tx history row title")
        case .completed:
            format = NSLocalizedString("Converted · %@", comment: "Dash DEX / tx history row title")
        case .notStarted, .pending, .swapping, .unknown:
            format = NSLocalizedString("Converting · %@", comment: "Dash DEX / tx history row title")
        }
        return String(format: format, pair)
    }

    /// Whether the row carries the error corner badge: the ended-without-payout states the
    /// finished-swap rows already badge, plus a stuck deposit.
    var showsErrorBadge: Bool {
        switch order.buyPhase {
        case .stuck, .refunded, .failed, .expired: return true
        case .awaitingPayment, .waitingForProvider, .processing, .completed: return false
        }
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

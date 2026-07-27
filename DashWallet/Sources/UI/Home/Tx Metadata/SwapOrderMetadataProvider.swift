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
///   `DWEnvironment.sharedInstance().currentWallet.allTransactions` and match the incoming
///   Dash tx by address + time + approximate amount. Return that tx's `txHashData`.
///   Re-resolves on `NSNotification.Name.DSWalletBalanceDidChange` so a buy that lands
///   after the order is stored still gets labelled.
class SwapOrderMetadataProvider: MetadataProvider, @unchecked Sendable {
    static let shared = SwapOrderMetadataProvider()

    private let dao = SwapOrdersDAOImpl.shared
    private var cancellables = Set<AnyCancellable>()
    private let metadataQueue = DispatchQueue(label: "SwapOrderMetadataProvider.metadata", qos: .utility)

    private var _availableMetadata: [Data: TxRowMetadata] = [:]
    var availableMetadata: [Data: TxRowMetadata] {
        metadataQueue.sync { _availableMetadata }
    }

    /// The swap order behind each wallet tx, keyed the same way as `availableMetadata`. Lets the tx
    /// details screen offer a provider block-explorer link without re-running the order matching.
    private var _ordersByTx: [Data: SwapOrder] = [:]
    func order(forTxHashData txHashData: Data) -> SwapOrder? {
        metadataQueue.sync { _ordersByTx[txHashData] }
    }

    let metadataUpdated = PassthroughSubject<Data, Never>()

    private init() {
        dao.observeAll()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] orders in
                self?.updateMetadata(from: orders)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMetadata() }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func updateMetadata(from orders: [SwapOrder]) {
        var current: [Data: TxRowMetadata] = [:]
        var currentOrders: [Data: SwapOrder] = [:]
        for order in orders {
            if let key = metadataKey(for: order) {
                current[key] = makeMetadata(for: order)
                currentOrders[key] = order
            }
        }

        metadataQueue.async { [weak self] in
            guard let self else { return }
            let staleKeys = Set(self._availableMetadata.keys).subtracting(current.keys)
            let changedKeys = Set(current.keys).union(staleKeys)
            self._availableMetadata = current
            self._ordersByTx = currentOrders
            DispatchQueue.main.async {
                for key in changedKeys {
                    self.metadataUpdated.send(key)
                }
            }
        }
    }

    private func metadataKey(for order: SwapOrder) -> Data? {
        if order.direction == "sell" {
            return Data(hex: order.id).map { Data($0.reversed()) }
        } else {
            if let outboundTxHash = order.outboundTxHash?.trimmingCharacters(in: .whitespacesAndNewlines),
               !outboundTxHash.isEmpty,
               let txHashData = Data(hex: outboundTxHash),
               let matchingTx = DWEnvironment.sharedInstance().currentWallet.allTransactions.first(
                    where: { $0.txHashHexString.caseInsensitiveCompare(outboundTxHash) == .orderedSame }
               ),
               SwapBuyTransactionMatcher.matchedTransaction(for: order, in: [matchingTx]) != nil {
                return Data(txHashData.reversed())
            }

            return walletTxHashData(for: order)
        }
    }

    private func walletTxHashData(for order: SwapOrder) -> Data? {
        let transactions = DWEnvironment.sharedInstance().currentWallet.allTransactions
        return SwapBuyTransactionMatcher.walletTxHashData(for: order, in: transactions)
    }

    private func refreshMetadata() {
        Task {
            let orders = await dao.all()
            updateMetadata(from: orders)
        }
    }

    private func makeMetadata(for order: SwapOrder) -> TxRowMetadata {
        let pair = "\(shortSymbol(from: order.fromAsset))/\(shortSymbol(from: order.toAsset))"
        let title = String(
            format: NSLocalizedString("Converted · %@", comment: "Dash DEX / tx history row title"),
            pair
        )
        return TxRowMetadata(
            title: title,
            details: statusLabel(for: order.status),
            iconName: .custom("transaction-convert", bundle: .dashUIKit),
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
            return .custom("additional-info-error", bundle: .dashUIKit)
        case .notStarted, .pending, .swapping, .unknown, .completed:
            return nil
        }
    }

    /// Extracts the short ticker symbol from a full THORChain asset path.
    /// "ARB.USDC-0X-AF88D065E77C8C-C2239327C5ED-B3A432268E5831" → "USDC"
    /// "DASH" → "DASH"
    private func shortSymbol(from asset: String) -> String {
        let afterDot = asset.split(separator: ".").last.map(String.init) ?? asset
        return afterDot.split(separator: "-").first.map(String.init) ?? afterDot
    }

    /// Text badge — shown only for the **Processing** states. Success and Failed carry no label
    /// (Success shows nothing; Failed is conveyed by the error corner badge).
    private func statusLabel(for status: SwapOrderStatus) -> String? {
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

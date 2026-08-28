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
        var current: [Data: TxRowMetadata] = [:]
        for order in orders {
            if let key = metadataKey(for: order, matcherTransactions: matcherTransactions) {
                current[key] = makeMetadata(for: order)
            }
        }

        metadataQueue.async { [weak self] in
            guard let self else { return }
            let staleKeys = Set(self._availableMetadata.keys).subtracting(current.keys)
            let changedKeys = Set(current.keys).union(staleKeys)
            self._availableMetadata = current
            DispatchQueue.main.async {
                for key in changedKeys {
                    self.metadataUpdated.send(key)
                }
            }
        }
    }

    private func metadataKey(for order: SwapOrder, matcherTransactions: [Transaction]) -> Data? {
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

            return SwapBuyTransactionMatcher.walletTxHashData(for: order, in: matcherTransactions)
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
        let pair = "\(Self.shortSymbol(from: order.fromAsset))/\(Self.shortSymbol(from: order.toAsset))"
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
    /// Internal static: `SwapNotificationProducer` names the pair with it too.
    static func shortSymbol(from asset: String) -> String {
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

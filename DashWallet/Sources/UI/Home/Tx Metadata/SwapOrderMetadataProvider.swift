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
/// - **Buy**: walk `DWEnvironment.sharedInstance().currentWallet.allTransactions` and find
///   the tx whose output pays `order.toAddress` (the unique Dash receive address the DEX
///   sends DASH into). Return that tx's `txHashData`. This is immediate and requires no
///   `/track` response — it decorates the row as soon as the funds arrive in the wallet.
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
            .sink { [weak self] _ in self?.refreshBuyMetadata() }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func updateMetadata(from orders: [SwapOrder]) {
        for order in orders {
            guard let txKey = metadataKey(for: order) else { continue }
            let metadata = makeMetadata(for: order)

            metadataQueue.async { [weak self] in
                guard let self else { return }
                self._availableMetadata[txKey] = metadata
                DispatchQueue.main.async {
                    self.metadataUpdated.send(txKey)
                }
            }
        }
    }

    private func metadataKey(for order: SwapOrder) -> Data? {
        if order.direction == "sell" {
            return Data(hex: order.id).map { Data($0.reversed()) }
        } else {
            guard !order.toAddress.isEmpty else { return nil }
            return walletTxHashData(forAddress: order.toAddress)
        }
    }

    private func walletTxHashData(forAddress address: String) -> Data? {
        DWEnvironment.sharedInstance().currentWallet.allTransactions.first { tx in
            tx.outputAddresses.contains { ($0 as? String) == address }
        }?.txHashData
    }

    private func refreshBuyMetadata() {
        Task {
            let buyOrders = await dao.all().filter { $0.direction == "buy" }
            updateMetadata(from: buyOrders)
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

    /// Small status badge shown on the icon's corner. Only a few states carry one for now.
    private func secondaryIcon(for status: SwapOrderStatus) -> IconName? {
        switch status {
        case .refunded, .failed, .expired:
            return .custom("additional-info-error", bundle: .dashUIKit)
        case .notStarted, .pending, .swapping, .unknown:
            // No dedicated pending badge yet — use the native ellipsis ("…") as a placeholder.
            return .system("ellipsis")
        case .completed:
            // Completed needs no badge; the convert icon alone reads as done.
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

    private func statusLabel(for status: SwapOrderStatus) -> String {
        switch status {
        case .notStarted, .pending:
            return NSLocalizedString("Pending", comment: "Dash DEX")
        case .swapping:
            return NSLocalizedString("Swapping", comment: "Dash DEX")
        case .completed:
            return NSLocalizedString("Completed", comment: "Dash DEX")
        case .refunded:
            return NSLocalizedString("Refunded", comment: "Dash DEX")
        case .failed:
            return NSLocalizedString("Failed", comment: "Dash DEX")
        case .unknown:
            return NSLocalizedString("In progress", comment: "Dash DEX")
        case .expired:
            // Neutral: tracking stopped after 24 h without a terminal status; funds may have arrived.
            return NSLocalizedString("Status unavailable", comment: "Dash DEX")
        }
    }
}

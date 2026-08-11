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

import Combine
import CoreData
import DashUIKit
import Foundation
import UIKit

final class CoinbaseMetadataProvider: MetadataProvider, @unchecked Sendable {
    static let shared = CoinbaseMetadataProvider()

    private var cancellableBag = Set<AnyCancellable>()
    private let metadataDao = TransactionMetadataDAOImpl.shared
    private let metadataQueue = DispatchQueue(label: "CoinbaseMetadataProvider.metadata", qos: .utility)

    private var _availableMetadata: [Data: TxRowMetadata] = [:]
    var availableMetadata: [Data: TxRowMetadata] {
        metadataQueue.sync { _availableMetadata }
    }

    let metadataUpdated = PassthroughSubject<Data, Never>()

    /// Single-flight guard for `refreshMetadata()` — both fields guarded by
    /// `metadataQueue`. Every trigger (SwiftData save, wallet switch, DAO
    /// change) funnels through `requestRefresh()`; requests landing while a
    /// refresh runs collapse into one trailing rerun. Without this,
    /// save-storms during initial sync queue unbounded concurrent refreshes
    /// (this pegged 7 cores and 4.6GB after a mainnet recovery back when
    /// each refresh also fetched the full wallet snapshot).
    private var refreshInFlight = false
    private var refreshQueued = false

    private init() {
        requestRefresh()

        metadataDao.$lastChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self, let change = change else { return }

                switch change {
                case .created, .updated:
                    self.requestRefresh()

                case .deleted(let metadata):
                    metadataQueue.sync {
                        self._availableMetadata.removeValue(forKey: metadata.txHash)
                    }
                    metadataUpdated.send(metadata.txHash)

                case .deletedAll:
                    let keys = metadataQueue.sync { () -> [Data] in
                        let existing = Array(self._availableMetadata.keys)
                        self._availableMetadata = [:]
                        return existing
                    }
                    for key in keys {
                        metadataUpdated.send(key)
                    }
                }
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(
            for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellableBag)
    }

    /// Coalescing entry point for all refresh triggers — see the guard
    /// fields' doc for why triggers must not spawn refreshes directly.
    private func requestRefresh() {
        let shouldStart: Bool = metadataQueue.sync {
            if refreshInFlight {
                refreshQueued = true
                return false
            }
            refreshInFlight = true
            return true
        }
        guard shouldStart else { return }
        Task { [weak self] in
            guard let self else { return }
            var runAgain = true
            while runAgain {
                await self.refreshMetadata()
                runAgain = self.metadataQueue.sync {
                    if self.refreshQueued {
                        self.refreshQueued = false
                        return true
                    }
                    self.refreshInFlight = false
                    return false
                }
            }
        }
    }

    private func refreshMetadata() async {
        let coinbaseMetadata = metadataDao.all().filter { $0.service == ServiceName.coinbase.rawValue }
        // Resolve against only the rows the stored metadata points at —
        // point lookups on the txid index. With no stored Coinbase metadata
        // (most wallets, and every save tick during initial sync) the
        // refresh doesn't touch the transaction store at all.
        let current: [Data: TxRowMetadata]
        if coinbaseMetadata.isEmpty {
            current = [:]
        } else {
            current = Self.resolveMetadata(
                storedMetadata: coinbaseMetadata,
                walletSnapshot: CoinbaseWalletTransactionSnapshot.matching(
                    txids: Set(coinbaseMetadata.map(\.txHash))),
                icon: coinbaseIcon())
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

    static func resolveMetadata(
        storedMetadata: [TransactionMetadata],
        walletSnapshot: CoinbaseWalletTransactionSnapshot?,
        icon: UIImage? = nil
    ) -> [Data: TxRowMetadata] {
        guard let walletSnapshot else { return [:] }
        let transactionsByHash = Dictionary(
            uniqueKeysWithValues: walletSnapshot.transactions.map { ($0.txHashData, $0) })

        var resolved: [Data: TxRowMetadata] = [:]
        for metadata in storedMetadata where metadata.service == ServiceName.coinbase.rawValue {
            guard let transaction = transactionsByHash[metadata.txHash] else {
                continue
            }
            resolved[metadata.txHash] = makeMetadata(for: transaction, icon: icon)
        }
        return resolved
    }

    static func makeMetadata(
        for transaction: CoinbaseWalletTransactionRecord,
        icon: UIImage? = nil
    ) -> TxRowMetadata {
        TxRowMetadata(
            icon: icon,
            iconName: .custom("transaction-coinbase.received", bundle: .dashUIKit),
            secondaryIcon: transaction.direction == .sent
                ? .custom("additional-info-sent", bundle: .dashUIKit)
                : .custom("additional-info-received", bundle: .dashUIKit)
        )
    }

    private func coinbaseIcon() -> UIImage? {
        UIImage(named: "transaction-coinbase.received", in: .dashUIKit, compatibleWith: nil)
    }
}

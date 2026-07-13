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

    private init() {
        Task {
            await refreshMetadata()
        }

        metadataDao.$lastChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self, let change = change else { return }

                switch change {
                case .created(let metadata), .updated(let metadata, _):
                    Task {
                        await self.refreshMetadata()
                    }

                case .deleted(let metadata):
                    metadataQueue.async { [weak self] in
                        self?._availableMetadata.removeValue(forKey: metadata.txHash)
                    }
                    metadataUpdated.send(metadata.txHash)

                case .deletedAll:
                    let keys = metadataQueue.sync { self._availableMetadata.keys }
                    for key in keys {
                        metadataUpdated.send(key)
                    }
                    metadataQueue.async { [weak self] in
                        self?._availableMetadata = [:]
                    }
                }
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.refreshMetadata()
                }
            }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.refreshMetadata()
                }
            }
            .store(in: &cancellableBag)
    }

    private func refreshMetadata() async {
        let coinbaseMetadata = metadataDao.all().filter { $0.service == ServiceName.coinbase.rawValue }
        let walletTransactions = DWEnvironment.sharedInstance().currentWallet.allTransactions

        var current: [Data: TxRowMetadata] = [:]
        for metadata in coinbaseMetadata {
            guard let transaction = walletTransactions.first(where: { $0.txHashData == metadata.txHash }) else {
                continue
            }

            current[metadata.txHash] = makeMetadata(for: transaction)
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

    private func makeMetadata(for transaction: DSTransaction) -> TxRowMetadata {
        TxRowMetadata(
            icon: coinbaseIcon(),
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

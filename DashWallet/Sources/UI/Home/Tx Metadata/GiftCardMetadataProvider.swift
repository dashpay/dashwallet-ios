//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import UIKit
import CryptoKit

class GiftCardMetadataProvider: MetadataProvider, @unchecked Sendable {
    static let shared = GiftCardMetadataProvider()
    
    private var cancellableBag = Set<AnyCancellable>()
    private let iconBitmapDao = IconBitmapDAOImpl.shared
    private let giftCardDao = GiftCardsDAOImpl.shared
    private let metadataDao = TransactionMetadataDAOImpl.shared
    private let metadataQueue = DispatchQueue(label: "GiftCardMetadataProvider.metadata", qos: .utility)
    
    private var _availableMetadata: [Data: TxRowMetadata] = [:]
    var availableMetadata: [Data: TxRowMetadata] {
        return metadataQueue.sync { _availableMetadata }
    }
    let metadataUpdated = PassthroughSubject<Data, Never>()
    
    init() {
        Task {
            await loadMetadata()
        }

        // Observe gift card changes
        giftCardDao.observeAll()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] giftCards in
                guard let self = self else { return }
                Task {
                    await self.updateMetadataForGiftCards(giftCards)
                }
            }
            .store(in: &cancellableBag)

        self.metadataDao.$lastChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self = self, let change = change else { return }

                switch change {
                case .created(let metadata), .updated(let metadata, _):
                    Task {
                        await self.onMetadataUpdated(metadata: metadata)
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
    }
    
    private func loadMetadata() async {
        let giftCards = await giftCardDao.all()
        await updateMetadataForGiftCards(giftCards)
    }

    private func updateMetadataForGiftCards(_ giftCards: [GiftCard]) async {
        for giftCard in giftCards {
            let title = String.localizedStringWithFormat(NSLocalizedString("Gift card · %@", comment: "DashSpend"), giftCard.merchantName)

            metadataQueue.async { [weak self] in
                guard let self = self else { return }
                var txRowMetadata = self._availableMetadata[giftCard.txId]

                if txRowMetadata != nil {
                    txRowMetadata!.title = title
                    txRowMetadata!.secondaryIcon = .custom("image.explore.dash.wts.payment.gift-card")
                } else {
                    txRowMetadata = TxRowMetadata(
                        title: title,
                        secondaryIcon: .custom("image.explore.dash.wts.payment.gift-card")
                    )
                }

                self._availableMetadata[giftCard.txId] = txRowMetadata

                // Send update notification for this tx
                DispatchQueue.main.async {
                    self.metadataUpdated.send(giftCard.txId)
                }
            }
        }
    }
    
    private func onMetadataUpdated(metadata: TransactionMetadata) async {
        guard let service = metadata.service, service == ServiceName.ctxSpend.rawValue else { return }
        guard let giftCard = await giftCardDao.get(byTxId: metadata.txHash) else { return }
        let title = String.localizedStringWithFormat(NSLocalizedString("Gift card · %@", comment: "DashSpend"), giftCard.merchantName)
        
        metadataQueue.async { [weak self] in
            guard let self = self else { return }
            var txRowMetadata = self._availableMetadata[metadata.txHash]
            
            if txRowMetadata != nil {
                txRowMetadata!.title = title
                txRowMetadata!.secondaryIcon = .custom("image.explore.dash.wts.payment.gift-card")
            } else {
                txRowMetadata = TxRowMetadata(
                    title: title,
                    secondaryIcon: .custom("image.explore.dash.wts.payment.gift-card")
                )
            }
            
            self._availableMetadata[metadata.txHash] = txRowMetadata
            
            DispatchQueue.main.async {
                self.metadataUpdated.send(metadata.txHash)
            }
        }
    }
}

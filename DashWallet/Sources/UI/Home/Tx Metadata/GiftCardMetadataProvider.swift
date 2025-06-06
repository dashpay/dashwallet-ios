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

class GiftCardMetadataProvider: MetadataProvider {
    static let shared = GiftCardMetadataProvider()
    
    private var cancellableBag = Set<AnyCancellable>()
    private let iconBitmapDao = IconBitmapDAOImpl.shared
    private let giftCardDao = GiftCardsDAOImpl.shared
    private let metadataDao = TransactionMetadataDAOImpl.shared
    
    var availableMetadata: [Data: TxRowMetadata] = [:]
    let metadataUpdated = PassthroughSubject<Data, Never>()
    
    init() {
        Task {
            await loadMetadata()
        }
        
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
                    availableMetadata.removeValue(forKey: metadata.txHash)
                    metadataUpdated.send(metadata.txHash)

                case .deletedAll:
                    for metadata in availableMetadata {
                        metadataUpdated.send(metadata.key)
                    }
                    availableMetadata = [:]
                }
            }
            .store(in: &cancellableBag)
    }
    
    private func loadMetadata() async {
        let giftCards = await giftCardDao.all()
        
        for giftCard in giftCards {
            var txRowMetadata = availableMetadata[giftCard.txId]
            let title = String.localizedStringWithFormat(NSLocalizedString("Gift card · %@", comment: "DashSpend"), giftCard.merchantName)

            if txRowMetadata != nil {
                txRowMetadata!.title = title
                txRowMetadata!.secondaryIcon = .custom("image.explore.dash.wts.payment.gift-card")
            } else {
                txRowMetadata = TxRowMetadata(
                    title: title,
                    secondaryIcon: .custom("image.explore.dash.wts.payment.gift-card")
                )
            }

            availableMetadata[giftCard.txId] = txRowMetadata
        }
    }
    
    private func onMetadataUpdated(metadata: TransactionMetadata) async {
        guard let service = metadata.service, service == ServiceName.ctxSpend.rawValue else { return }
        guard let giftCard = await giftCardDao.get(byTxId: metadata.txHash) else { return }
        let title = String.localizedStringWithFormat(NSLocalizedString("Gift card · %@", comment: "DashSpend"), giftCard.merchantName)
        var txRowMetadata = availableMetadata[metadata.txHash]
        
        if txRowMetadata != nil {
            txRowMetadata!.title = title
        } else {
            txRowMetadata = TxRowMetadata(title: title)
        }
        
        availableMetadata[metadata.txHash] = txRowMetadata
        metadataUpdated.send(metadata.txHash)
    }
}

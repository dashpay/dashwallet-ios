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

class CustomIconMetadataProvider: MetadataProvider {
    private var cancellableBag = Set<AnyCancellable>()
    private let iconBitmapDao = iconBitmapDAOImpl.shared
    var availableMetadata: [Data : TxRowMetadata] = [:]
    
    let metadataUpdated = PassthroughSubject<Data, Never>()
    
    init() {
        loadMetadata()
//        self.metadataDao.$lastChange
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] change in
//                guard let self = self, let change = change else { return }
//                
//                switch change {
//                case .created(let metadata), .updated(let metadata, _):
//                    onMemoUpdated(metadata: metadata)
//                    
//                case .deleted(let metadata):
//                    availableMetadata.removeValue(forKey: metadata.txHash)
//                    metadataUpdated.send(metadata.txHash)
//                    
//                case .deletedAll:
//                    for metadata in availableMetadata {
//                        metadataUpdated.send(metadata.key)
//                    }
//                    availableMetadata = [:]
//                }
//            }
//            .store(in: &cancellableBag)
    }
    
    private func loadMetadata() {
//        let txMetadata = metadataDao.getPrivateMemos()
//        
//        for metadata in txMetadata {
//            var txRowMetadata = availableMetadata[metadata.txHash]
//            
//            if txRowMetadata != nil {
//                txRowMetadata!.details = metadata.memo
//            } else {
//                txRowMetadata = TxRowMetadata(
//                    title: nil,
//                    details: metadata.memo
//                )
//            }
//            
//            availableMetadata[metadata.txHash] = txRowMetadata
//        }
    }
    
//    private func onMemoUpdated(metadata: TransactionMetadata) {
//        var txRowMetadata = availableMetadata[metadata.txHash]
//        
//        if txRowMetadata != nil {
//            txRowMetadata!.details = metadata.memo
//        } else {
//            txRowMetadata = TxRowMetadata(
//                title: nil,
//                details: metadata.memo
//            )
//        }
//        
//        availableMetadata[metadata.txHash] = txRowMetadata
//        metadataUpdated.send(metadata.txHash)
//    }
}

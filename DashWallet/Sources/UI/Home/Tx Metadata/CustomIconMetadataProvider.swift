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

class CustomIconMetadataProvider: MetadataProvider {
    static let shared = CustomIconMetadataProvider()
    
    private var cancellableBag = Set<AnyCancellable>()
    private let iconBitmapDao = IconBitmapDAOImpl.shared
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
        let customIcons = metadataDao.getCustomIcons()

        for iconMetadata in customIcons {
            guard let iconId = iconMetadata.customIconId else { continue }
            let bitmap = await iconBitmapDao.getBitmap(id: iconId)
            guard let data = bitmap?.imageData, let icon = UIImage(data: data) else { continue }
            var txRowMetadata = availableMetadata[iconMetadata.txHash]

            if txRowMetadata != nil {
                txRowMetadata!.iconId = iconMetadata.customIconId
                txRowMetadata!.icon = icon
            } else {
                txRowMetadata = TxRowMetadata(
                    iconId: iconMetadata.customIconId,
                    icon: icon
                )
            }

            availableMetadata[iconMetadata.txHash] = txRowMetadata
        }
    }
    
    private func onMetadataUpdated(metadata: TransactionMetadata) async {
        guard let iconId = metadata.customIconId else { return }
        let bitmap = await iconBitmapDao.getBitmap(id: iconId)
        guard let data = bitmap?.imageData, let icon = UIImage(data: data) else { return }
        var txRowMetadata = availableMetadata[metadata.txHash]

        if txRowMetadata != nil {
            txRowMetadata!.details = metadata.memo
        } else {
            txRowMetadata = TxRowMetadata(
                title: nil,
                details: metadata.memo
            )
        }

        availableMetadata[metadata.txHash] = txRowMetadata  
        metadataUpdated.send(metadata.txHash)
    }
    
    func updateIcon(txId: Data, iconUrl: String) {
        Task {
            do {
                guard let url = URL(string: iconUrl) else {
                    print("Invalid icon URL: \(iconUrl)")
                    return
                }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                
                guard let image = UIImage(data: data) else {
                    print("Failed to create image from data for URL: \(iconUrl)")
                    return
                }
                
                // Calculate hash from original image data
                let imageHash = SHA256.hash(data: data)
                let hashData = Data(imageHash)
                
                let resizedImage = resizeIcon(image: image)
                guard let resizedImageData = resizedImage.pngData() else {
                    return
                }
                
                let iconBitmap = IconBitmap(
                    id: hashData,
                    imageData: resizedImageData,
                    originalUrl: iconUrl,
                    height: Int(resizedImage.size.height),
                    width: Int(resizedImage.size.width)
                )
                
                await iconBitmapDao.addBitmap(bitmap: iconBitmap)
                
                var metadata = TransactionMetadata(txHash: txId)
                metadata.customIconId = hashData
                metadataDao.update(dto: metadata)
                
                var txRowMetadata = availableMetadata[txId] ?? TxRowMetadata(title: nil, details: nil)
                txRowMetadata.iconId = hashData
                txRowMetadata.icon = resizedImage
                availableMetadata[txId] = txRowMetadata
                
                Task { @MainActor in
                    self.metadataUpdated.send(txId)
                }
            } catch {
                print("Failed to fetch icon from URL \(iconUrl): \(error)")
            }
        }
    }
    
    private func resizeIcon(image: UIImage) -> UIImage {
        let destSize: CGFloat = 150.0
        var width = image.size.width
        var height = image.size.height
        
        if width > destSize || height > destSize {
            if width < height {
                let scale = destSize / height
                height = destSize
                width = width * scale
            } else if width > height {
                let scale = destSize / width
                width = destSize
                height = height * scale
            } else {
                width = destSize
                height = destSize
            }
        }
        
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
}

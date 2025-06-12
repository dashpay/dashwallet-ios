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
    var availableMetadata: [Data : TxRowMetadata] = [:]
    
    let metadataUpdated = PassthroughSubject<Data, Never>()
    
    init() {
        loadMetadata()
        
        iconBitmapDao.observeBitmaps()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bitmaps in
                guard let self = self else { return }
                
                // Update metadata with new icons
                for (iconId, iconBitmap) in bitmaps {
                    if let image = UIImage(data: iconBitmap.imageData) {
                        // Find transactions that use this icon
                        for (txHash, metadata) in availableMetadata { // TODO: create new metatada if needed
                            if let customIconId = metadata.customIconId, customIconId == iconId {
                                var updatedMetadata = metadata
                                updatedMetadata.icon = image
                                availableMetadata[txHash] = updatedMetadata
                                metadataUpdated.send(txHash)
                            }
                        }
                    }
                }
            }
            .store(in: &cancellableBag)
    }
    
    private func loadMetadata() {
        // TODO: Load existing metadata if needed
        // This would typically load from transaction metadata that references icon IDs
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
                txRowMetadata.customIconId = hashData
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

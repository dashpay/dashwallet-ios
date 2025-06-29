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

struct GiftCardDetailsUIState {
    var merchantName: String = ""
    var merchantUrl: String? = nil
    var formattedPrice: String = "$0.00"
    var cardNumber: String? = nil
    var cardPin: String? = nil
    var barcodeImage: UIImage? = nil
    var merchantIcon: UIImage? = nil
    var purchaseDate: Date? = nil
    var isLoadingCardDetails: Bool = false
    var loadingError: Error? = nil
    var transaction: DSTransaction? = nil
}

@MainActor
class GiftCardDetailsViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let ctxSpendRepository = CTXSpendRepository.shared
    private let giftCardsDAO = GiftCardsDAOImpl.shared
    private let customIconDAO = IconBitmapDAOImpl.shared
    private let txMetadataDAO = TransactionMetadataDAOImpl.shared
    private var tickerTimer: Timer?
    private var retryCount = 0
    private let maxRetries = 3
    
    let txId: Data
    @Published private(set) var uiState = GiftCardDetailsUIState()
    
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()
    
    init(txId: Data) {
        self.txId = txId
        loadTransaction()
    }
    
    func startObserving() {
        loadExistingMetadata()
        
        // Load the initial gift card data
        Task {
            await loadGiftCard()
        }
        
        // Observe changes to gift card txId
        giftCardsDAO.giftCardTxIdPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] publishedTxId in
                guard let self = self,
                      let publishedTxId = publishedTxId,
                      publishedTxId == self.txId else { return }
                
                // The gift card for our txId has changed, fetch it
                Task {
                    await self.loadGiftCard()
                }
            }
            .store(in: &cancellableBag)
        
        self.txMetadataDAO.$lastChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self = self, let change = change else { return }

                Task {
                    switch change {
                    case .created(let metadata), .updated(let metadata, _):
                        await self.loadIcon(metadata: metadata)
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellableBag)
    }
    
    func stopObserving() {
        cancellableBag.removeAll()
        stopTicker()
    }
    
    private func loadTransaction() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            let transaction = DWEnvironment.sharedInstance().currentWallet.allTransactions.first { transaction in
                return transaction.txHashData == self.txId
            }
            
            await MainActor.run {
                if let tx = transaction {
                    self.uiState.purchaseDate = Date(timeIntervalSince1970: TimeInterval(tx.timestamp))
                    self.uiState.transaction = tx
                }
            }
        }
    }
    
    private func loadGiftCard() async {
        guard let card = await giftCardsDAO.get(byTxId: txId) else { return }
        
        await MainActor.run {
            self.uiState.merchantName = card.merchantName
            self.uiState.merchantUrl = card.merchantUrl
            self.uiState.formattedPrice = self.currencyFormatter.string(from: card.price as NSDecimalNumber) ?? "$0.00"
            self.uiState.cardNumber = card.number
            self.uiState.cardPin = card.pin
            
            // Generate barcode if we have the value
            if let barcodeValue = card.barcodeValue {
                self.generateBarcode(from: barcodeValue, format: card.barcodeFormat ?? "CODE128")
            }
            
            // If we don't have card details yet but have a note (payment ID), start ticker
            if card.number == nil && card.note != nil {
                self.startTicker()
            } else {
                self.stopTicker()
            }
        }
    }
    
    private func startTicker() {
        guard tickerTimer == nil else { return }
        
        uiState.isLoadingCardDetails = true
        uiState.loadingError = nil
        
        Task {
            await fetchGiftCardInfo()
        }
        
        // Set up timer for periodic fetches
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.fetchGiftCardInfo()
            }
        }
    }
    
    private func stopTicker() {
        tickerTimer?.invalidate()
        tickerTimer = nil
        uiState.isLoadingCardDetails = false
        retryCount = 0
    }
    
    private func fetchGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              let _ = giftCard.note,
              ctxSpendRepository.isUserSignedIn else {
            stopTicker()
            return
        }
        
        do {
            let base58TxId = ((txId as NSData).reverse() as NSData).base58String()
            let response = try await ctxSpendRepository.getGiftCardByTxid(txid: base58TxId)
            
            switch response.status {
            case "fulfilled":
                if let cardNumber = response.cardNumber, !cardNumber.isEmpty {
                    // Update gift card with received details
                    await giftCardsDAO.updateCardDetails(
                        txId: txId,
                        number: cardNumber,
                        pin: response.cardPin
                    )
                    
                    // Save barcode
                    if !cardNumber.isEmpty {
                        let cleanNumber = cardNumber.replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: "-", with: "")
                        await giftCardsDAO.updateBarcode(
                            txId: txId,
                            value: cleanNumber,
                            format: "CODE128"
                        )
                    }
                    stopTicker()
                    DSLogger.log("DashSpend: Gift card details fetched successfully")
                }
                
            case "rejected":
                await MainActor.run {
                    self.uiState.loadingError = CTXSpendError.customError(
                        NSLocalizedString("Gift card purchase was rejected", comment: "")
                    )
                }
                stopTicker()
                
            default:
                // Keep polling for other statuses
                break
            }
        } catch {
            retryCount += 1
            if retryCount >= maxRetries {
                await MainActor.run {
                    self.uiState.loadingError = error
                }
                stopTicker()
            }
            DSLogger.log("DashSpend: Failed to fetch gift card info: \(error)")
        }
    }
    
    private func loadExistingMetadata() {
        Task {
            if let metadata = txMetadataDAO.get(by: txId) {
                await self.loadIcon(metadata: metadata)
            }
        }
    }
    
    private func loadIcon(metadata: TransactionMetadata) async {
        if let customIconId = metadata.customIconId,
            let iconBitmap = await self.customIconDAO.getBitmap(id: customIconId) {
            guard let image = UIImage(data: iconBitmap.imageData) else {
                DSLogger.log("Failed to create image from data for tx icon: \(metadata.txHash.hexEncodedString())")
                return
            }
            
            self.uiState.merchantIcon = image
        }
    }
    
    private func generateBarcode(from string: String, format: String) {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return }
        
        let data = string.data(using: .ascii)
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage else { return }
        
        let scaleX = 3.0
        let scaleY = 5.0
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let context = CIContext()
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            uiState.barcodeImage = UIImage(cgImage: cgImage)
        }
    }
} 

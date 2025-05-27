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
import CoreImage.CIFilterBuiltins

@MainActor
class GiftCardDetailsViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let ctxSpendService = CTXSpendService.shared
    private let giftCardsDAO = GiftCardsDAOImpl.shared
    private var tickerTimer: Timer?
    private var retryCount = 0
    private let maxRetries = 3
    
    let txId: Data
    @Published private(set) var merchantName: String = ""
    @Published private(set) var merchantIconUrl: String? = nil
    @Published private(set) var merchantUrl: String? = nil
    @Published private(set) var formattedPrice: String = "$0.00"
    @Published private(set) var cardNumber: String? = nil
    @Published private(set) var cardPin: String? = nil
    @Published private(set) var barcodeImage: UIImage? = nil
    @Published private(set) var purchaseDate: Date? = nil
    @Published private(set) var isLoadingCardDetails: Bool = false
    @Published private(set) var loadingError: Error? = nil
    
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()
    
    init(txId: Data) {
        self.txId = txId
        loadTransactionDate()
    }
    
    func startObserving() {
        // Observe gift card changes
        giftCardsDAO.observeCard(byTxId: txId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] giftCard in
                guard let self = self, let card = giftCard else { return }
                
                self.merchantName = card.merchantName
                self.merchantUrl = card.merchantUrl
                self.formattedPrice = self.currencyFormatter.string(from: card.price as NSDecimalNumber) ?? "$0.00"
                self.cardNumber = card.number
                self.cardPin = card.pin
                
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
            .store(in: &cancellableBag)
        
        // TODO: Observe merchant icon from transaction metadata if available
    }
    
    func stopObserving() {
        cancellableBag.removeAll()
        stopTicker()
    }
    
    func logHowToUse() {
        // TODO: Log analytics event
        DSLogger.log("DashSpend: User tapped 'How to use' for gift card")
    }
    
    private func loadTransactionDate() {
        // Get transaction date
        if let tx = DWEnvironment.sharedInstance().currentWallet.allTransactions.first(where: { transaction in
            return transaction.txHashData == txId
        }) {
            purchaseDate = Date(timeIntervalSince1970: TimeInterval(tx.timestamp))
        }
    }
    
    private func startTicker() {
        guard tickerTimer == nil else { return }
        
        isLoadingCardDetails = true
        loadingError = nil
        
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
        isLoadingCardDetails = false
        retryCount = 0
    }
    
    private func fetchGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              let paymentId = giftCard.note,
              ctxSpendService.isUserSignedIn else {
            stopTicker()
            return
        }
        
        do {
            let response = try await ctxSpendService.getGiftCardByTxid(txid: txId.hexEncodedString())
            
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
                loadingError = CTXSpendError.customError(
                    NSLocalizedString("Gift card purchase was rejected", comment: "")
                )
                stopTicker()
                
            default:
                // Keep polling for other statuses
                break
            }
        } catch {
            retryCount += 1
            if retryCount >= maxRetries {
                loadingError = error
                stopTicker()
            }
            DSLogger.log("DashSpend: Failed to fetch gift card info: \(error)")
        }
    }
    
    private func generateBarcode(from string: String, format: String) {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return }
        
        let data = string.data(using: .ascii)
        filter.setValue(data, forKey: "inputMessage")
        
        guard let outputImage = filter.outputImage else { return }
        
        let scaleX = 3.0
        let scaleY = 3.0
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let context = CIContext()
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            barcodeImage = UIImage(cgImage: cgImage)
        }
    }
} 

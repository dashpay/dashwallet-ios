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

struct GiftCardDetailsCardItem: Identifiable {
    let id: String
    let formattedPrice: String
    let cardNumber: String?
    let cardPin: String?
    let barcodeImage: UIImage?
    let isClaimLink: Bool
}

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
    var isClaimLink: Bool = false
    var hasBeenPollingForLongTime: Bool = false
    var provider: String? = nil
    var cards: [GiftCardDetailsCardItem] = []
}

private struct GiftCardOrderMetadata: Codable {
    let orderId: String
    let cardAmounts: [String]?
    let cards: [GiftCardPayloadEntry]?
}

private struct GiftCardPayloadEntry: Codable {
    let formattedPrice: String
    let cardNumber: String?
    let cardPin: String?
    let barcodeValue: String?
    let barcodeFormat: String?
    let isClaimLink: Bool
}

@MainActor
class GiftCardDetailsViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private lazy var ctxSpendRepository = CTXSpendRepository.shared
    private lazy var piggyCardsRepository = PiggyCardsRepository.shared
    private lazy var giftCardsDAO = GiftCardsDAOImpl.shared
    private lazy var customIconDAO = IconBitmapDAOImpl.shared
    private lazy var txMetadataDAO = TransactionMetadataDAOImpl.shared
    private var tickerTimer: Timer?
    private var retryCount = 0
    private let maxRetries = 40
    private let longPollingThreshold = 27

    let txId: Data
    @Published private(set) var uiState = GiftCardDetailsUIState()

    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    init(txId: Data, shouldLoadTransaction: Bool = true) {
        self.txId = txId
        if shouldLoadTransaction {
            loadTransaction()
        }
    }

    func startObserving() {
        loadExistingMetadata()

        Task {
            await loadGiftCard()
        }

        giftCardsDAO.giftCardTxIdPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] publishedTxId in
                guard let self = self,
                      let publishedTxId = publishedTxId,
                      publishedTxId == self.txId else { return }

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
                        guard metadata.txHash == self.txId else { return }
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
                transaction.txHashData == self.txId
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

        let formattedPrice = currencyFormatter.string(from: card.price as NSDecimalNumber) ?? "$0.00"
        let displayCards = buildDisplayCards(from: card, fallbackFormattedPrice: formattedPrice)
        let isClaimLink = displayCards.first?.isClaimLink ?? (card.number?.starts(with: "http") ?? false)
        let barcodeImage = displayCards.first?.barcodeImage ?? imageFromBarcode(value: card.barcodeValue, format: card.barcodeFormat)

        await MainActor.run {
            self.uiState.merchantName = card.merchantName
            self.uiState.merchantUrl = card.merchantUrl
            self.uiState.formattedPrice = formattedPrice
            self.uiState.cardNumber = card.number
            self.uiState.cardPin = card.pin
            self.uiState.provider = card.provider
            self.uiState.isClaimLink = isClaimLink
            self.uiState.barcodeImage = barcodeImage
            self.uiState.cards = displayCards

            if shouldStartPolling(for: card, hasDisplayCards: !displayCards.isEmpty) {
                self.startTicker()
            } else {
                self.stopTicker()
            }
        }
    }

    private func shouldStartPolling(for card: GiftCard, hasDisplayCards: Bool) -> Bool {
        guard card.note != nil else { return false }

        if card.provider == "PiggyCards" {
            if let note = card.note, decodeOrderMetadata(from: note).cards?.isEmpty == false {
                return false
            }
            return !hasDisplayCards
        }

        return card.number == nil
    }

    private func startTicker() {
        guard tickerTimer == nil else { return }

        uiState.isLoadingCardDetails = true
        uiState.loadingError = nil

        Task {
            await fetchGiftCardInfo()
        }

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
        uiState.hasBeenPollingForLongTime = false
        retryCount = 0
    }

    private func fetchGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              giftCard.note != nil else {
            stopTicker()
            return
        }

        if retryCount >= longPollingThreshold {
            await MainActor.run {
                self.uiState.hasBeenPollingForLongTime = true
            }
        }

        let providerName = giftCard.provider ?? "nil (defaulting to CTX)"
        let txIdHex = txId.map { String(format: "%02x", $0) }.joined()
        DSLogger.log("DashSpend: Fetching gift card - Provider: \(providerName), TxId: \(txIdHex)")

        if giftCard.provider == "PiggyCards" {
            await fetchPiggyCardsGiftCardInfo()
        } else {
            await fetchCTXGiftCardInfo()
        }
    }

    private func fetchCTXGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              giftCard.note != nil,
              ctxSpendRepository.isUserSignedIn else {
            stopTicker()
            return
        }

        do {
            let base58TxId = ((txId as NSData).reverse() as NSData).base58String()
            DSLogger.log("DashSpend: Calling CTX API - Base58TxId: \(base58TxId)")
            let response = try await ctxSpendRepository.getGiftCardByTxid(txid: base58TxId)

            switch response.status {
            case "fulfilled":
                if let cardNumber = response.cardNumber, !cardNumber.isEmpty {
                    await giftCardsDAO.updateCardDetails(
                        txId: txId,
                        number: cardNumber,
                        pin: response.cardPin
                    )

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
                } else if let redeemUrl = response.redeemUrl, !redeemUrl.isEmpty {
                    await giftCardsDAO.updateCardDetails(
                        txId: txId,
                        number: redeemUrl,
                        pin: nil
                    )
                    stopTicker()
                    DSLogger.log("DashSpend: Gift card redeem URL fetched successfully")
                }

            case "rejected":
                await MainActor.run {
                    self.uiState.loadingError = DashSpendError.customError(
                        NSLocalizedString("Gift card purchase was rejected", comment: "")
                    )
                }
                stopTicker()

            default:
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

    private func fetchPiggyCardsGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              let note = giftCard.note,
              piggyCardsRepository.isUserSignedIn else {
            stopTicker()
            return
        }

        let metadata = decodeOrderMetadata(from: note)

        do {
            DSLogger.log("DashSpend: Calling PiggyCards API - OrderId: \(metadata.orderId)")
            let orderStatus = try await piggyCardsRepository.getOrderStatus(orderId: metadata.orderId)

            switch orderStatus.data.status.lowercased() {
            case "complete", "completed":
                let payload = await buildPayloadEntries(
                    cards: orderStatus.data.cards,
                    fallbackFormattedPrice: uiState.formattedPrice,
                    expectedAmounts: metadata.cardAmounts
                )

                guard !payload.isEmpty else {
                    await MainActor.run {
                        self.uiState.loadingError = DashSpendError.customError(
                            NSLocalizedString("Gift card details are unavailable. Please contact support.", comment: "")
                        )
                    }
                    stopTicker()
                    return
                }

                let completedMetadata = GiftCardOrderMetadata(
                    orderId: metadata.orderId,
                    cardAmounts: metadata.cardAmounts,
                    cards: payload
                )
                let serializedNote = encodeOrderMetadata(completedMetadata) ?? note
                let firstEntry = payload.first

                let updatedCard = GiftCard(
                    txId: giftCard.txId,
                    merchantName: giftCard.merchantName,
                    merchantUrl: giftCard.merchantUrl,
                    price: giftCard.price,
                    number: firstEntry?.cardNumber,
                    pin: firstEntry?.cardPin,
                    barcodeValue: firstEntry?.barcodeValue,
                    barcodeFormat: firstEntry?.barcodeFormat,
                    note: serializedNote,
                    provider: giftCard.provider
                )

                await giftCardsDAO.update(dto: updatedCard)
                stopTicker()

            case "failed", "rejected", "cancelled":
                await MainActor.run {
                    self.uiState.loadingError = DashSpendError.customError(
                        NSLocalizedString("Gift card purchase was rejected", comment: "")
                    )
                }
                stopTicker()

            default:
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
        }
    }

    private func buildPayloadEntries(
        cards: [PiggyCardsOrderGiftCard],
        fallbackFormattedPrice: String,
        expectedAmounts: [String]?
    ) async -> [GiftCardPayloadEntry] {
        var entries: [GiftCardPayloadEntry] = []

        for (index, card) in cards.enumerated() {
            let formattedPrice = formattedPriceForCard(
                amountString: expectedAmounts?[safe: index],
                fallbackFormattedPrice: fallbackFormattedPrice
            )

            if let claimCode = card.claimCode, !claimCode.isEmpty {
                let cleanCode = claimCode.replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")

                var barcodeValue = cleanCode
                var barcodeFormat = "CODE_128"

                if let barcodeLink = card.barcodeLink, !barcodeLink.isEmpty {
                    if let parsed = parseBarcodePayload(from: barcodeLink) {
                        barcodeValue = parsed.value
                        barcodeFormat = parsed.format
                    } else if let result = await BarcodeScanner.downloadAndScan(from: barcodeLink) {
                        barcodeValue = result.value.replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: "-", with: "")
                        barcodeFormat = result.format.rawValue
                    }
                }

                entries.append(
                    GiftCardPayloadEntry(
                        formattedPrice: formattedPrice,
                        cardNumber: claimCode,
                        cardPin: card.claimPin,
                        barcodeValue: barcodeValue,
                        barcodeFormat: barcodeFormat,
                        isClaimLink: false
                    )
                )
            } else if let claimLink = card.claimLink, !claimLink.isEmpty {
                entries.append(
                    GiftCardPayloadEntry(
                        formattedPrice: formattedPrice,
                        cardNumber: claimLink,
                        cardPin: nil,
                        barcodeValue: nil,
                        barcodeFormat: nil,
                        isClaimLink: true
                    )
                )
            }
        }

        return entries
    }

    private func decodeOrderMetadata(from note: String) -> GiftCardOrderMetadata {
        guard let data = note.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GiftCardOrderMetadata.self, from: data) else {
            return GiftCardOrderMetadata(orderId: note, cardAmounts: nil, cards: nil)
        }

        return decoded
    }

    private func encodeOrderMetadata(_ metadata: GiftCardOrderMetadata) -> String? {
        guard let data = try? JSONEncoder().encode(metadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func buildDisplayCards(from card: GiftCard, fallbackFormattedPrice: String) -> [GiftCardDetailsCardItem] {
        if let note = card.note, let payload = decodeOrderMetadata(from: note).cards, !payload.isEmpty {
            return payload.enumerated().map { index, entry in
                GiftCardDetailsCardItem(
                    id: "\(index)-\(entry.cardNumber ?? "")",
                    formattedPrice: entry.formattedPrice,
                    cardNumber: entry.cardNumber,
                    cardPin: entry.cardPin,
                    barcodeImage: imageFromBarcode(value: entry.barcodeValue, format: entry.barcodeFormat),
                    isClaimLink: entry.isClaimLink
                )
            }
        }

        if card.number != nil || card.pin != nil || card.barcodeValue != nil {
            return [
                GiftCardDetailsCardItem(
                    id: "legacy-0",
                    formattedPrice: fallbackFormattedPrice,
                    cardNumber: card.number,
                    cardPin: card.pin,
                    barcodeImage: imageFromBarcode(value: card.barcodeValue, format: card.barcodeFormat),
                    isClaimLink: card.number?.starts(with: "http") ?? false
                )
            ]
        }

        return []
    }

    private func formattedPriceForCard(amountString: String?, fallbackFormattedPrice: String) -> String {
        guard let amountString,
              let amount = Decimal(string: amountString) else {
            return fallbackFormattedPrice
        }

        return currencyFormatter.string(from: amount as NSDecimalNumber) ?? fallbackFormattedPrice
    }

    private func parseBarcodePayload(from link: String) -> (value: String, format: String)? {
        guard let components = URLComponents(string: link),
              let queryItems = components.queryItems,
              !queryItems.isEmpty else { return nil }

        let loweredItems = queryItems.reduce(into: [String: String]()) { dict, item in
            guard let value = item.value, !value.isEmpty else { return }
            dict[item.name.lowercased()] = value
        }

        let valueKeys = ["text", "data", "code", "barcode"]
        guard let rawValue = valueKeys.compactMap({ loweredItems[$0] }).first, !rawValue.isEmpty else {
            return nil
        }

        let formatCandidate = loweredItems["format"] ?? loweredItems["type"] ?? loweredItems["symbology"]
        let normalizedValue = rawValue
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        return (normalizedValue, normalizeBarcodeFormat(formatCandidate))
    }

    private func normalizeBarcodeFormat(_ rawFormat: String?) -> String {
        let normalized = (rawFormat ?? "CODE_128")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "CODE128", "CODE_128": return "CODE_128"
        case "QRCODE", "QR_CODE", "QR": return "QR_CODE"
        case "PDF417", "PDF_417": return "PDF_417"
        case "AZTEC", "AZTEC_CODE": return "AZTEC"
        case "DATAMATRIX", "DATA_MATRIX": return "DATA_MATRIX"
        default: return "CODE_128"
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

    private func imageFromBarcode(value: String?, format: String?) -> UIImage? {
        guard let value, !value.isEmpty else { return nil }
        let normalizedFormat = normalizeBarcodeFormat(format)

        let filterName: String
        let transform: CGAffineTransform
        switch normalizedFormat {
        case "QR_CODE":
            filterName = "CIQRCodeGenerator"
            transform = CGAffineTransform(scaleX: 6.0, y: 6.0)
        case "PDF_417":
            filterName = "CIPDF417BarcodeGenerator"
            transform = CGAffineTransform(scaleX: 3.0, y: 3.0)
        case "AZTEC":
            filterName = "CIAztecCodeGenerator"
            transform = CGAffineTransform(scaleX: 6.0, y: 6.0)
        case "DATA_MATRIX":
            filterName = "CIDataMatrixCodeGenerator"
            transform = CGAffineTransform(scaleX: 8.0, y: 8.0)
        default:
            filterName = "CICode128BarcodeGenerator"
            transform = CGAffineTransform(scaleX: 3.0, y: 5.0)
        }

        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(value.data(using: .utf8), forKey: "inputMessage")
        if normalizedFormat == "QR_CODE" {
            filter.setValue("M", forKey: "inputCorrectionLevel")
        }

        guard let outputImage = filter.outputImage else { return nil }
        let transformedImage = outputImage.transformed(by: transform)
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension GiftCardDetailsViewModel {
    static func previewBarcodeCard() -> GiftCardDetailsViewModel {
        let viewModel = GiftCardDetailsViewModel(txId: Data(), shouldLoadTransaction: false)
        viewModel.uiState = GiftCardDetailsUIState(
            merchantName: "Amazon",
            merchantUrl: "https://www.amazon.com",
            formattedPrice: "$75.00",
            cardNumber: "1234 5678 9012",
            cardPin: "7890",
            barcodeImage: UIImage(systemName: "barcode.viewfinder"),
            merchantIcon: UIImage(systemName: "cart.fill"),
            purchaseDate: Date(timeIntervalSince1970: 1_713_484_800),
            isLoadingCardDetails: false,
            loadingError: nil,
            transaction: nil,
            isClaimLink: false,
            hasBeenPollingForLongTime: false,
            provider: "CTX",
            cards: [
                GiftCardDetailsCardItem(
                    id: "preview-1",
                    formattedPrice: "$75.00",
                    cardNumber: "1234 5678 9012",
                    cardPin: "7890",
                    barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                    isClaimLink: false
                )
            ]
        )
        return viewModel
    }

    static func previewClaimLinkCard() -> GiftCardDetailsViewModel {
        let viewModel = GiftCardDetailsViewModel(txId: Data(), shouldLoadTransaction: false)
        viewModel.uiState = GiftCardDetailsUIState(
            merchantName: "Steam",
            merchantUrl: "https://store.steampowered.com",
            formattedPrice: "$50.00",
            cardNumber: "https://giftcards.example.com/claim/ABC123",
            cardPin: nil,
            barcodeImage: nil,
            merchantIcon: UIImage(systemName: "gamecontroller.fill"),
            purchaseDate: Date(timeIntervalSince1970: 1_713_571_200),
            isLoadingCardDetails: false,
            loadingError: nil,
            transaction: nil,
            isClaimLink: true,
            hasBeenPollingForLongTime: false,
            provider: "PiggyCards",
            cards: [
                GiftCardDetailsCardItem(
                    id: "preview-claim-1",
                    formattedPrice: "$50.00",
                    cardNumber: "https://giftcards.example.com/claim/ABC123",
                    cardPin: nil,
                    barcodeImage: nil,
                    isClaimLink: true
                )
            ]
        )
        return viewModel
    }

    static func previewLoadingCard() -> GiftCardDetailsViewModel {
        let viewModel = GiftCardDetailsViewModel(txId: Data(), shouldLoadTransaction: false)
        viewModel.uiState = GiftCardDetailsUIState(
            merchantName: "Target",
            merchantUrl: "https://www.target.com",
            formattedPrice: "$100.00",
            cardNumber: nil,
            cardPin: nil,
            barcodeImage: nil,
            merchantIcon: UIImage(systemName: "bag.fill"),
            purchaseDate: Date(timeIntervalSince1970: 1_713_657_600),
            isLoadingCardDetails: true,
            loadingError: nil,
            transaction: nil,
            isClaimLink: false,
            hasBeenPollingForLongTime: true,
            provider: "CTX",
            cards: []
        )
        return viewModel
    }

    static func previewMultipleCards() -> GiftCardDetailsViewModel {
        let viewModel = GiftCardDetailsViewModel(txId: Data(), shouldLoadTransaction: false)
        viewModel.uiState = GiftCardDetailsUIState(
            merchantName: "Amazon",
            merchantUrl: "https://www.amazon.com",
            formattedPrice: "$125.00",
            cardNumber: "1111 2222 3333",
            cardPin: "1234",
            barcodeImage: UIImage(systemName: "barcode.viewfinder"),
            merchantIcon: UIImage(systemName: "cart.fill"),
            purchaseDate: Date(timeIntervalSince1970: 1_713_484_800),
            isLoadingCardDetails: false,
            loadingError: nil,
            transaction: nil,
            isClaimLink: false,
            hasBeenPollingForLongTime: false,
            provider: "PiggyCards",
            cards: [
                GiftCardDetailsCardItem(
                    id: "preview-multi-1",
                    formattedPrice: "$25.00",
                    cardNumber: "1111 2222 3333",
                    cardPin: "1234",
                    barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                    isClaimLink: false
                ),
                GiftCardDetailsCardItem(
                    id: "preview-multi-2",
                    formattedPrice: "$100.00",
                    cardNumber: "4444 5555 6666",
                    cardPin: "9876",
                    barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                    isClaimLink: false
                )
            ]
        )
        return viewModel
    }
}

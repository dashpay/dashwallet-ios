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
    let redeemUrlChallenge: String?
    let barcodeImage: UIImage?
    let isClaimLink: Bool

    /// The link a claim-link card is redeemed at; such a card keeps it in `cardNumber`.
    var redeemLink: String? {
        isClaimLink ? Self.trimmedOrNil(cardNumber) : nil
    }

    var challengeCode: String? {
        Self.trimmedOrNil(redeemUrlChallenge)
    }

    static func trimmedOrNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// The value as it is, or nil when it is blank. Rows stored by earlier versions may hold a blank
    /// number or PIN, which is a missing one.
    static func nonBlank(_ value: String?) -> String? {
        trimmedOrNil(value) == nil ? nil : value
    }

    /// Whether a stored row holds anything to show as a card.
    static func hasStoredDetails(number: String?, pin: String?, barcodeValue: String?) -> Bool {
        nonBlank(number) != nil || nonBlank(pin) != nil || barcodeValue != nil
    }

    /// Whether a stored card number is in fact the card's link. Rows stored by earlier versions
    /// may hold it untrimmed.
    static func isLink(_ storedNumber: String?) -> Bool {
        guard let value = trimmedOrNil(storedNumber)?.lowercased() else { return false }
        return value.hasPrefix("https://") || value.hasPrefix("http://")
    }

    /// The card of an order stored without a per-card payload.
    static func stored(formattedPrice: String,
                       number: String?,
                       pin: String?,
                       redeemUrlChallenge: String?,
                       barcodeImage: UIImage?) -> GiftCardDetailsCardItem {
        GiftCardDetailsCardItem(
            id: "legacy-0",
            formattedPrice: formattedPrice,
            cardNumber: nonBlank(number),
            cardPin: nonBlank(pin),
            redeemUrlChallenge: redeemUrlChallenge,
            barcodeImage: barcodeImage,
            isClaimLink: isLink(number)
        )
    }
}

/// What a fulfilled CTX order delivered. A card number wins over a redeem link; a blank one of either is none.
enum CTXGiftCardDelivery: Equatable {
    case number(String, pin: String?)
    case link(String, challenge: String?)
    case nothingYet

    init(cardNumber: String?, cardPin: String?, redeemUrl: String?, redeemUrlChallenge: String?) {
        if let cardNumber = GiftCardDetailsCardItem.trimmedOrNil(cardNumber) {
            self = .number(cardNumber, pin: GiftCardDetailsCardItem.nonBlank(cardPin))
        } else if let link = GiftCardDetailsCardItem.trimmedOrNil(redeemUrl) {
            self = .link(link, challenge: GiftCardDetailsCardItem.trimmedOrNil(redeemUrlChallenge))
        } else {
            self = .nothingYet
        }
    }

    /// Whether a stored CTX row still waits for what its order delivers.
    static func isAwaited(storedNumber: String?) -> Bool {
        GiftCardDetailsCardItem.nonBlank(storedNumber) == nil
    }
}

struct GiftCardDetailsUIState {
    var merchantName: String = ""
    var merchantUrl: String? = nil
    var formattedPrice: String = "$0.00"
    var cardNumber: String? = nil
    var cardPin: String? = nil
    var redeemUrlChallenge: String? = nil
    var barcodeImage: UIImage? = nil
    var merchantIcon: UIImage? = nil
    var purchaseDate: Date? = nil
    var isLoadingCardDetails: Bool = false
    var loadingError: Error? = nil
    var transaction: Transaction? = nil
    var isClaimLink: Bool = false
    var hasBeenPollingForLongTime: Bool = false
    /// The poller stopped on a run of failures and the sheet may offer to start it again.
    var canRetryLoading: Bool = false
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
    let redeemUrlChallenge: String?
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
    /// Polls served since the ticker started, successful or not — drives the "still working on
    /// it" copy. Counting failures alone (as this once did) never reached the threshold while
    /// CTX was healthily answering "not fulfilled yet", so the hint never appeared.
    private var pollCount = 0
    /// Consecutive failed polls. Reset by any answered poll; drives the backoff and the give-up.
    private var errorStreak = 0
    /// Give up after this many consecutive failures. With the backoff below that is ~2 minutes
    /// of a CTX outage before the retry affordance is offered, instead of hammering it.
    private let maxErrorStreak = 8
    private let longPollingThreshold = 27
    private let basePollInterval: TimeInterval = 1.5
    private let maxPollInterval: TimeInterval = 30
    private var pollInterval: TimeInterval = 1.5

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

            let transaction = SwiftDashSDKWalletSource.fetch(txid: self.txId)

            await MainActor.run {
                if let tx = transaction {
                    self.uiState.purchaseDate = tx.date
                    self.uiState.transaction = tx
                }
            }
        }
    }

    private func loadGiftCard() async {
        guard let card = await giftCardsDAO.get(byTxId: txId) else { return }

        let formattedPrice = currencyFormatter.string(from: card.price as NSDecimalNumber) ?? "$0.00"
        let displayCards = buildDisplayCards(from: card, fallbackFormattedPrice: formattedPrice)
        let isClaimLink = displayCards.first?.isClaimLink ?? GiftCardDetailsCardItem.isLink(card.number)
        let barcodeImage = displayCards.first?.barcodeImage ?? imageFromBarcode(value: card.barcodeValue, format: card.barcodeFormat)

        await MainActor.run {
            self.uiState.merchantName = card.merchantName
            self.uiState.merchantUrl = card.merchantUrl
            self.uiState.formattedPrice = formattedPrice
            self.uiState.cardNumber = card.number
            self.uiState.cardPin = card.pin
            self.uiState.redeemUrlChallenge = card.redeemUrlChallenge
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

        return CTXGiftCardDelivery.isAwaited(storedNumber: card.number)
    }

    private func startTicker() {
        // `isLoadingCardDetails` is the synchronous claim: the first poll is awaited before a
        // timer exists, so guarding on `tickerTimer` alone would let a second `loadGiftCard`
        // (the DAO publisher fires on every write) start a parallel poller in that window.
        guard tickerTimer == nil, !uiState.isLoadingCardDetails else { return }

        uiState.isLoadingCardDetails = true
        uiState.loadingError = nil
        uiState.canRetryLoading = false

        Task {
            await fetchGiftCardInfo()
            scheduleNextPoll()
        }
    }

    /// Re-arms a single-shot timer at the current interval. Single-shot rather than repeating so
    /// a failing CTX backs off (doubling up to `maxPollInterval`) instead of being polled every
    /// 1.5 s for as long as the sheet is open.
    private func scheduleNextPoll() {
        guard uiState.isLoadingCardDetails else { return }

        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchGiftCardInfo()
                self?.scheduleNextPoll()
            }
        }
    }

    private func noteSuccessfulPoll() {
        errorStreak = 0
        pollInterval = basePollInterval
    }

    /// Resume polling after the ticker gave up on a run of failures (the "Retry" affordance).
    func retryLoadingCardDetails() {
        guard tickerTimer == nil else { return }

        errorStreak = 0
        pollInterval = basePollInterval
        startTicker()
    }

    private func stopTicker() {
        tickerTimer?.invalidate()
        tickerTimer = nil
        uiState.isLoadingCardDetails = false
        uiState.hasBeenPollingForLongTime = false
        pollCount = 0
        errorStreak = 0
        pollInterval = basePollInterval
    }

    private func fetchGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              giftCard.note != nil else {
            stopTicker()
            return
        }

        pollCount += 1
        if pollCount >= longPollingThreshold {
            await MainActor.run {
                self.uiState.hasBeenPollingForLongTime = true
            }
        }

        let providerName = giftCard.provider ?? "nil (defaulting to CTX)"
        let txIdHex = txId.map { String(format: "%02x", $0) }.joined()
        DWLogger.log("DashSpend: Fetching gift card - Provider: \(providerName), TxId: \(txIdHex)")

        if giftCard.provider == "PiggyCards" {
            await fetchPiggyCardsGiftCardInfo()
        } else {
            await fetchCTXGiftCardInfo()
        }
    }

    private func fetchCTXGiftCardInfo() async {
        guard let giftCard = await giftCardsDAO.get(byTxId: txId),
              ctxSpendRepository.isUserSignedIn else {
            stopTicker()
            return
        }

        do {
            let base58TxId = ScriptAddressCodec.base58Encode(Data(txId.reversed()))
            let response: GiftCardResponse

            if let orderId = giftCard.note?.trimmingCharacters(in: .whitespacesAndNewlines),
               !orderId.isEmpty {
                DWLogger.log("DashSpend: Calling CTX API - OrderId: \(orderId)")
                response = try await ctxSpendRepository.getGiftCardByOrderId(orderId: orderId)
            } else {
                DWLogger.log("DashSpend: Calling CTX API - Base58TxId: \(base58TxId)")
                response = try await ctxSpendRepository.getGiftCardByTxid(txid: base58TxId)
            }

            // An answered poll — whatever the order status — ends the failure streak and
            // returns the ticker to its base cadence.
            noteSuccessfulPoll()

            switch response.status {
            case "fulfilled":
                let delivery = CTXGiftCardDelivery(
                    cardNumber: response.cardNumber,
                    cardPin: response.cardPin,
                    redeemUrl: response.redeemUrl,
                    redeemUrlChallenge: response.redeemUrlChallenge
                )

                switch delivery {
                case .number(let cardNumber, let pin):
                    await giftCardsDAO.updateCardDetails(
                        txId: txId,
                        number: cardNumber,
                        pin: pin
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
                    DWLogger.log("DashSpend: Gift card details fetched successfully")
                case .link(let redeemUrl, let challenge):
                    await giftCardsDAO.updateRedeemUrl(
                        txId: txId,
                        url: redeemUrl,
                        challenge: challenge
                    )
                    stopTicker()
                    DWLogger.log("DashSpend: Gift card redeem URL fetched successfully")
                case .nothingYet:
                    break
                }

            case "rejected":
                await MainActor.run {
                    self.uiState.loadingError = DashSpendError.customError(
                        String(localized: "Gift card purchase was rejected", comment: "")
                    )
                }
                stopTicker()

            default:
                break
            }
        } catch {
            errorStreak += 1
            // Read before the give-up path: `stopTicker` resets the streak, so logging it
            // afterwards reported the last failure as attempt 0.
            let attempt = errorStreak
            if errorStreak >= maxErrorStreak {
                await MainActor.run {
                    self.uiState.loadingError = error
                    self.uiState.canRetryLoading = true
                }
                stopTicker()
            } else {
                pollInterval = min(pollInterval * 2, maxPollInterval)
            }
            DWLogger.log("DashSpend: Failed to fetch gift card info (attempt \(attempt)): \(error)")
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
            DWLogger.log("DashSpend: Calling PiggyCards API - OrderId: \(metadata.orderId)")
            let orderStatus = try await piggyCardsRepository.getOrderStatus(orderId: metadata.orderId)
            noteSuccessfulPoll()

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
                            String(localized: "Gift card details are unavailable. Please contact support.", comment: "")
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
                    provider: giftCard.provider,
                    redeemUrlChallenge: giftCard.redeemUrlChallenge
                )

                await giftCardsDAO.update(dto: updatedCard)
                stopTicker()

            case "failed", "rejected", "cancelled":
                await MainActor.run {
                    self.uiState.loadingError = DashSpendError.customError(
                        String(localized: "Gift card purchase was rejected", comment: "")
                    )
                }
                stopTicker()

            default:
                break
            }
        } catch {
            errorStreak += 1
            if errorStreak >= maxErrorStreak {
                await MainActor.run {
                    self.uiState.loadingError = error
                    self.uiState.canRetryLoading = true
                }
                stopTicker()
            } else {
                pollInterval = min(pollInterval * 2, maxPollInterval)
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
                        redeemUrlChallenge: nil,
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
                        redeemUrlChallenge: nil,
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
                    redeemUrlChallenge: entry.redeemUrlChallenge,
                    barcodeImage: imageFromBarcode(value: entry.barcodeValue, format: entry.barcodeFormat),
                    isClaimLink: entry.isClaimLink
                )
            }
        }

        if GiftCardDetailsCardItem.hasStoredDetails(number: card.number,
                                                    pin: card.pin,
                                                    barcodeValue: card.barcodeValue) {
            return [
                GiftCardDetailsCardItem.stored(
                    formattedPrice: fallbackFormattedPrice,
                    number: card.number,
                    pin: card.pin,
                    redeemUrlChallenge: card.redeemUrlChallenge,
                    barcodeImage: imageFromBarcode(value: card.barcodeValue, format: card.barcodeFormat)
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
                DWLogger.log("Failed to create image from data for tx icon: \(metadata.txHash.hexEncodedString())")
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
            redeemUrlChallenge: nil,
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
                    redeemUrlChallenge: nil,
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
            redeemUrlChallenge: "ABC1-2345",
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
                    redeemUrlChallenge: "ABC1-2345",
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
            redeemUrlChallenge: nil,
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
            redeemUrlChallenge: nil,
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
                    redeemUrlChallenge: nil,
                    barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                    isClaimLink: false
                ),
                GiftCardDetailsCardItem(
                    id: "preview-multi-2",
                    formattedPrice: "$100.00",
                    cardNumber: "4444 5555 6666",
                    cardPin: "9876",
                    redeemUrlChallenge: nil,
                    barcodeImage: UIImage(systemName: "barcode.viewfinder"),
                    isClaimLink: false
                )
            ]
        )
        return viewModel
    }
}

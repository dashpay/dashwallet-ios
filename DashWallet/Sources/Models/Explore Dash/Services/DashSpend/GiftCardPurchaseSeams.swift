//
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
import Foundation

// What `DashSpendPayViewModel` asks of the provider repositories, the send service and the
// stores a purchase is written to. The view model holds these instead of the shared
// instances, so a test can run a purchase with a provider answer it controls.

/// Whether the buyer is signed in to a gift card provider.
@MainActor
protocol GiftCardProviderSession: AnyObject {
    var isUserSignedIn: Bool { get }
    var isUserSignedInPublisher: AnyPublisher<Bool, Never> { get }
}

/// The CTX calls the purchase screen makes.
@MainActor
protocol CTXGiftCardOrdering: GiftCardProviderSession {
    func getMerchant(merchantId: String) async throws -> MerchantResponse
    func purchaseGiftCard(merchantId: String, fiatAmount: String, fiatCurrency: String,
                          cryptoCurrency: String) async throws -> GiftCardResponse
}

extension CTXSpendRepository: CTXGiftCardOrdering {}

/// The PiggyCards calls the purchase screen makes.
@MainActor
protocol PiggyCardsGiftCardOrdering: GiftCardProviderSession {
    func getGiftCards(country: String, sourceId: String, merchantId: String) async throws -> [PiggyCardsGiftcard]
    func orderGiftCards(merchantId: String, lineItems: [PiggyCardsRepository.OrderLineItem],
                        fiatCurrency: String, cryptoCurrency: String) async throws -> GiftCardInfo
}

extension PiggyCardsRepository: PiggyCardsGiftCardOrdering {}

/// The two ways a gift card order is paid: a payment request URL (CTX) and a plain address
/// with an amount (PiggyCards). Both return the wire-order txid of the payment, and both
/// throw `DashSpendError.paymentStatusUnknown` with the txid when the payment was handed to
/// the network and its outcome is unknown.
protocol GiftCardPaying {
    func payWithDashUrl(url paymentUrlString: String, awaitAcceptance: Bool,
                        validate: @escaping (Confirmation) async throws -> Void) async throws -> Data
    func payGiftCardOrder(address: String, amount: UInt64) async throws -> Data
}

extension SendCoinsService: GiftCardPaying {}

/// Everything that ties a paid order to its transaction.
struct GiftCardPurchaseRecord: Equatable {
    /// Wire-order txid (`Transaction.txHashData` convention): the key of every row written.
    let txidWire: Data
    let provider: GiftCardProvider
    let merchantName: String
    let merchantUrl: String?
    let merchantIconUrl: String
    /// The card value the buyer confirmed, stored as the card's price.
    let price: Decimal
    /// The order id, or the order metadata, the details poller reads.
    let note: String
}

@MainActor
protocol GiftCardPurchaseRecording {
    func record(_ purchase: GiftCardPurchaseRecord)
}

/// Sets the merchant icon a purchase's transaction shows.
protocol GiftCardIconUpdating {
    func updateIcon(txId: Data, iconUrl: String)
}

extension CustomIconMetadataProvider: GiftCardIconUpdating {}

/// Writes a purchase to the app's stores: the tax and service metadata of the transaction,
/// the merchant icon, and the `gift_cards` row whose `note` carries the order id.
@MainActor
final class GiftCardPurchaseStore: GiftCardPurchaseRecording {
    private let makeTxMetadataDao: () -> TransactionMetadataDAO
    private let makeIconProvider: () -> GiftCardIconUpdating
    private let makeGiftCardsDao: () -> GiftCardsDAO
    private lazy var txMetadataDao = makeTxMetadataDao()
    private lazy var customIconProvider = makeIconProvider()
    private lazy var giftCardsDao = makeGiftCardsDao()

    /// Each store is made on the first purchase; by default, the app's shared one.
    init(txMetadata: @escaping () -> TransactionMetadataDAO = { TransactionMetadataDAOImpl.shared },
         icons: @escaping () -> GiftCardIconUpdating = { CustomIconMetadataProvider.shared },
         giftCards: @escaping () -> GiftCardsDAO = { GiftCardsDAOImpl.shared }) {
        makeTxMetadataDao = txMetadata
        makeIconProvider = icons
        makeGiftCardsDao = giftCards
    }

    func record(_ purchase: GiftCardPurchaseRecord) {
        var txMetadata = TransactionMetadata(txHash: purchase.txidWire)
        txMetadata.taxCategory = TxMetadataTaxCategory.expense
        switch purchase.provider {
        case .ctx:
            txMetadata.service = ServiceName.ctxSpend.rawValue
        #if PIGGYCARDS_ENABLED
        case .piggyCards:
            txMetadata.service = ServiceName.piggyCards.rawValue
        #endif
        }
        txMetadataDao.update(dto: txMetadata)

        customIconProvider.updateIcon(txId: purchase.txidWire, iconUrl: purchase.merchantIconUrl)

        DWLogger.log("Gift card saved - txId: \(purchase.txidWire.hexEncodedString())")
        let giftCard = GiftCard(
            txId: purchase.txidWire,
            merchantName: purchase.merchantName,
            merchantUrl: purchase.merchantUrl,
            price: purchase.price,
            note: purchase.note,
            provider: purchase.provider.displayName)
        let giftCardsDao = giftCardsDao
        Task {
            await giftCardsDao.create(dto: giftCard)
        }
    }
}

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

import SQLite
import XCTest
@testable import dashpay

final class GiftCardLinkRulesTests: XCTestCase {
    private let ctxLink = "https://spend.ctx.com/gift-cards/abc/redeem"

    /// A card as the sheet builds it from a stored gift card row.
    private func stored(number: String?, pin: String? = nil, challenge: String? = nil) -> GiftCardDetailsCardItem {
        GiftCardDetailsCardItem.stored(
            formattedPrice: "$10.00",
            number: number,
            pin: pin,
            redeemUrlChallenge: challenge,
            barcodeImage: nil
        )
    }

    /// A card of a PiggyCards order, whose stored payload says itself whether it is a claim link.
    private func payloadCard(number: String?, isClaimLink: Bool) -> GiftCardDetailsCardItem {
        GiftCardDetailsCardItem(
            id: "0-test",
            formattedPrice: "$10.00",
            cardNumber: number,
            cardPin: nil,
            redeemUrlChallenge: nil,
            barcodeImage: nil,
            isClaimLink: isClaimLink
        )
    }

    private func delivery(number: String? = nil,
                          pin: String? = nil,
                          link: String? = nil,
                          challenge: String? = nil) -> CTXGiftCardDelivery {
        CTXGiftCardDelivery(cardNumber: number, cardPin: pin, redeemUrl: link, redeemUrlChallenge: challenge)
    }

    // MARK: What the sheet shows

    func testStoredLinkWithChallengeOffersBoth() {
        let card = stored(number: ctxLink, challenge: "A1B2C3D4E5")

        XCTAssertTrue(card.isClaimLink)
        XCTAssertEqual(card.redeemLink, ctxLink)
        XCTAssertEqual(card.challengeCode, "A1B2C3D4E5")
    }

    func testStoredLinkIsFoundWhateverTheSchemeCase() {
        for link in ["HTTPS://SPEND.CTX.COM/gift-cards/abc/redeem", "Http://piggy.cards/claim/abc", "http://piggy.cards/claim/abc"] {
            let card = stored(number: link)

            XCTAssertTrue(card.isClaimLink, link)
            XCTAssertEqual(card.redeemLink, link)
        }
    }

    func testUntrimmedStoredLinkIsStillALink() {
        let card = stored(number: " \(ctxLink)\n", challenge: "  A1B2C3D4E5 ")

        XCTAssertTrue(card.isClaimLink)
        XCTAssertEqual(card.redeemLink, ctxLink)
        XCTAssertEqual(card.challengeCode, "A1B2C3D4E5")
    }

    func testBlankChallengeIsNoChallenge() {
        XCTAssertNil(stored(number: ctxLink, challenge: nil).challengeCode)
        XCTAssertNil(stored(number: ctxLink, challenge: "").challengeCode)
        XCTAssertNil(stored(number: ctxLink, challenge: " \n\t").challengeCode)
    }

    func testStoredNumberIsNotALink() {
        let numbers = [
            "6006 4912 3456 7890",
            "6006http://4912",
            "ABC-https://-123",
            "httpx-1234",
            "https:1234",
            "http",
        ]

        for number in numbers {
            let card = stored(number: number)

            XCTAssertFalse(card.isClaimLink, number)
            XCTAssertNil(card.redeemLink, number)
            XCTAssertEqual(card.cardNumber, number)
        }
        XCTAssertFalse(stored(number: nil).isClaimLink)
    }

    func testBlankStoredNumberIsNoNumber() {
        for number in ["", "   ", " \n\t"] {
            let card = stored(number: number)

            XCTAssertNil(card.cardNumber, number)
            XCTAssertFalse(card.isClaimLink, number)
            XCTAssertNil(card.redeemLink, number)
        }
    }

    func testBlankStoredPinIsNoPinAndAValidOneIsKeptAsStored() {
        XCTAssertNil(stored(number: "6006491234567890", pin: "").cardPin)
        XCTAssertNil(stored(number: "6006491234567890", pin: " \n").cardPin)
        XCTAssertEqual(stored(number: "6006491234567890", pin: "0042").cardPin, "0042")
        XCTAssertEqual(stored(number: "6006491234567890", pin: " 12 34 ").cardPin, " 12 34 ")
    }

    func testBlankStoredRowShowsNoCard() {
        XCTAssertFalse(GiftCardDetailsCardItem.hasStoredDetails(number: nil, pin: nil, barcodeValue: nil))
        XCTAssertFalse(GiftCardDetailsCardItem.hasStoredDetails(number: "  \n", pin: " ", barcodeValue: nil))
        XCTAssertFalse(GiftCardDetailsCardItem.hasStoredDetails(number: "  ", pin: nil, barcodeValue: ""))
        XCTAssertFalse(GiftCardDetailsCardItem.hasStoredDetails(number: nil, pin: nil, barcodeValue: " \n"))
        XCTAssertTrue(GiftCardDetailsCardItem.hasStoredDetails(number: "6006491234567890", pin: nil, barcodeValue: nil))
        XCTAssertTrue(GiftCardDetailsCardItem.hasStoredDetails(number: " ", pin: "1234", barcodeValue: nil))
        XCTAssertTrue(GiftCardDetailsCardItem.hasStoredDetails(number: nil, pin: nil, barcodeValue: "6006491234567890"))
    }

    func testCardWithoutANumberOrALinkLacksBoth() {
        XCTAssertTrue(stored(number: "  ", pin: "1234").lacksNumberAndLink)
        XCTAssertTrue(stored(number: nil, pin: "1234").lacksNumberAndLink)
        XCTAssertTrue(payloadCard(number: "   ", isClaimLink: true).lacksNumberAndLink)
        XCTAssertFalse(stored(number: "6006491234567890").lacksNumberAndLink)
        XCTAssertFalse(stored(number: ctxLink).lacksNumberAndLink)
    }

    func testPayloadCardFollowsItsOwnFlag() {
        XCTAssertEqual(payloadCard(number: " https://piggy.cards/claim/abc ", isClaimLink: true).redeemLink,
                       "https://piggy.cards/claim/abc")
        XCTAssertNil(payloadCard(number: "   ", isClaimLink: true).redeemLink)
        XCTAssertNil(payloadCard(number: nil, isClaimLink: true).redeemLink)
        XCTAssertNil(payloadCard(number: "6006 4912 3456 7890", isClaimLink: false).redeemLink)
    }

    // MARK: What a fulfilled CTX order delivered

    func testLinkOnlyOrderDeliversTheTrimmedLinkAndChallenge() {
        XCTAssertEqual(
            delivery(link: " https://spend.ctx.com/gift-cards/abc/redeem ", challenge: " A1B2C3D4E5\n"),
            .link("https://spend.ctx.com/gift-cards/abc/redeem", challenge: "A1B2C3D4E5")
        )
        XCTAssertEqual(
            delivery(number: "", link: "https://spend.ctx.com/gift-cards/abc/redeem", challenge: "  "),
            .link("https://spend.ctx.com/gift-cards/abc/redeem", challenge: nil)
        )
    }

    func testNumberWinsOverLink() {
        XCTAssertEqual(
            delivery(number: "6006491234567890",
                     pin: "1234",
                     link: "https://spend.ctx.com/gift-cards/abc/redeem",
                     challenge: "A1B2C3D4E5"),
            .number("6006491234567890", pin: "1234")
        )
        XCTAssertEqual(delivery(number: " 6006491234567890\n"), .number("6006491234567890", pin: nil))
    }

    func testBlankNumberDoesNotBeatALink() {
        XCTAssertEqual(
            delivery(number: "  \n", pin: "1234", link: "https://spend.ctx.com/gift-cards/abc/redeem"),
            .link("https://spend.ctx.com/gift-cards/abc/redeem", challenge: nil)
        )
        XCTAssertEqual(delivery(number: " ", pin: "1234"), .nothingYet)
    }

    func testBlankPinIsNoPinAndAValidOneIsKeptAsDelivered() {
        XCTAssertEqual(delivery(number: "6006491234567890", pin: ""), .number("6006491234567890", pin: nil))
        XCTAssertEqual(delivery(number: "6006491234567890", pin: " \n"), .number("6006491234567890", pin: nil))
        XCTAssertEqual(delivery(number: "6006491234567890", pin: " 0042 "), .number("6006491234567890", pin: " 0042 "))
    }

    func testStoredRowWithABlankNumberIsStillAwaited() {
        let link = " https://spend.ctx.com/gift-cards/abc/redeem "

        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: nil, hasOrderReference: true))
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: "", hasOrderReference: true))
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: " \n", hasOrderReference: true))
        XCTAssertFalse(CTXGiftCardDelivery.isAwaited(storedNumber: "6006491234567890", hasOrderReference: true))
        XCTAssertFalse(CTXGiftCardDelivery.isAwaited(storedNumber: link, hasOrderReference: true))
    }

    func testRowWithoutAnOrderReferenceIsAwaitedOnlyWhenItsNumberWasWrittenBlank() {
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: "", hasOrderReference: false))
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: "  ", hasOrderReference: false))
        XCTAssertFalse(CTXGiftCardDelivery.isAwaited(storedNumber: nil, hasOrderReference: false))
        XCTAssertFalse(CTXGiftCardDelivery.isAwaited(storedNumber: "6006491234567890", hasOrderReference: false))
    }

    private func hasOrderToFetch(provider: String? = "CTX",
                                 hasOrderReference: Bool = false,
                                 number: String?,
                                 pin: String? = nil,
                                 barcodeValue: String? = nil) -> Bool {
        CTXGiftCardDelivery.hasOrderToFetch(
            provider: provider,
            hasOrderReference: hasOrderReference,
            number: number,
            pin: pin,
            barcodeValue: barcodeValue
        )
    }

    func testRowWithAnOrderReferenceHasAnOrderToFetch() {
        XCTAssertTrue(hasOrderToFetch(hasOrderReference: true, number: nil))
        XCTAssertTrue(hasOrderToFetch(provider: nil, hasOrderReference: true, number: "  ", pin: "1234"))
        XCTAssertTrue(hasOrderToFetch(provider: "PiggyCards", hasOrderReference: true, number: nil))
    }

    func testBlankRowWithoutAnOrderReferenceIsFetchedUnlessItHoldsABarcode() {
        XCTAssertTrue(hasOrderToFetch(number: "  "))
        XCTAssertTrue(hasOrderToFetch(provider: nil, number: "", barcodeValue: ""))
        XCTAssertTrue(hasOrderToFetch(number: "  ", pin: "1234"))
        XCTAssertFalse(hasOrderToFetch(number: "  ", pin: "1234", barcodeValue: "6006491234567890"))
        XCTAssertFalse(hasOrderToFetch(number: "  ", barcodeValue: "6006491234567890"))
        XCTAssertFalse(hasOrderToFetch(number: nil))
        XCTAssertFalse(hasOrderToFetch(number: "6006491234567890"))
    }

    func testPiggyCardsRowWithoutAnOrderReferenceIsNeverFetched() {
        XCTAssertFalse(hasOrderToFetch(provider: "PiggyCards", number: "  "))
        XCTAssertFalse(hasOrderToFetch(provider: "PiggyCards", number: nil))
    }

    func testFulfilledAnswersWithoutDetailsCountOnlyInARow() {
        XCTAssertEqual(CTXGiftCardDelivery.fulfilledAnswersWithoutDetails(after: 0, isFulfilled: true), 1)
        XCTAssertEqual(CTXGiftCardDelivery.fulfilledAnswersWithoutDetails(after: 59, isFulfilled: true), 60)
        XCTAssertEqual(CTXGiftCardDelivery.fulfilledAnswersWithoutDetails(after: 59, isFulfilled: false), 0)
        XCTAssertEqual(CTXGiftCardDelivery.fulfilledAnswersWithoutDetails(after: 0, isFulfilled: false), 0)
    }

    func testALaterLinkWithoutAChallengeKeepsTheOneAnotherAnswerStored() throws {
        let txId = Data([0x01, 0x02])
        let link = "https://spend.ctx.com/gift-cards/abc/redeem"
        let connection = try Connection(.inMemory)
        try connection.run(GiftCard.table.create { table in
            table.column(GiftCard.txId, primaryKey: true)
            table.column(GiftCard.number)
            table.column(GiftCard.redeemUrlChallenge)
        })
        try connection.run(GiftCard.table.insert(GiftCard.txId <- txId))

        func storedChallenge() throws -> String? {
            let row = try XCTUnwrap(connection.pluck(GiftCard.table))
            XCTAssertEqual(row[GiftCard.number], link)
            return row[GiftCard.redeemUrlChallenge]
        }

        try connection.run(GiftCardsDAOImpl.redeemUrlUpdate(txId: txId, url: link, challenge: nil))
        XCTAssertNil(try storedChallenge())

        try connection.run(GiftCardsDAOImpl.redeemUrlUpdate(txId: txId, url: link, challenge: "A1B2C3D4E5"))
        try connection.run(GiftCardsDAOImpl.redeemUrlUpdate(txId: txId, url: link, challenge: nil))
        XCTAssertEqual(try storedChallenge(), "A1B2C3D4E5")

        try connection.run(GiftCardsDAOImpl.redeemUrlUpdate(txId: txId, url: link, challenge: "F6G7H8I9J0"))
        XCTAssertEqual(try storedChallenge(), "F6G7H8I9J0")
    }

    @MainActor
    func testBlankStoredBarcodeDrawsNoImage() {
        let viewModel = GiftCardDetailsViewModel(txId: Data(), shouldLoadTransaction: false)

        XCTAssertNil(viewModel.imageFromBarcode(value: nil, format: nil))
        XCTAssertNil(viewModel.imageFromBarcode(value: "", format: nil))
        XCTAssertNil(viewModel.imageFromBarcode(value: " \t\n", format: "CODE128"))
        XCTAssertNotNil(viewModel.imageFromBarcode(value: "6006491234567890", format: "CODE128"))
    }

    func testSignInIsRequiredOnlyForAnOrderThatWouldBeFetched() {
        XCTAssertTrue(CTXGiftCardDelivery.isSignInRequired(isSignedIn: false, hasOrderToFetch: true))
        XCTAssertFalse(CTXGiftCardDelivery.isSignInRequired(isSignedIn: true, hasOrderToFetch: true))
        XCTAssertFalse(CTXGiftCardDelivery.isSignInRequired(isSignedIn: false, hasOrderToFetch: false))
    }

    func testAnAnswerWithoutAPinKeepsTheStoredOne() {
        XCTAssertEqual(CTXGiftCardDelivery.pinToStore(delivered: "0042", stored: "1234"), "0042")
        XCTAssertEqual(CTXGiftCardDelivery.pinToStore(delivered: nil, stored: "1234"), "1234")
        XCTAssertEqual(CTXGiftCardDelivery.pinToStore(delivered: " ", stored: " 12 34 "), " 12 34 ")
        XCTAssertNil(CTXGiftCardDelivery.pinToStore(delivered: nil, stored: "  "))
        XCTAssertNil(CTXGiftCardDelivery.pinToStore(delivered: nil, stored: nil))
    }

    func testFulfilledAnswersWithoutDetailsAreBounded() {
        let limit = CTXGiftCardDelivery.maxFulfilledAnswersWithoutDetails

        XCTAssertEqual(limit, 60)
        XCTAssertFalse(CTXGiftCardDelivery.isUnavailable(afterFulfilledAnswersWithoutDetails: 1))
        XCTAssertFalse(CTXGiftCardDelivery.isUnavailable(afterFulfilledAnswersWithoutDetails: limit - 1))
        XCTAssertTrue(CTXGiftCardDelivery.isUnavailable(afterFulfilledAnswersWithoutDetails: limit))
        XCTAssertTrue(CTXGiftCardDelivery.isUnavailable(afterFulfilledAnswersWithoutDetails: limit + 1))
    }

    func testBlankLinkKeepsWaiting() {
        XCTAssertEqual(delivery(), .nothingYet)
        XCTAssertEqual(delivery(number: "", link: ""), .nothingYet)
        XCTAssertEqual(delivery(link: "  \n", challenge: "A1B2C3D4E5"), .nothingYet)
    }
}

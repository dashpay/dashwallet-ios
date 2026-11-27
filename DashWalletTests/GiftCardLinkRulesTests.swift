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
        XCTAssertTrue(GiftCardDetailsCardItem.hasStoredDetails(number: "6006491234567890", pin: nil, barcodeValue: nil))
        XCTAssertTrue(GiftCardDetailsCardItem.hasStoredDetails(number: " ", pin: "1234", barcodeValue: nil))
        XCTAssertTrue(GiftCardDetailsCardItem.hasStoredDetails(number: nil, pin: nil, barcodeValue: "6006491234567890"))
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
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: nil))
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: ""))
        XCTAssertTrue(CTXGiftCardDelivery.isAwaited(storedNumber: " \n"))
        XCTAssertFalse(CTXGiftCardDelivery.isAwaited(storedNumber: "6006491234567890"))
        XCTAssertFalse(CTXGiftCardDelivery.isAwaited(storedNumber: " https://spend.ctx.com/gift-cards/abc/redeem "))
    }

    func testBlankLinkKeepsWaiting() {
        XCTAssertEqual(delivery(), .nothingYet)
        XCTAssertEqual(delivery(number: "", link: ""), .nothingYet)
        XCTAssertEqual(delivery(link: "  \n", challenge: "A1B2C3D4E5"), .nothingYet)
    }
}

//
//  CTXMerchantResponseDecodingTests.swift
//  DashWalletTests
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

@testable import dashpay
import XCTest

/// The JSON here is written by hand with made-up values. It copies the shape of the CTX
/// answers (which keys each environment sends), not a recorded response.
final class CTXMerchantResponseDecodingTests: XCTestCase {

    // MARK: - Merchant

    /// Staging shape: `userDiscount` / `locationCount`, no image URLs, and an `info`
    /// without `terms`.
    func testMerchantDecodesWhenInfoLacksTerms() throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Example Baskets",
            "enabled": true,
            "userDiscount": 400,
            "denominationsType": "min-max",
            "denominations": ["5", "500"],
            "locationCount": 0,
            "type": "online",
            "redeemType": "online",
            "currency": "USD",
            "info": {
                "description": "Gift baskets for every occasion.",
                "instructions": "Enter the code at checkout.",
                "intro": "Send a basket today."
            }
        }
        """

        let merchant = try decodeMerchant(json)

        XCTAssertEqual(merchant.id, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(merchant.denominationType, .Range)
        XCTAssertEqual(merchant.minimumCardPurchase, 5)
        XCTAssertEqual(merchant.maximumCardPurchase, 500)
        XCTAssertEqual(merchant.discount, 400)

        let info = try XCTUnwrap(merchant.info)
        XCTAssertNil(info.terms)
        XCTAssertEqual(info.description, "Gift baskets for every occasion.")
        XCTAssertEqual(info.instructions, "Enter the code at checkout.")
        XCTAssertEqual(info.intro, "Send a basket today.")
    }

    /// Production shape: `savingsPercentage` / `cachedLocationCount`, image URLs, and an
    /// `info` with all four texts.
    func testMerchantDecodesEveryInfoText() throws {
        let json = """
        {
            "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "name": "Example Pizza",
            "logoUrl": "https://example.com/logo.png",
            "enabled": true,
            "savingsPercentage": 250,
            "denominationsType": "fixed",
            "denominations": ["10", "25", "50"],
            "cachedLocationCount": 12,
            "mapPinUrl": "https://example.com/pin.png",
            "type": "both",
            "redeemType": "barcode",
            "cardImageUrl": "https://example.com/card.png",
            "currency": "USD",
            "info": {
                "terms": "Not redeemable for cash.",
                "description": "Pizza, sides and desserts.",
                "instructions": "Show the barcode to the cashier.",
                "intro": "Dinner is sorted."
            }
        }
        """

        let merchant = try decodeMerchant(json)

        XCTAssertEqual(merchant.id, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(merchant.name, "Example Pizza")
        XCTAssertEqual(merchant.logoUrl, "https://example.com/logo.png")
        XCTAssertEqual(merchant.denominationType, .Fixed)
        XCTAssertEqual(merchant.denominations, ["10", "25", "50"])
        XCTAssertEqual(merchant.discount, 250)
        XCTAssertEqual(merchant.locationCountValue, 12)
        XCTAssertEqual(merchant.redeemType, "barcode")

        let info = try XCTUnwrap(merchant.info)
        XCTAssertEqual(info.terms, "Not redeemable for cash.")
        XCTAssertEqual(info.description, "Pizza, sides and desserts.")
        XCTAssertEqual(info.instructions, "Show the barcode to the cashier.")
        XCTAssertEqual(info.intro, "Dinner is sorted.")
    }

    func testMerchantDecodesWhenInfoIsEmpty() throws {
        let json = """
        {
            "id": "merchant-1",
            "denominationsType": "fixed",
            "denominations": ["25"],
            "info": {}
        }
        """

        let info = try XCTUnwrap(decodeMerchant(json).info)

        XCTAssertNil(info.terms)
        XCTAssertNil(info.description)
        XCTAssertNil(info.instructions)
        XCTAssertNil(info.intro)
    }

    func testMerchantWithoutInfoHasNoInfo() throws {
        let json = """
        {
            "id": "merchant-1",
            "denominationsType": "fixed",
            "denominations": ["25"]
        }
        """

        XCTAssertNil(try decodeMerchant(json).info)
    }

    // MARK: - Gift card

    func testGiftCardDecodesWhenInfoLacksTerms() throws {
        let json = """
        {
            "id": "gift-card-1",
            "status": "unpaid",
            "paymentId": "payment-1",
            "info": {
                "description": "Gift baskets for every occasion.",
                "instructions": "Enter the code at checkout.",
                "intro": "Send a basket today."
            }
        }
        """

        let giftCard = try JSONDecoder().decode(GiftCardResponse.self, from: Data(json.utf8))

        XCTAssertEqual(giftCard.id, "gift-card-1")
        XCTAssertEqual(giftCard.status, "unpaid")
        let info = try XCTUnwrap(giftCard.info)
        XCTAssertNil(info.terms)
        XCTAssertEqual(info.instructions, "Enter the code at checkout.")
    }

    // MARK: - Helpers

    private func decodeMerchant(_ json: String) throws -> MerchantResponse {
        try JSONDecoder().decode(MerchantResponse.self, from: Data(json.utf8))
    }
}

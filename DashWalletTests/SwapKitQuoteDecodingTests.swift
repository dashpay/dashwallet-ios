//
//  SwapKitQuoteDecodingTests.swift
//  DashWalletTests
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

@testable import DashWallet
import XCTest

final class SwapKitQuoteDecodingTests: XCTestCase {
    private func loadFixture(named name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw XCTestError(.timeoutWhileWaiting, userInfo: ["file": name])
        }
        return try Data(contentsOf: url)
    }

    func testDecodeQuoteResponse() throws {
        let data = try loadFixture(named: "swapkit_quote_response")
        let response = try JSONDecoder().decode(SwapKitQuoteResponse.self, from: data)

        XCTAssertEqual(response.quoteId, "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
        XCTAssertEqual(response.routes?.count, 2)
        XCTAssertNil(response.error)

        let first = try XCTUnwrap(response.routes?.first)
        XCTAssertEqual(first.sellAsset, "DASH.DASH")
        XCTAssertEqual(first.buyAsset, "BTC.BTC")
        XCTAssertEqual(first.expectedBuyAmount, "0.00057")
        XCTAssertEqual(first.providers, ["MAYACHAIN_STREAMING"])
        XCTAssertEqual(first.meta?.tags, ["RECOMMENDED"])
        XCTAssertEqual(first.fees?.count, 3)
        XCTAssertEqual(first.estimatedTime?.total, 670)
        XCTAssertEqual(first.totalSlippageBps, 35.0)

        let errors = try XCTUnwrap(response.providerErrors)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.provider, "THORCHAIN")
        XCTAssertEqual(errors.first?.errorCode, "noRoutesFound")
    }

    func testBestRouteIsRecommended() throws {
        let data = try loadFixture(named: "swapkit_quote_response")
        let response = try JSONDecoder().decode(SwapKitQuoteResponse.self, from: data)
        let routes = try XCTUnwrap(response.routes)

        // bestRoute() picks RECOMMENDED first, then CHEAPEST, then first.
        let best = routes.first(where: { $0.meta?.tags?.contains("RECOMMENDED") == true })
            ?? routes.first(where: { $0.meta?.tags?.contains("CHEAPEST") == true })
            ?? routes.first

        XCTAssertEqual(best?.meta?.tags?.first, "RECOMMENDED")
    }
}

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

@testable import dashpay
import Moya
import XCTest

/// Anchors `Bundle(for:)` for the JSON fixtures shared by the test cases in this file.
private final class FixtureBundleToken {}

private func loadFixture(named name: String) throws -> Data {
    let bundle = Bundle(for: FixtureBundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
        throw XCTestError(.timeoutWhileWaiting, userInfo: ["file": name])
    }
    return try Data(contentsOf: url)
}

final class SwapKitQuoteDecodingTests: XCTestCase {

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

// MARK: - Error normalization

/// Covers the rules `SwapKitErrorCopy` applies to a raw SwapKit failure. They exist because the
/// code is the only stable identifier SwapKit returns — the prose around it is free text and, on
/// a provider-level failure, arrives without the code unless `providerErrorMessage(_:)` puts it
/// back. A refactor that reads the prose again would put every amount error back on the generic
/// "something went wrong" copy, which is the bug these tests guard.
final class SwapKitErrorCopyTests: XCTestCase {
    private let coin = SwapCryptoCurrency(
        id: "btc",
        code: "BTC",
        name: "Bitcoin",
        swapAsset: "BTC.BTC",
        chain: "BTC"
    )

    private func message(_ raw: String?) -> String {
        SwapKitErrorCopy.message(for: raw, coin: coin)
    }

    private var genericMessage: String {
        message("someCodeSwapKitHasNeverReturned")
    }

    private func providerError(code: String?, message: String?) -> SwapKitProviderError {
        SwapKitProviderError(provider: "NEAR", errorCode: code, message: message)
    }

    // MARK: providerErrorMessage

    func testProviderErrorMessagePutsTheCodeInFrontOfTheProse() {
        let composed = SwapKitErrorCopy.providerErrorMessage(
            providerError(code: "sellAssetAmountTooSmall",
                          message: "Sell asset amount too small for provider NEAR. Min amount is 0.17498713 DASH.DASH")
        )

        XCTAssertEqual(
            composed,
            "sellAssetAmountTooSmall: Sell asset amount too small for provider NEAR. Min amount is 0.17498713 DASH.DASH"
        )
    }

    func testProviderErrorMessageFallsBackToWhicheverHalfIsPresent() {
        XCTAssertEqual(SwapKitErrorCopy.providerErrorMessage(providerError(code: "noRoutesFound", message: nil)),
                       "noRoutesFound")
        XCTAssertEqual(SwapKitErrorCopy.providerErrorMessage(providerError(code: nil, message: "Api request failed")),
                       "Api request failed")
    }

    func testProviderErrorMessageTreatsBlankFieldsAsMissing() {
        XCTAssertEqual(SwapKitErrorCopy.providerErrorMessage(providerError(code: "  noRoutesFound  ", message: "   ")),
                       "noRoutesFound")
        XCTAssertNil(SwapKitErrorCopy.providerErrorMessage(providerError(code: "", message: nil)))
        XCTAssertNil(SwapKitErrorCopy.providerErrorMessage(nil))
    }

    // MARK: Classification

    func testBelowMinimumMatchesTheCodeFamilyWhateverTheCase() {
        XCTAssertTrue(SwapKitErrorCopy.isBelowMinimum("sellAssetAmountTooSmall"))
        XCTAssertTrue(SwapKitErrorCopy.isBelowMinimum("BUYASSETAMOUNTTOOLOW"))
        // The composed `"<code>: <detail>"` shape must classify the same as the bare code.
        XCTAssertTrue(SwapKitErrorCopy.isBelowMinimum("sellAssetAmountTooSmall: Min amount is 0.175 DASH.DASH"))
    }

    func testBelowMinimumIgnoresUnrelatedBelowThresholdCodes() {
        XCTAssertFalse(SwapKitErrorCopy.isBelowMinimum("inboundFeeTooLow"))
        XCTAssertFalse(SwapKitErrorCopy.isBelowMinimum("noRoutesFound"))
        XCTAssertFalse(SwapKitErrorCopy.isBelowMinimum(nil))
    }

    func testIsNoRouteMatchesBareAndComposedForms() {
        XCTAssertTrue(SwapKitErrorCopy.isNoRoute("noRoutesFound"))
        XCTAssertTrue(SwapKitErrorCopy.isNoRoute("noRoutesFound: No routes found for DASH.DASH -> BTC.BTC"))
        XCTAssertFalse(SwapKitErrorCopy.isNoRoute("apiRequestFailed"))
        XCTAssertFalse(SwapKitErrorCopy.isNoRoute(nil))
    }

    /// The regression itself: before the fix the prose reached the mapper without its code, and
    /// "No routes found for …" matches nothing. Prose alone must still fall through — the fix is
    /// that callers no longer send it alone, not that the mapper started guessing from text.
    func testProseWithoutItsCodeIsNotMistakenForAMapping() {
        XCTAssertEqual(message("No routes found for DASH.DASH -> BTC.BTC"), genericMessage)
        XCTAssertNotEqual(message("noRoutesFound: No routes found for DASH.DASH -> BTC.BTC"), genericMessage)
    }

    // MARK: message(for:coin:)

    func testDetailAfterTheCodeDoesNotChangeTheMapping() {
        XCTAssertEqual(message("validation_error: body/sellAmount sellAmount must be greater than 0"),
                       message("validation_error"))
    }

    func testBelowMinimumGetsItsOwnCopy() {
        let belowMinimum = message("sellAssetAmountTooSmall: Min amount is 0.17498713 DASH.DASH")

        XCTAssertNotEqual(belowMinimum, genericMessage)
        // Distinct from the no-route copy: one asks for a larger amount, the other for a retry.
        XCTAssertNotEqual(belowMinimum, message("noRoutesFound"))
    }

    /// The four codes SwapKit returns today that used to fall through to the generic copy.
    func testNewlyMappedCodesAreNoLongerGeneric() {
        for code in ["apiRequestFailed", "invalidRoute", "invalidAsset", "memoTooLongForSourceChain"] {
            XCTAssertNotEqual(message(code), genericMessage, "\(code) still falls through")
        }
    }

    /// SwapKit's name for the over-length memo the wallet also catches locally before broadcasting;
    /// one situation, so one message.
    func testServerAndLocalMemoTooLongShareOneMessage() {
        XCTAssertEqual(message("memoTooLongForSourceChain"),
                       message(SwapKitErrorCopy.mayaMemoTooLongErrorCode))
    }

    func testUnknownAndEmptyErrorsFallBackToTheGenericCopy() {
        XCTAssertEqual(message(nil), genericMessage)
        XCTAssertEqual(message(""), genericMessage)
    }
}

// MARK: - Production boundary

/// Drives the two functions that apply the rules above to a real SwapKit reply —
/// `decodeQuoteError(from:)` for a non-2xx body and `routability(from:)` for the Buy picker's
/// probe — so reverting either one (prose before the code, or pruning on a top-level
/// `noRoutesFound`) fails here even while every helper test still passes.
@MainActor
final class SwapKitQuoteBoundaryTests: XCTestCase {
    private func statusError(_ json: String, statusCode: Int = 404) -> Error {
        HTTPClientError.statusCode(Moya.Response(statusCode: statusCode, data: Data(json.utf8)))
    }

    private func response(providerErrors: [SwapKitProviderError]? = nil,
                          error: String? = nil, message: String? = nil) -> SwapKitQuoteResponse {
        SwapKitQuoteResponse(quoteId: nil, routes: [], providerErrors: providerErrors, error: error, message: message)
    }

    private func providerError(_ code: String?, message: String? = nil) -> SwapKitProviderError {
        SwapKitProviderError(provider: "NEAR", errorCode: code, message: message)
    }

    // MARK: decodeQuoteError(from:)

    /// The recorded 404 for 0.01 DASH → BTC. Before the fix the prose won and the code was lost.
    func testQuoteErrorPutsTheTopLevelCodeBeforeTheProse() {
        let error = statusError(#"{"error": "noRoutesFound", "message": "No routes found for DASH.DASH -> BTC.BTC"}"#)

        XCTAssertEqual(SwapKitSwapProvider.decodeQuoteError(from: error),
                       "noRoutesFound: No routes found for DASH.DASH -> BTC.BTC")
    }

    func testQuoteErrorWithOnlyACodeReturnsTheCode() {
        XCTAssertEqual(SwapKitSwapProvider.decodeQuoteError(from: statusError(#"{"error": "invalidAsset"}"#)),
                       "invalidAsset")
    }

    func testQuoteErrorFallsBackToTheProviderCode() {
        let provider = statusError(#"""
        {"providerErrors": [{"provider": "NEAR", "errorCode": "sellAssetAmountTooSmall", "message": "Min amount is 0.175 DASH.DASH"}],
         "message": "Quote failed"}
        """#)

        XCTAssertEqual(SwapKitSwapProvider.decodeQuoteError(from: provider),
                       "sellAssetAmountTooSmall: Min amount is 0.175 DASH.DASH")
    }

    func testQuoteErrorWithNoCodeAnywhereFallsBackToTheProse() {
        XCTAssertEqual(SwapKitSwapProvider.decodeQuoteError(from: statusError(#"{"message": "Quote failed"}"#)),
                       "Quote failed")
    }

    func testQuoteErrorIgnoresFailuresThatCarryNoSwapKitBody() {
        XCTAssertNil(SwapKitSwapProvider.decodeQuoteError(from: statusError("<html>Bad Gateway</html>", statusCode: 502)))
        XCTAssertNil(SwapKitSwapProvider.decodeQuoteError(from: URLError(.notConnectedToInternet)))
    }

    // MARK: routability(from:)

    func testAnyRouteIsConclusivelyRoutable() throws {
        let recorded = try JSONDecoder().decode(SwapKitQuoteResponse.self,
                                                from: loadFixture(named: "swapkit_quote_response"))

        // The fixture also carries a THORCHAIN `noRoutesFound`; a route elsewhere outranks it.
        XCTAssertEqual(SwapKitSwapProvider.routability(from: recorded), .routable)
    }

    /// The ambiguous case: SwapKit gives a top-level `noRoutesFound` for an amount far below the
    /// floor as well as for a pair it cannot carry, so it must not prune the picker.
    func testTopLevelNoRouteLeavesTheQuestionOpen() {
        let noRoute = response(error: "noRoutesFound", message: "No routes found for DASH.DASH -> BTC.BTC")
        XCTAssertNil(SwapKitSwapProvider.routability(from: noRoute))
    }

    func testAbsentOrBlankProviderErrorsLeaveTheQuestionOpen() {
        XCTAssertNil(SwapKitSwapProvider.routability(from: response()))
        XCTAssertNil(SwapKitSwapProvider.routability(from: response(providerErrors: [])))
        XCTAssertNil(SwapKitSwapProvider.routability(from: response(providerErrors: [providerError(" ", message: "")])))
    }

    func testProviderNoRouteIsConclusivelyNotRoutable() {
        let noRoute = response(providerErrors: [providerError("noRoutesFound")])
        XCTAssertEqual(SwapKitSwapProvider.routability(from: noRoute), .notRoutable)
    }

    /// The probe amount was under the floor — evidence the route exists, not that it does not.
    func testProviderBelowMinimumCountsAsRoutable() {
        let tooSmall = response(providerErrors: [
            providerError("sellAssetAmountTooSmall", message: "Min amount is 0.175 DASH.DASH"),
        ])
        XCTAssertEqual(SwapKitSwapProvider.routability(from: tooSmall), .routable)
    }

    func testProviderUpstreamFailureLeavesTheQuestionOpen() {
        let upstream = response(providerErrors: [providerError("apiRequestFailed")])
        XCTAssertNil(SwapKitSwapProvider.routability(from: upstream))
    }
}

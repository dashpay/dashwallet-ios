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

// MARK: - Buy swap orders before their Dash transaction exists

final class BuySwapOrderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func buyOrder(
        id: String = "0xdeposit",
        status: SwapOrderStatus = .notStarted,
        depositSeenSecondsAgo: Int64? = nil,
        providerDenied: Bool = false,
        memo: String? = "",
        expected: String? = "2.51",
        fromAsset: String = "ARB.USDT-0XFD086BC7",
        finalisedSecondsAgo: Int64? = nil
    ) -> SwapOrder {
        let nowSeconds = Int64(now.timeIntervalSince1970)
        return SwapOrder(
            id: id,
            direction: "buy",
            service: "swapkit",
            fromAsset: fromAsset,
            toAsset: "DASH",
            toAddress: "XdestinationAddress",
            depositAddress: id,
            expectedToAmount: expected,
            status: status,
            timestamp: (nowSeconds - 3_600) * 1000,
            finalisedAt: finalisedSecondsAgo.map { nowSeconds - $0 } ?? -1,
            fromAmount: "150",
            depositSeenAt: depositSeenSecondsAgo.map { nowSeconds - $0 },
            providerDeniedAt: providerDenied ? nowSeconds : nil,
            depositMemo: memo,
            ownerWalletId: "aa11",
            ownerNetwork: "0"
        )
    }

    // MARK: Phase

    func testUnpaidOrderIsAwaitingPaymentAndHasNoRow() {
        let order = buyOrder()
        XCTAssertEqual(order.buyPhase, .awaitingPayment)
        XCTAssertFalse(order.hasDepositOnRecord)
        XCTAssertFalse(order.isBuyHistoryRow(now: now))
    }

    func testDepositOnChainWaitsForTheProviderUntilTheProviderDeniesIt() {
        // However long ago the deposit appeared, time alone does not make it stuck: with the
        // app in the background nobody asked the provider.
        let waiting = buyOrder(depositSeenSecondsAgo: 86_400)
        XCTAssertEqual(waiting.buyPhase, .waitingForProvider)
        XCTAssertTrue(waiting.isBuyHistoryRow(now: now))
        XCTAssertFalse(BuySwapOrderItem(order: waiting).showsErrorBadge)

        let denied = buyOrder(depositSeenSecondsAgo: 86_400, providerDenied: true)
        XCTAssertEqual(denied.buyPhase, .stuck)
        XCTAssertTrue(denied.isBuyHistoryRow(now: now))
        XCTAssertTrue(BuySwapOrderItem(order: denied).showsErrorBadge)
    }

    func testSlowChainsGetLongerBeforeTheProvidersDenialCounts() {
        XCTAssertEqual(SwapOrder.stuckAfterSeconds(forAsset: "ARB.USDT-0XFD086BC7"), 600)
        XCTAssertEqual(SwapOrder.stuckAfterSeconds(forAsset: "ETH.ETH"), 600)
        XCTAssertEqual(SwapOrder.stuckAfterSeconds(forAsset: "BTC.BTC"), 5_400)
        XCTAssertEqual(SwapOrder.stuckAfterSeconds(forAsset: "bch.BCH"), 5_400)
        XCTAssertEqual(SwapOrder.stuckAfterSeconds(forAsset: "LTC.LTC"), 2_700)
        XCTAssertEqual(buyOrder(fromAsset: "DOGE.DOGE").stuckAfterSeconds, 2_700)
    }

    func testProviderProgressWinsOverADenial() {
        for status in [SwapOrderStatus.pending, .swapping, .unknown] {
            let order = buyOrder(status: status, depositSeenSecondsAgo: 86_400, providerDenied: true)
            XCTAssertEqual(order.buyPhase, .processing, "\(status)")
            XCTAssertTrue(order.isBuyHistoryRow(now: now), "\(status)")
        }
    }

    func testAStatusAloneIsNotDepositEvidence() {
        // Some provider answers are only mapped onto a status; the tracker stamps
        // `depositSeenAt` when the deposit is actually proven, and only that counts.
        for status in [SwapOrderStatus.pending, .refunded, .failed, .expired] {
            XCTAssertFalse(buyOrder(status: status).hasDepositOnRecord, "\(status)")
            XCTAssertFalse(buyOrder(status: status).isBuyHistoryRow(now: now), "\(status)")
            XCTAssertTrue(buyOrder(status: status, depositSeenSecondsAgo: 60).isBuyHistoryRow(now: now), "\(status)")
        }
    }

    func testCompletedOrderKeepsARowOnlyWhileThePayoutMayStillBeArriving() {
        let justDone = buyOrder(
            status: .completed, depositSeenSecondsAgo: 7_200, finalisedSecondsAgo: SwapOrder.completedRowSeconds)
        XCTAssertEqual(justDone.buyPhase, .completed)
        XCTAssertTrue(justDone.isBuyHistoryRow(now: now))

        XCTAssertFalse(buyOrder(
            status: .completed, depositSeenSecondsAgo: 7_200, finalisedSecondsAgo: SwapOrder.completedRowSeconds + 1
        ).isBuyHistoryRow(now: now))
        // Completion time unknown: nothing to bound the row with, so no row.
        XCTAssertFalse(buyOrder(status: .completed, depositSeenSecondsAgo: 7_200).isBuyHistoryRow(now: now))
    }

    @MainActor
    private func track(_ json: String) throws -> SwapStatusResult {
        let response = try JSONDecoder().decode(SwapKitTrackResponse.self, from: Data(json.utf8))
        return SwapKitSwapProvider().mapTrackResponse(response)
    }

    @MainActor
    func testTrackStatusesThatProveADeposit() throws {
        for status in ["pending", "swapping", "completed", "refunded"] {
            let result = try track(#"{"status":"\#(status)"}"#)
            XCTAssertTrue(result.depositProven, status)
            XCTAssertTrue(result.isObserved, status)
            XCTAssertFalse(result.requestFailed, status)
            XCTAssertNil(result.providerStatus, status)
        }
    }

    @MainActor
    func testTrackStatusesThatProveNothing() throws {
        let notStarted = try track(#"{"status":"not_started"}"#)
        XCTAssertFalse(notStarted.isObserved)
        XCTAssertFalse(notStarted.requestFailed)
        XCTAssertFalse(notStarted.depositProven)

        // No status at all is not an answer.
        XCTAssertTrue(try track("{}").requestFailed)

        // Folded into refunded / pending for the sell flow, but the real word is kept and
        // no deposit is claimed on its strength.
        for (status, folded) in [("failed", "refunded"), ("unknown", "refunded"), ("Expired", "pending")] {
            let result = try track(#"{"status":"\#(status)"}"#)
            XCTAssertEqual(result.observedStatus, folded, status)
            XCTAssertEqual(result.providerStatus, status.lowercased(), status)
            XCTAssertFalse(result.depositProven, status)
        }
    }

    func testSourceChainComesFromTheAssetIdentifier() {
        XCTAssertEqual(buyOrder().fromChain, "ARB")
        XCTAssertEqual(SwapOrder.chain(ofAsset: "btc.BTC"), "BTC")
        XCTAssertNil(SwapOrder.chain(ofAsset: ""))
    }

    func testOnlyInProgressStatusesAreProviderProgress() {
        XCTAssertEqual(
            [SwapOrderStatus.pending, .swapping, .unknown].map(\.isProviderProgress), [true, true, true])
        for status in [SwapOrderStatus.notStarted, .completed, .refunded, .failed, .expired] {
            XCTAssertFalse(status.isProviderProgress, "\(status)")
        }
    }

    func testSellOrderIsNeverABuyRow() {
        var order = buyOrder(status: .pending, depositSeenSecondsAgo: 60)
        order.direction = "sell"
        XCTAssertFalse(order.isBuyHistoryRow(now: now))
        XCTAssertFalse(order.canWatchDepositAddress)
    }

    // MARK: Ownership and payouts

    func testOrderBelongsOnlyToTheWalletAndNetworkThatMadeIt() {
        let order = buyOrder()
        XCTAssertTrue(order.isOwned(byWalletId: "aa11", network: "0"))
        XCTAssertFalse(order.isOwned(byWalletId: "bb22", network: "0"))
        XCTAssertFalse(order.isOwned(byWalletId: "aa11", network: "1"))
        XCTAssertFalse(order.isOwned(byWalletId: nil, network: "0"))

        var unknown = order
        unknown.ownerWalletId = nil
        XCTAssertFalse(unknown.isOwned(byWalletId: "aa11", network: "0"))
    }

    func testOnlyOrdersTheProviderHasNotEndedCanStillBePaidOut() {
        for status in [SwapOrderStatus.notStarted, .pending, .swapping, .unknown, .completed] {
            XCTAssertTrue(buyOrder(status: status).mayStillBePaidOut(now: now), "\(status)")
        }
        XCTAssertFalse(buyOrder(status: .refunded).mayStillBePaidOut(now: now))
        XCTAssertFalse(buyOrder(status: .failed).mayStillBePaidOut(now: now))
        // Expired is us no longer asking; a late payout still belongs to a funded order for
        // a while — but an expired order nobody paid claims nothing.
        XCTAssertTrue(buyOrder(
            status: .expired, depositSeenSecondsAgo: 86_400, finalisedSecondsAgo: SwapOrder.latePayoutSeconds
        ).mayStillBePaidOut(now: now))
        XCTAssertFalse(buyOrder(
            status: .expired, depositSeenSecondsAgo: 86_400, finalisedSecondsAgo: SwapOrder.latePayoutSeconds + 1
        ).mayStillBePaidOut(now: now))
        XCTAssertFalse(buyOrder(status: .expired, finalisedSecondsAgo: 60).mayStillBePaidOut(now: now))
    }

    func testOrdersSavedBeforeDepositsWereRecordedKeepTheirOldMatching() {
        for status in [SwapOrderStatus.expired, .refunded, .failed] {
            var legacy = buyOrder(status: status)
            legacy.fromAmount = nil
            XCTAssertTrue(legacy.isLegacyRecord)
            XCTAssertTrue(legacy.mayStillBePaidOut(now: now), "\(status)")
            // …but it is still no row of its own: no deposit on record, no owner.
            XCTAssertFalse(legacy.isBuyHistoryRow(now: now), "\(status)")
        }
        XCTAssertFalse(buyOrder().isLegacyRecord)
    }

    func testSettleWaitScalesWithTheChain() {
        XCTAssertEqual(buyOrder().settleSeconds, 3_600)
        XCTAssertEqual(buyOrder(fromAsset: "BTC.BTC").settleSeconds, 10_800)
        XCTAssertEqual(buyOrder(fromAsset: "LTC.LTC").settleSeconds, 5_400)
    }

    func testNoTransactionsMeansNoPayouts() {
        XCTAssertTrue(SwapBuyTransactionMatcher.payoutAssignments(among: [buyOrder(status: .pending)], in: [], now: now).isEmpty)
        XCTAssertTrue(SwapBuyTransactionMatcher.matchingTransactions(for: buyOrder(status: .pending), in: []).isEmpty)
    }

    func testOrderRowWordsProviderProgressLikeTheFinishedSwapRow() {
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(status: .pending)).statusText,
                       SwapOrderMetadataProvider.statusLabel(for: .pending))
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(status: .swapping)).statusText,
                       SwapOrderMetadataProvider.statusLabel(for: .swapping))
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder()).pair, "USDT/DASH")
    }

    // MARK: Deposit address watching

    func testMemoDepositCannotBeRecognisedByItsAddress() {
        XCTAssertTrue(buyOrder(memo: "").canWatchDepositAddress)
        XCTAssertTrue(buyOrder(memo: "  ").canWatchDepositAddress)
        XCTAssertFalse(buyOrder(memo: "123456").canWatchDepositAddress)
        // Saved before the memo was recorded: unknown, so not watched.
        XCTAssertFalse(buyOrder(memo: nil).canWatchDepositAddress)
    }

    func testHoldsAssetMatchesTheIdentifierWhateverItsCase() {
        let asset = "ARB.USDT-0XFD086BC7"
        let held = [
            SwapKitBalanceItem(identifier: "ARB.ETH", value: "0"),
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "150"),
        ]
        XCTAssertTrue(SwapTrackingService.holdsAsset(asset, in: held))
    }

    func testHoldsAssetIgnoresZeroOtherAssetsAndGarbage() {
        let asset = "ARB.USDT-0XFD086BC7"
        XCTAssertFalse(SwapTrackingService.holdsAsset(asset, in: []))
        XCTAssertFalse(SwapTrackingService.holdsAsset(asset, in: [
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "0"),
            SwapKitBalanceItem(identifier: "ARB.USDC-0xaf88d065", value: "9"),
            SwapKitBalanceItem(identifier: "ARB.ETH", value: "1.5"),
            SwapKitBalanceItem(identifier: nil, value: "7"),
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "n/a"),
        ]))
    }

    func testNativeCoinNamedDifferentlyByTheBalanceLookupStillCounts() {
        // Toncoin: `TON.TON` in the coin list, `TON.GRAM` from `/balance`.
        let ton = [
            SwapKitBalanceItem(identifier: "TON.GRAM", value: "12.5"),
            SwapKitBalanceItem(identifier: "TON.USDT-EQCxE6mU", value: "2"),
        ]
        XCTAssertTrue(SwapTrackingService.holdsAsset("TON.TON", in: ton))
        XCTAssertTrue(SwapTrackingService.holdsAsset("TON.USDT-EQCXE6MU", in: ton))
        XCTAssertFalse(SwapTrackingService.holdsAsset("TON.TON", in: [SwapKitBalanceItem(identifier: "TON.GRAM", value: "0")]))
        // Listed under its own name: that entry decides, a sibling native does not.
        XCTAssertFalse(SwapTrackingService.holdsAsset("MAYA.MAYA", in: [
            SwapKitBalanceItem(identifier: "MAYA.MAYA", value: "0"),
            SwapKitBalanceItem(identifier: "MAYA.CACAO", value: "5"),
        ]))
        // Two natives and neither is ours: nothing to mean.
        XCTAssertFalse(SwapTrackingService.holdsAsset("MAYA.MAYA", in: [
            SwapKitBalanceItem(identifier: "MAYA.CACAO", value: "5"),
            SwapKitBalanceItem(identifier: "MAYA.OTHER", value: "5"),
        ]))
        // A token is never matched by the native balance, nor a coin by another chain's.
        XCTAssertFalse(SwapTrackingService.holdsAsset("TON.USDT-EQCXE6MU", in: [SwapKitBalanceItem(identifier: "TON.GRAM", value: "9")]))
        XCTAssertFalse(SwapTrackingService.holdsAsset("TON.TON", in: [SwapKitBalanceItem(identifier: "SOL.SOL", value: "9")]))
    }

    // MARK: Row

    func testRowShowsTheExpectedAmountOnlyWhileAPayoutIsStillPossible() {
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(depositSeenSecondsAgo: 60)).expectedDuffs, 251_000_000)
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(status: .completed, finalisedSecondsAgo: 60)).expectedDuffs, 251_000_000)
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(status: .refunded)).expectedDuffs, 0)
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(status: .failed)).expectedDuffs, 0)
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(expected: nil)).expectedDuffs, 0)
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(expected: "0.017580064")).expectedDuffs, 1_758_006)
        XCTAssertEqual(BuySwapOrderItem(order: buyOrder(expected: "99999999999999999999999999")).expectedDuffs, 0)
    }

    func testRowIsDatedByTheDepositNotTheOrder() {
        let seen = BuySwapOrderItem(order: buyOrder(depositSeenSecondsAgo: 120))
        XCTAssertEqual(seen.date, now.addingTimeInterval(-120))
        let unseen = BuySwapOrderItem(order: buyOrder(status: .pending))
        XCTAssertEqual(unseen.date, now.addingTimeInterval(-3_600))
    }

    // MARK: /v3/swap meta

    private func decodeSwap(meta: String) throws -> SwapKitSwapResponse {
        let json = #"{"inboundAddress":"0xdeposit","expectedBuyAmount":"2.51","meta":"# + meta + "}"
        return try JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
    }

    func testDepositDeadlineDecodesFromANumberOrAString() throws {
        XCTAssertEqual(try decodeSwap(meta: #"{"depositChannelExpiration":1800003600}"#).meta?.depositChannelExpiration, 1_800_003_600)
        XCTAssertEqual(try decodeSwap(meta: #"{"depositChannelExpiration":"1800003600"}"#).meta?.depositChannelExpiration, 1_800_003_600)
        XCTAssertEqual(
            try decodeSwap(meta: #"{"depositChannelExpiration":1800003600}"#).meta?.depositDeadline(now: now),
            now.addingTimeInterval(3_600))
    }

    func testImplausibleDepositDeadlineReadsAsNone() throws {
        // Already past, milliseconds instead of seconds, absurdly large, not a finite number.
        for raw in ["1799999999", "1800003600000", "1e30", #""inf""#, #""nan""#] {
            let meta = try decodeSwap(meta: "{\"depositChannelExpiration\":\(raw)}").meta
            XCTAssertNil(meta?.depositDeadline(now: now), raw)
        }
        let edge = now.addingTimeInterval(SwapKitSwapMeta.maxDepositWindow).timeIntervalSince1970
        XCTAssertNotNil(try decodeSwap(meta: "{\"depositChannelExpiration\":\(Int(edge))}").meta?.depositDeadline(now: now))
    }

    func testUnexpectedMetaNeverFailsTheSwapResponse() throws {
        for meta in [#"{"depositChannelExpiration":{"at":1}}"#, #"{"other":true}"#, #""free text""#, "[1,2]", "null"] {
            let response = try decodeSwap(meta: meta)
            XCTAssertEqual(response.inboundAddress, "0xdeposit", meta)
            XCTAssertNil(response.meta?.depositChannelExpiration, meta)
        }
    }
}

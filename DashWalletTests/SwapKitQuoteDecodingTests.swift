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
import Combine
import Moya
import SwiftDashSDK
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

/// A wallet transaction as the payout matcher reads it.
private struct PayoutFixture: SwapPayoutCandidate {
    let txHashHexString: String
    let date: Date
    let firstStored: Date?
    let direction: TransactionDirection
    let outputReceiveAddresses: [String]
    let dashAmount: UInt64
}

/// A read of the orders table that fails the first `failures` times it is made.
private final class FlakyOrdersRead: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: Int
    private var made = 0
    private let orders: [SwapOrder]

    /// How many reads were made, failed ones included.
    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return made
    }

    init(failures: Int, orders: [SwapOrder]) {
        self.failures = failures
        self.orders = orders
    }

    func read() throws -> [SwapOrder] {
        lock.lock()
        defer { lock.unlock() }
        made += 1
        guard failures == 0 else {
            failures -= 1
            throw CocoaError(.fileReadUnknown)
        }
        return orders
    }
}

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
        finalisedSecondsAgo: Int64? = nil,
        createdSecondsAgo: Int64 = 3_600,
        payoutHash: String? = nil
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
            outboundTxHash: payoutHash,
            timestamp: (nowSeconds - createdSecondsAgo) * 1000,
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
        XCTAssertFalse(order.isBuyHistoryRow(walletPayout: .notFound, now: now))
    }

    func testDepositOnChainWaitsForTheProviderUntilTheProviderDeniesIt() {
        // However long ago the deposit appeared, time alone does not make it stuck: with the
        // app in the background nobody asked the provider.
        let waiting = buyOrder(depositSeenSecondsAgo: 86_400)
        XCTAssertEqual(waiting.buyPhase, .waitingForProvider)
        XCTAssertTrue(waiting.isBuyHistoryRow(walletPayout: .notFound, now: now))
        XCTAssertFalse(BuySwapOrderItem(order: waiting).showsErrorBadge)

        let denied = buyOrder(depositSeenSecondsAgo: 86_400, providerDenied: true)
        XCTAssertEqual(denied.buyPhase, .stuck)
        XCTAssertTrue(denied.isBuyHistoryRow(walletPayout: .notFound, now: now))
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
            XCTAssertTrue(order.isBuyHistoryRow(walletPayout: .notFound, now: now), "\(status)")
        }
    }

    func testAStatusAloneIsNotDepositEvidence() {
        // Some provider answers are only mapped onto a status; the tracker stamps
        // `depositSeenAt` when the deposit is actually proven, and only that counts.
        for status in [SwapOrderStatus.pending, .refunded, .failed, .expired] {
            XCTAssertFalse(buyOrder(status: status).hasDepositOnRecord, "\(status)")
            XCTAssertFalse(buyOrder(status: status).isBuyHistoryRow(walletPayout: .notFound, now: now), "\(status)")
            XCTAssertTrue(buyOrder(status: status, depositSeenSecondsAgo: 60).isBuyHistoryRow(walletPayout: .notFound, now: now), "\(status)")
        }
    }

    func testCompletedOrderKeepsItsRowUntilTheWalletShowsThePayout() {
        // The provider completed it a day ago, with the wallet inactive or still syncing.
        let done = buyOrder(status: .completed, depositSeenSecondsAgo: 2 * 86_400, finalisedSecondsAgo: 86_400)
        XCTAssertEqual(done.buyPhase, .completed)
        // The wallet was read and has no payout: the row stays, however long ago that was.
        XCTAssertTrue(done.isBuyHistoryRow(walletPayout: .notFound, now: now))
        // The payout is there: that transaction is the row.
        XCTAssertFalse(done.isBuyHistoryRow(walletPayout: .inWallet, now: now))
        // …or what may be the payout is there, unsettled between orders.
        XCTAssertFalse(done.isBuyHistoryRow(walletPayout: .unsettled, now: now))
        // An order still in progress keeps its row through that.
        let live = buyOrder(status: .swapping, depositSeenSecondsAgo: 600)
        XCTAssertTrue(live.isBuyHistoryRow(walletPayout: .unsettled, now: now))
        XCTAssertTrue(live.isBuyHistoryRow(walletPayout: .unknown, now: now))
        XCTAssertFalse(live.isBuyHistoryRow(walletPayout: .inWallet, now: now))

        // The wallet not read yet: shown only right after completion.
        XCTAssertFalse(done.isBuyHistoryRow(walletPayout: .unknown, now: now))
        let justDone = buyOrder(
            status: .completed, depositSeenSecondsAgo: 7_200, finalisedSecondsAgo: SwapOrder.completedRowSeconds)
        XCTAssertTrue(justDone.isBuyHistoryRow(walletPayout: .unknown, now: now))
        // An unpaid order is no row whatever the wallet says.
        XCTAssertFalse(buyOrder(status: .completed).isBuyHistoryRow(walletPayout: .notFound, now: now))
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
    func testACompletedSwapIntoDashNamesItsDashPayout() throws {
        // The shape `/track` answers with for a finished ETH → DASH swap: the source-chain
        // leg, the router's leg, and the payout sent on the Dash chain.
        let buy = try track(#"""
        {"status":"completed","chainId":"1","hash":"0xsource","fromAsset":"ETH.ETH","toAsset":"DASH.DASH","legs":[
          {"status":"completed","chainId":"1","hash":"0xsource","fromAsset":"ETH.ETH","toAsset":"ETH.ETH"},
          {"status":"completed","chainId":"mayachain-mainnet-v1","hash":"source","fromAsset":"ETH.ETH","toAsset":"DASH.DASH"},
          {"status":"completed","chainId":"dash","hash":"dashpayout","fromAsset":"DASH.DASH","toAsset":"DASH.DASH"}]}
        """#)
        XCTAssertEqual(buy.dashPayoutHash, "dashpayout")
        // Without a Dash leg no payout is named: the deposit's hash is not one.
        let unnamed = try track(#"""
        {"status":"completed","chainId":"1","hash":"0xsource","fromAsset":"ETH.ETH","toAsset":"DASH.DASH","legs":[
          {"status":"completed","chainId":"1","hash":"0xsource","fromAsset":"ETH.ETH","toAsset":"ETH.ETH"}]}
        """#)
        XCTAssertNil(unnamed.dashPayoutHash)
        // Nor when the answer does not say where the swap ends.
        let unknown = try track(#"""
        {"status":"completed","chainId":"1","hash":"0xsource","legs":[
          {"status":"completed","chainId":"dash","hash":"dashleg"}]}
        """#)
        XCTAssertNil(unknown.dashPayoutHash)
        // A swap out of DASH still names the destination chain's leg, not the Dash deposit.
        let sell = try track(#"""
        {"status":"completed","chainId":"dash","hash":"dashdeposit","fromAsset":"DASH.DASH","toAsset":"ETH.ETH","legs":[
          {"status":"completed","chainId":"dash","hash":"dashdeposit","fromAsset":"DASH.DASH","toAsset":"DASH.DASH"},
          {"status":"completed","chainId":"1","hash":"0xpayout","fromAsset":"DASH.DASH","toAsset":"ETH.ETH"}]}
        """#)
        XCTAssertEqual(sell.outHashes, ["0xpayout"])
        XCTAssertNil(sell.dashPayoutHash)
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
        XCTAssertFalse(order.isBuyHistoryRow(walletPayout: .notFound, now: now))
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
            XCTAssertTrue(buyOrder(status: status).mayStillBePaidOut, "\(status)")
        }
        XCTAssertFalse(buyOrder(status: .refunded).mayStillBePaidOut)
        XCTAssertFalse(buyOrder(status: .failed).mayStillBePaidOut)
        // Expired is us no longer asking; a late payout still belongs to a funded order,
        // however long ago it expired. One nobody paid keeps a claim to what was there as
        // it was let go (`latestPayoutDate`), however much later the wallet is looked at.
        XCTAssertTrue(buyOrder(
            status: .expired, depositSeenSecondsAgo: 86_400, finalisedSecondsAgo: 10 * SwapOrder.latePayoutSeconds
        ).mayStillBePaidOut)
        XCTAssertTrue(buyOrder(status: .expired, finalisedSecondsAgo: 60).mayStillBePaidOut)
        XCTAssertTrue(buyOrder(status: .expired, finalisedSecondsAgo: 365 * 86_400).mayStillBePaidOut)
    }

    func testAnOrderLetGoBesideItsPayoutStillTakesIt() {
        // Let go unpaid five hours ago — and its payout had been written a moment before,
        // unread. The order takes it and is completed after all, also once the payout is
        // mined and carries its block's time, a little after the order was let go.
        let letGo = buyOrder(
            id: "0xa", status: .expired, finalisedSecondsAgo: 5 * 3_600, createdSecondsAgo: 6 * 86_400)
        XCTAssertEqual(assignments([letGo], [payout("aa", secondsAgo: 5 * 3_600 + 60)]), ["0xa": "aa"])
        XCTAssertEqual(assignments([letGo], [payout("aa", secondsAgo: 5 * 3_600 - 600)]), ["0xa": "aa"])
        // A receive that came hours after it was let go is not its payout.
        XCTAssertEqual(assignments([letGo], [payout("bb", secondsAgo: 3_600)]), [:])
        // It only takes what the others left: a live order for the same amount comes first,
        // and is not held up by it.
        let live = buyOrder(id: "0xb", createdSecondsAgo: 5 * 86_400)
        let resolution = SwapBuyTransactionMatcher.payoutResolution(
            among: [letGo, live], in: [payout("aa", secondsAgo: 5 * 3_600 + 60)])
        XCTAssertEqual(resolution.assigned.mapValues(\.txHashHexString), ["0xb": "aa"])
        XCTAssertTrue(resolution.contested.isEmpty)
    }

    func testCompletedOrdersThatNameNoPayoutAreAsked() {
        let named = buyOrder(
            id: "0xa", status: .completed, finalisedSecondsAgo: 3_600, payoutHash: String(repeating: "a", count: 64))
        let unnamed = buyOrder(id: "0xb", status: .completed, finalisedSecondsAgo: 3_600)
        let sourceHash = buyOrder(id: "0xc", status: .completed, finalisedSecondsAgo: 3_600, payoutHash: "0xsource")
        var legacy = buyOrder(
            id: "0xd", status: .completed, finalisedSecondsAgo: 3_600, payoutHash: String(repeating: "b", count: 64))
        legacy.fromAmount = nil
        let live = buyOrder(id: "0xe", status: .pending)
        // Just completed: the provider may still add the Dash leg to its answer.
        let fresh = buyOrder(id: "0xf", status: .completed, finalisedSecondsAgo: 60)
        func ids(waiting asked: [SwapOrder]) -> [String] {
            SwapTrackingService.ordersToAskForPayoutIdentity(
                among: [named, unnamed, sourceHash, legacy, live, fresh],
                notBefore: Dictionary(
                    uniqueKeysWithValues: asked.map { (SwapTrackingService.payoutIdentityKey(for: $0), Int64.max) }),
                nowSeconds: Int64(now.timeIntervalSince1970)).map(\.id)
        }
        // Not the one that names its payout, nor one still in flight. A record saved before
        // this version is asked whatever its hash looks like: it may be the deposit's.
        XCTAssertEqual(ids(waiting: []), ["0xb", "0xc", "0xd"])
        XCTAssertEqual(ids(waiting: [unnamed, legacy]), ["0xc"])
        // A later order on the same deposit address is another order.
        var earlier = unnamed
        earlier.timestamp -= 86_400_000
        XCTAssertEqual(ids(waiting: [earlier, legacy]), ["0xb", "0xc"])
        // The provider's hash is taken only in the shape of a Dash transaction id.
        XCTAssertEqual(SwapOrder.dashTxId(from: " " + String(repeating: "A", count: 64)), String(repeating: "a", count: 64))
        XCTAssertNil(SwapOrder.dashTxId(from: "0x" + String(repeating: "a", count: 64)))
        XCTAssertNil(SwapOrder.dashTxId(from: "  "))
    }

    func testANamedPayoutIsNotBoundedByItsDate() {
        // Completed four hours ago. Its payout sat unmined for three and now carries a
        // block time past the order's bound: unnamed, the order would lose it there.
        let order = buyOrder(
            id: "0xa", status: .completed, depositSeenSecondsAgo: 7_200, finalisedSecondsAgo: 4 * 3_600,
            createdSecondsAgo: 86_400)
        XCTAssertEqual(assignments([order], [payout("aa", secondsAgo: 4 * 3_600)]), ["0xa": "aa"])
        XCTAssertEqual(assignments([order], [payout("aa", secondsAgo: 3_600)]), [:])
        // The tracker writes the hash into the order while the first holds, and then it
        // stays matched.
        var named = order
        named.outboundTxHash = "AA"
        XCTAssertEqual(assignments([named], [payout("aa", secondsAgo: 3_600)]), ["0xa": "aa"])
        // Only a match nothing can change is written down: with a live order beside it
        // that fits the same transaction, the completed one has it for now, unnamed.
        let live = buyOrder(id: "0xb", createdSecondsAgo: 12 * 3_600)
        let early = [payout("aa", secondsAgo: 4 * 3_600)]
        XCTAssertEqual(
            SwapBuyTransactionMatcher.payoutResolution(among: [order], in: early).unshared, ["0xa"])
        let shared = SwapBuyTransactionMatcher.payoutResolution(among: [order, live], in: early)
        XCTAssertEqual(shared.assigned.mapValues(\.txHashHexString), ["0xa": "aa"])
        XCTAssertTrue(shared.unshared.isEmpty)
    }

    func testATransactionSeenInTimeStaysTheOrdersAfterItsDateMoves() {
        // Completed four hours ago, with a live order beside it that fits the same
        // transaction: the completed one has it, but not by name.
        let order = buyOrder(
            id: "0xa", status: .completed, depositSeenSecondsAgo: 7_200, finalisedSecondsAgo: 4 * 3_600,
            createdSecondsAgo: 86_400)
        let live = buyOrder(id: "0xb", createdSecondsAgo: 12 * 3_600)
        let early = SwapBuyTransactionMatcher.payoutResolution(
            among: [order, live], in: [payout("aa", secondsAgo: 4 * 3_600)])
        XCTAssertEqual(early.assigned.mapValues(\.txHashHexString), ["0xa": "aa"])
        // What the tracker keeps with the order: only for the one with a date bound.
        XCTAssertEqual(early.datedInTime, ["0xa": ["aa"]])
        // Mined three hours later, the transaction is dated past the bound. Not kept, it
        // would go to the live order…
        let mined = [payout("aa", secondsAgo: 3_600)]
        XCTAssertEqual(assignments([order, live], mined), ["0xb": "aa"])
        // …kept, it is still the completed order's, and nothing new is reported to keep.
        var remembering = order
        remembering.payoutCandidates = remembering.payoutCandidates(adding: ["aa"])
        let late = SwapBuyTransactionMatcher.payoutResolution(among: [remembering, live], in: mined)
        XCTAssertEqual(late.assigned.mapValues(\.txHashHexString), ["0xa": "aa"])
        XCTAssertTrue(late.datedInTime.isEmpty)
        // Another transaction dated past the bound is not the order's for that.
        XCTAssertEqual(assignments([remembering], [payout("bb", secondsAgo: 3_600)]), [:])

        // Nothing is written when there is nothing to add, and the list does not grow
        // without end.
        XCTAssertNil(remembering.payoutCandidates(adding: ["aa"]))
        XCTAssertEqual(remembering.payoutCandidates(adding: ["cc", "aa", "bb"]), "aa cc bb")
        // A transaction another order has by name is not kept as this one's to take.
        let namedHash = String(repeating: "c", count: 64)
        let naming = buyOrder(
            id: "0xc", status: .completed, finalisedSecondsAgo: 4 * 3_600, createdSecondsAgo: 86_400,
            payoutHash: namedHash)
        let both = SwapBuyTransactionMatcher.payoutResolution(
            among: [order, naming],
            in: [payout(namedHash, secondsAgo: 4 * 3_600 + 60), payout("aa", secondsAgo: 4 * 3_600)])
        XCTAssertEqual(both.datedInTime, ["0xa": ["aa"]])
        var full = order
        full.payoutCandidates = (0..<SwapOrder.maximumPayoutCandidates).map { "t\($0)" }.joined(separator: " ")
        XCTAssertNil(full.payoutCandidates(adding: ["zz"]))
    }

    func testAnOlderRecordNamedByTheProviderTakesNoOtherTransaction() {
        // Saved before this version; the provider has since named its payout, which this
        // wallet read does not show. The one transaction there is the live order's.
        var repaired = buyOrder(
            id: "0xa", status: .completed, finalisedSecondsAgo: 3_600, createdSecondsAgo: 7_200,
            payoutHash: String(repeating: "a", count: 64))
        repaired.fromAmount = nil
        let live = buyOrder(id: "0xb", createdSecondsAgo: 5_400)
        let other = [payout("bb", secondsAgo: 3_000)]
        // With nothing but the hash, an older record's names nothing for sure: it may be
        // the deposit's, and the order is matched by date.
        XCTAssertFalse(repaired.namesItsPayout)
        XCTAssertEqual(assignments([repaired, live], other), ["0xa": "bb"])
        // When the wallet shows the transaction the hash names, the order has it by name,
        // and the tracker is told so.
        let own = SwapBuyTransactionMatcher.payoutResolution(
            among: [repaired, live], in: [payout(String(repeating: "a", count: 64), secondsAgo: 3_000)])
        XCTAssertEqual(own.assigned.keys.sorted(), ["0xa"])
        XCTAssertEqual(own.takenByName, ["0xa"])
        // Not when another order records the same hash: whose it is, is not settled by that.
        var twin = repaired
        twin.id = "0xc"
        XCTAssertTrue(SwapBuyTransactionMatcher.payoutResolution(
            among: [repaired, twin], in: [payout(String(repeating: "a", count: 64), secondsAgo: 3_000)])
            .takenByName.isEmpty)
        // And the one for which the hash is established has the transaction, though the
        // other was made first.
        twin.payoutNamedAt = Int64(now.timeIntervalSince1970)
        twin.timestamp += 60_000
        XCTAssertEqual(
            assignments([repaired, twin], [payout(String(repeating: "a", count: 64), secondsAgo: 3_000)]),
            ["0xc": String(repeating: "a", count: 64)])
        repaired.payoutNamedAt = Int64(now.timeIntervalSince1970)
        XCTAssertTrue(repaired.namesItsPayout)
        XCTAssertEqual(assignments([repaired, live], other), ["0xb": "bb"])
        XCTAssertEqual(
            SwapTrackingService.ordersToAskForPayoutIdentity(
                among: [repaired], notBefore: [:], nowSeconds: Int64(now.timeIntervalSince1970)).map(\.id),
            [])
    }

    func testAnOldOrderIsAskedAgainAfterAnAnswerWithoutADashLeg() {
        // Saved before this version and completed a month ago, with a hash from the
        // deposit's chain; the provider's first answer names no Dash payout.
        let nowSeconds = Int64(now.timeIntervalSince1970)
        var legacy = buyOrder(
            id: "0xa", status: .completed, finalisedSecondsAgo: 30 * 86_400, createdSecondsAgo: 31 * 86_400,
            payoutHash: "0xsource")
        legacy.fromAmount = nil
        let key = SwapTrackingService.payoutIdentityKey(for: legacy)
        func isAsked(_ order: SwapOrder, secondsLater: Int64, notBefore: [String: Int64]) -> Bool {
            !SwapTrackingService.ordersToAskForPayoutIdentity(
                among: [order], notBefore: notBefore, nowSeconds: nowSeconds + secondsLater).isEmpty
        }
        XCTAssertTrue(isAsked(legacy, secondsLater: 0, notBefore: [:]))
        // That answer is not the last word, however old the order: it is left alone for a
        // while and then asked again…
        let firstWait = SwapTrackingService.payoutIdentityRetryDelay(timesAsked: 1)
        let afterFirst = [key: nowSeconds + firstWait]
        XCTAssertFalse(isAsked(legacy, secondsLater: firstWait - 1, notBefore: afterFirst))
        XCTAssertTrue(isAsked(legacy, secondsLater: firstWait, notBefore: afterFirst))
        // …and once the provider names the payout, the order has it by name and is done.
        legacy.outboundTxHash = String(repeating: "a", count: 64)
        legacy.payoutNamedAt = nowSeconds + firstWait
        XCTAssertTrue(legacy.namesItsPayout)
        XCTAssertFalse(isAsked(legacy, secondsLater: firstWait, notBefore: afterFirst))

        // Ever more rarely, and never given up.
        XCTAssertEqual(firstWait, 600)
        XCTAssertEqual(SwapTrackingService.payoutIdentityRetryDelay(timesAsked: 2), 1_200)
        XCTAssertEqual(SwapTrackingService.payoutIdentityRetryDelay(timesAsked: 7), 64 * 600)
        XCTAssertEqual(SwapTrackingService.payoutIdentityRetryDelay(timesAsked: 14), 30 * 86_400)
        XCTAssertEqual(SwapTrackingService.payoutIdentityRetryDelay(timesAsked: 1_000), 30 * 86_400)
        XCTAssertEqual(SwapTrackingService.payoutIdentityRetryDelay(timesAsked: 0), 600)

        // The record kept between launches: each answer counts, and sets the next try's time.
        let first = SwapTrackingService.payoutIdentityAsk(after: nil, answered: true, nowSeconds: nowSeconds)
        XCTAssertEqual(first, [1, Int(nowSeconds + 600)])
        let second = SwapTrackingService.payoutIdentityAsk(after: first, answered: true, nowSeconds: nowSeconds + 600)
        XCTAssertEqual(second, [2, Int(nowSeconds + 600 + 1_200)])
        XCTAssertEqual(SwapTrackingService.payoutIdentityNotBefore(of: second, nowSeconds: nowSeconds), nowSeconds + 1_800)
        // A request the provider did not answer is tried again after the wait so far,
        // without making it longer.
        XCTAssertEqual(
            SwapTrackingService.payoutIdentityAsk(after: second, answered: false, nowSeconds: nowSeconds),
            [2, Int(nowSeconds + 1_200)])
        XCTAssertEqual(
            SwapTrackingService.payoutIdentityAsk(after: nil, answered: false, nowSeconds: nowSeconds),
            [0, Int(nowSeconds + 600)])
        // A time set while the clock ran a year ahead does not silence the order: it is due.
        let aYearAhead = [key: SwapTrackingService.payoutIdentityNotBefore(
            of: [3, Int(nowSeconds + 365 * 86_400)], nowSeconds: nowSeconds)]
        var unnamedLegacy = legacy
        unnamedLegacy.outboundTxHash = "0xsource"
        unnamedLegacy.payoutNamedAt = nil
        XCTAssertTrue(isAsked(unnamedLegacy, secondsLater: 0, notBefore: aYearAhead))
        // A record of another shape is no record: due, and counted from the start.
        XCTAssertEqual(SwapTrackingService.payoutIdentityNotBefore(of: [7], nowSeconds: nowSeconds), 0)
        XCTAssertEqual(
            SwapTrackingService.payoutIdentityAsk(after: [7], answered: true, nowSeconds: nowSeconds),
            [1, Int(nowSeconds + 600)])

        // Those never asked come before the ones whose next try is due.
        let neverAsked = buyOrder(id: "0xz", status: .completed, finalisedSecondsAgo: 86_400)
        XCTAssertEqual(
            SwapTrackingService.ordersToAskForPayoutIdentity(
                among: [unnamedLegacy, neverAsked], notBefore: [key: nowSeconds - 60], nowSeconds: nowSeconds)
                .map(\.id),
            ["0xz", "0xa"])
    }

    func testAPayoutWrittenAsTheOrderWasLetGoIsItsOwnAfterItIsMined() {
        // Let go unpaid a day ago. Its payout was written to the wallet in that moment,
        // unread, and nothing was kept of it with the order; by the next look it is mined
        // and carries its block's time, three hours after the order was let go.
        let letGo = buyOrder(
            id: "0xa", status: .expired, finalisedSecondsAgo: 86_400, createdSecondsAgo: 4 * 86_400)
        XCTAssertNil(letGo.payoutCandidates)
        let mined = payout("aa", secondsAgo: 86_400 - 3 * 3_600, storedSecondsAgo: 86_400 - 30)
        XCTAssertEqual(assignments([letGo], [mined]), ["0xa": "aa"])
        // And it is kept with the order from that reading on.
        XCTAssertEqual(
            SwapBuyTransactionMatcher.payoutResolution(among: [letGo], in: [mined]).datedInTime, ["0xa": ["aa"]])
        // A receive the wallet first held hours after the order was let go is not its
        // payout, whenever it was mined…
        XCTAssertEqual(
            assignments([letGo], [payout("bb", secondsAgo: 86_400 - 3 * 3_600, storedSecondsAgo: 86_400 - 3 * 3_600)]),
            [:])
        // …and one mined in time is, though the store holds it only since a rescan.
        XCTAssertEqual(
            assignments([letGo], [payout("cc", secondsAgo: 86_400 + 60, storedSecondsAgo: 600)]), ["0xa": "cc"])
        // The same for a completed order whose payout was mined past its bound.
        let completed = buyOrder(
            id: "0xb", status: .completed, finalisedSecondsAgo: 86_400, createdSecondsAgo: 2 * 86_400)
        XCTAssertEqual(assignments([completed], [mined]), ["0xb": "aa"])
        // It still only takes what the others left: a live order for the same amount
        // comes first.
        let live = buyOrder(id: "0xc", createdSecondsAgo: 3 * 86_400)
        XCTAssertEqual(assignments([letGo, live], [mined]), ["0xc": "aa"])
        // Of two it fits, the completed order takes the one that reached the wallet
        // first, not the one mined first.
        let minedFirst = payout("dd", secondsAgo: 86_400 - 3_600)
        XCTAssertEqual(assignments([completed], [minedFirst, mined]), ["0xb": "aa"])
        // A time the store gives from before the order was made is not believed: the
        // date decides. A receive held since then and mined after the order was let go
        // is not its payout…
        let early = payout("ee", secondsAgo: 86_400 - 3 * 3_600, storedSecondsAgo: 4 * 86_400 + 60)
        XCTAssertEqual(assignments([letGo], [early]), [:])
        // …and a payout mined in time is, whatever the device's clock said as it was stored.
        XCTAssertEqual(
            assignments([letGo], [payout("ff", secondsAgo: 86_400 + 60, storedSecondsAgo: 4 * 86_400 + 60)]),
            ["0xa": "ff"])
        // The store's time counts to the second, as the date does: on the bound is in time.
        let onTheBound = PayoutFixture(
            txHashHexString: "ab",
            date: now.addingTimeInterval(-TimeInterval(86_400 - 3 * 3_600)),
            firstStored: now.addingTimeInterval(-TimeInterval(86_400 - 2 * 3_600) + 0.9),
            direction: .received,
            outputReceiveAddresses: ["XdestinationAddress"],
            dashAmount: 251_000_000)
        XCTAssertEqual(assignments([letGo], [onTheBound]), ["0xa": "ab"])
    }

    func testOrdersReadAfterTheFirstReadsFailedReachTheSnapshot() async {
        // A funded order the provider refunded: it is not polled or written again, so
        // nothing but a read can bring it to the snapshot Home builds its row from.
        let order = buyOrder(status: .refunded, depositSeenSecondsAgo: 1_800, finalisedSecondsAgo: 600)
        let table = FlakyOrdersRead(failures: 2, orders: [order])
        let dao = SwapOrdersDAOImpl(readingAll: { try table.read() })

        for _ in 0..<2 {
            let failed = await dao.all()
            XCTAssertEqual(failed, [])
            XCTAssertEqual(dao.currentOrders, [])
        }
        let read = await dao.all()
        XCTAssertEqual(read, [order])
        XCTAssertEqual(dao.currentOrders, [order])
        XCTAssertEqual(table.reads, 3)

        // A read that brings nothing new publishes nothing — subscribers read in answer
        // to a publication — and subscribing reads nothing once the table has been read.
        var publications = 0
        let observation = dao.observeAll().dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        _ = await dao.all()
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(table.reads, 4)
    }

    func testSubscribingReadsTheOrdersAFailedFirstReadLeftOut() async {
        let order = buyOrder(status: .refunded, depositSeenSecondsAgo: 1_800, finalisedSecondsAgo: 600)
        let table = FlakyOrdersRead(failures: 1, orders: [order])
        let dao = SwapOrdersDAOImpl(readingAll: { try table.read() })
        let failed = await dao.all()
        XCTAssertEqual(failed, [])

        // Home only observes: its subscription alone has to bring the stored orders.
        let published = expectation(description: "the stored orders are published")
        let observation = dao.observeAll().filter { !$0.isEmpty }.first().sink { orders in
            XCTAssertEqual(orders, [order])
            published.fulfill()
        }
        defer { observation.cancel() }
        await fulfillment(of: [published], timeout: 5)
        XCTAssertEqual(dao.currentOrders, [order])
        XCTAssertEqual(table.reads, 2)
    }

    func testALinkIsWithdrawnWhenItsOrderGivesUpThePayout() {
        // The details screen holds the link of the order a receive was assigned to.
        let order = buyOrder(id: "0xa", status: .pending)
        let linked = TxDetailModel.LinkedBuyOrder(order)
        func withdrawn(_ current: SwapOrder?) -> Bool {
            TxDetailModel.hasGivenUpItsPayout(linked, current: current)
        }
        // The provider then ends the order without a payout: it claims nothing any more,
        // and with no claimant left the wallet is not read — the link goes on the
        // order's own word.
        for status in [SwapOrderStatus.refunded, .failed] {
            var ended = order
            ended.status = status
            ended.finalisedAt = Int64(now.timeIntervalSince1970)
            XCTAssertTrue(withdrawn(ended), "\(status)")
        }
        // An order that can still be paid out keeps it: the assignment may be empty only
        // because the wallet could not be read…
        for status in [SwapOrderStatus.notStarted, .pending, .swapping, .unknown, .completed] {
            var open = order
            open.status = status
            XCTAssertFalse(withdrawn(open), "\(status)")
        }
        var expired = order
        expired.status = .expired
        expired.finalisedAt = Int64(now.timeIntervalSince1970)
        XCTAssertFalse(withdrawn(expired))
        // An expired order with no time of expiry on record claims nothing.
        expired.finalisedAt = -1
        XCTAssertTrue(withdrawn(expired))
        // …as does one saved before deposits were recorded, which claims in any status.
        var legacy = order
        legacy.status = .refunded
        legacy.fromAmount = nil
        XCTAssertFalse(withdrawn(legacy))
        // A newer order on the same deposit address is not the one the link was built from.
        var newer = order
        newer.timestamp += 60_000
        XCTAssertTrue(withdrawn(newer))
        // A row that could not be read tells nothing.
        XCTAssertFalse(withdrawn(nil))
    }

    func testTheStoresTimeIsTheRowsCreationTime() {
        let row = PersistentTransaction(
            txid: Data(repeating: 7, count: 32), transactionData: Data(), firstSeen: 1_700_000_000)
        row.blockTimestamp = 1_700_010_800
        let transaction = Transaction(persistentTransaction: row)
        XCTAssertEqual(transaction.date, Date(timeIntervalSince1970: 1_700_010_800))
        XCTAssertEqual(transaction.firstStored, row.createdAt)
    }

    func testOrdersSavedBeforeDepositsWereRecordedKeepTheirOldMatching() {
        for status in [SwapOrderStatus.expired, .refunded, .failed] {
            var legacy = buyOrder(status: status)
            legacy.fromAmount = nil
            XCTAssertTrue(legacy.isLegacyRecord)
            XCTAssertTrue(legacy.mayStillBePaidOut, "\(status)")
            // …but it is still no row of its own: no deposit on record, no owner.
            XCTAssertFalse(legacy.isBuyHistoryRow(walletPayout: .notFound, now: now), "\(status)")
        }
        XCTAssertFalse(buyOrder().isLegacyRecord)
    }

    func testSettleWaitScalesWithTheChain() {
        XCTAssertEqual(buyOrder().settleSeconds, 3_600)
        XCTAssertEqual(buyOrder(fromAsset: "BTC.BTC").settleSeconds, 10_800)
        XCTAssertEqual(buyOrder(fromAsset: "LTC.LTC").settleSeconds, 5_400)
    }

    func testNoTransactionsMeansNoPayouts() {
        let none: [PayoutFixture] = []
        XCTAssertTrue(SwapBuyTransactionMatcher.payoutResolution(among: [buyOrder(status: .pending)], in: none).assigned.isEmpty)
        XCTAssertTrue(SwapBuyTransactionMatcher.matchingTransactions(for: buyOrder(status: .pending), in: none).isEmpty)
    }

    // MARK: Payout assignment

    /// A received transaction of 2.51 DASH to the orders' address, `secondsAgo` before `now`.
    /// `storedSecondsAgo`: when the wallet's store first held it; not known when nil.
    private func payout(_ hash: String, secondsAgo: Int64, storedSecondsAgo: Int64? = nil) -> PayoutFixture {
        PayoutFixture(
            txHashHexString: hash,
            date: now.addingTimeInterval(-TimeInterval(secondsAgo)),
            firstStored: storedSecondsAgo.map { now.addingTimeInterval(-TimeInterval($0)) },
            direction: .received,
            outputReceiveAddresses: ["XdestinationAddress"],
            dashAmount: 251_000_000)
    }

    private func assignments(_ orders: [SwapOrder], _ transactions: [PayoutFixture]) -> [String: String] {
        SwapBuyTransactionMatcher.payoutResolution(among: orders, in: transactions).assigned.mapValues(\.txHashHexString)
    }

    func testALiveOrderDoesNotTakeAnExpiredOrdersLatePayout() {
        // A was paid and expired a day ago; B is a new attempt for the same amount. The one
        // payout fits both, and expiry does not say whose it is.
        let funded = buyOrder(
            id: "0xa", status: .expired, depositSeenSecondsAgo: 5 * 86_400, finalisedSecondsAgo: 86_400,
            createdSecondsAgo: 6 * 86_400)
        let live = buyOrder(id: "0xb", createdSecondsAgo: 600)
        XCTAssertEqual(assignments([funded, live], [payout("aa", secondsAgo: 60)]), [:])
        // Two payouts do not settle it either: nothing says they arrive in the order the
        // attempts were made.
        XCTAssertEqual(assignments([funded, live], [payout("aa", secondsAgo: 300), payout("bb", secondsAgo: 60)]), [:])
        // An expired order nobody paid only claims what was there about when it was let
        // go, and only what the others left: it stands in nobody's way.
        let unpaid = buyOrder(id: "0xa", status: .expired, finalisedSecondsAgo: 86_400, createdSecondsAgo: 6 * 86_400)
        XCTAssertEqual(assignments([unpaid, live], [payout("aa", secondsAgo: 60)]), ["0xb": "aa"])
    }

    func testLatePayoutIsBoundedByItsDateNotByWhenTheWalletIsLookedAt() {
        // Expired 30 days ago: the look happens long after the recovery window closed.
        let expiredAgo = 30 * 86_400 as Int64
        let funded = buyOrder(
            id: "0xa", status: .expired, depositSeenSecondsAgo: 35 * 86_400, finalisedSecondsAgo: expiredAgo,
            createdSecondsAgo: 36 * 86_400)
        // Arrived a minute before the window closed: still its payout.
        let inWindow = payout("aa", secondsAgo: expiredAgo - SwapOrder.latePayoutSeconds + 60)
        XCTAssertEqual(assignments([funded], [inWindow]), ["0xa": "aa"])
        // Arrived a minute after: an unrelated receive.
        let afterWindow = payout("bb", secondsAgo: expiredAgo - SwapOrder.latePayoutSeconds - 60)
        XCTAssertEqual(assignments([funded], [afterWindow]), [:])
        // …and it is free for another order it fits.
        let live = buyOrder(id: "0xb", status: .pending, createdSecondsAgo: 25 * 86_400)
        XCTAssertEqual(assignments([funded, live], [afterWindow]), ["0xb": "bb"])
    }

    func testIndistinguishablePayoutsAreNotPairedByCreationTime() {
        // A was made before B, but B was funded and paid out first. Both payouts fit both.
        let first = buyOrder(id: "0xa", status: .pending, createdSecondsAgo: 7_200)
        let second = buyOrder(id: "0xb", status: .pending, createdSecondsAgo: 3_600)
        let paidToSecond = payout("bb", secondsAgo: 600)
        let paidToFirst = payout("aa", secondsAgo: 60)
        XCTAssertEqual(assignments([first, second], [paidToSecond, paidToFirst]), [:])
        // The provider's word settles it: each completed order names its own transaction.
        var firstDone = first, secondDone = second
        firstDone.status = .completed; firstDone.outboundTxHash = "aa"
        secondDone.status = .completed; secondDone.outboundTxHash = "bb"
        XCTAssertEqual(
            assignments([firstDone, secondDone], [paidToSecond, paidToFirst]),
            ["0xa": "aa", "0xb": "bb"])
        // Completed without a named transaction says each was paid, not with which.
        firstDone.outboundTxHash = nil
        secondDone.outboundTxHash = nil
        XCTAssertEqual(assignments([firstDone, secondDone], [paidToSecond, paidToFirst]), [:])
        // …and the unsettled pair is not left for a live order to take.
        let third = buyOrder(id: "0xc", status: .pending, createdSecondsAgo: 1_800)
        XCTAssertEqual(assignments([firstDone, secondDone, third], [paidToSecond, paidToFirst]), [:])
        XCTAssertEqual(
            SwapBuyTransactionMatcher.payoutResolution(
                among: [firstDone, secondDone, third], in: [paidToSecond, paidToFirst]).contested,
            ["0xa", "0xb", "0xc"])
        // Nor does being the only completed one say which of the two is its own while a
        // live order fits them as well…
        XCTAssertEqual(assignments([firstDone, second], [paidToSecond, paidToFirst]), [:])
        // …but a single transaction goes to the order the provider says was paid, and that
        // leaves no open question about the other.
        let single = SwapBuyTransactionMatcher.payoutResolution(among: [firstDone, second], in: [paidToFirst])
        XCTAssertEqual(single.assigned.mapValues(\.txHashHexString), ["0xa": "aa"])
        XCTAssertTrue(single.contested.isEmpty)
        // A live order does not settle for the transaction left over from an open question
        // it is part of.
        let leftOver = payout("cc", secondsAgo: 30)
        XCTAssertEqual(assignments([firstDone, second], [paidToSecond, paidToFirst, leftOver]), [:])
        // An old attempt saved before deposits were recorded stands in nobody's way: the
        // live order takes its earliest, the old one what is left.
        let legacy = buyOrder(id: "0xl", status: .expired, finalisedSecondsAgo: 86_400, createdSecondsAgo: 9_000)
        var legacyRecord = legacy
        legacyRecord.fromAmount = nil
        XCTAssertTrue(legacyRecord.isLegacyRecord)
        XCTAssertEqual(
            assignments([legacyRecord, second], [paidToSecond, paidToFirst]),
            ["0xb": "bb", "0xl": "aa"])
        // One of them named settles both.
        secondDone.outboundTxHash = "bb"
        XCTAssertEqual(
            assignments([firstDone, secondDone], [paidToSecond, paidToFirst]),
            ["0xa": "aa", "0xb": "bb"])
        // An order alone on its payout still takes it.
        XCTAssertEqual(assignments([second], [paidToSecond]), ["0xb": "bb"])
    }

    func testCompletedOrdersSharingPayoutsHaveEnoughOnlyWithOneEach() {
        let first = buyOrder(id: "0xa", status: .completed, createdSecondsAgo: 7_200)
        let second = buyOrder(id: "0xb", status: .completed, createdSecondsAgo: 3_600)
        // Never paid, and fits the same transactions.
        let abandoned = buyOrder(id: "0xc", createdSecondsAgo: 1_800)
        let one = payout("aa", secondsAgo: 600), other = payout("bb", secondsAgo: 60)
        func resolve(_ orders: [SwapOrder], _ txs: [PayoutFixture]) -> PayoutResolution<PayoutFixture> {
            SwapBuyTransactionMatcher.payoutResolution(among: orders, in: txs)
        }
        // Two payouts for the two the provider says were paid — whatever else shares them.
        XCTAssertEqual(resolve([first, second], [one, other]).contestedWithEnough, ["0xa", "0xb"])
        let withAbandoned = resolve([first, second, abandoned], [one, other])
        XCTAssertEqual(withAbandoned.contested, ["0xa", "0xb", "0xc"])
        XCTAssertEqual(withAbandoned.contestedWithEnough, ["0xa", "0xb"])
        // One payout for the two of them: somebody's has not arrived.
        let short = resolve([first, second], [one])
        XCTAssertEqual(short.contested, ["0xa", "0xb"])
        XCTAssertTrue(short.contestedWithEnough.isEmpty)
        // Orders still open are never counted in: their row does not depend on it.
        let open = resolve([abandoned, buyOrder(id: "0xd", createdSecondsAgo: 900)], [one, other])
        XCTAssertEqual(open.contested, ["0xc", "0xd"])
        XCTAssertTrue(open.contestedWithEnough.isEmpty)
    }

    func testAnUnsettledPayoutIsNotAMissingOne() {
        // Two unpaid-looking orders for the same amount; both were paid while the app was
        // away. The provider has forgotten them (404) and the deposit addresses were swept.
        let first = buyOrder(id: "0xa", createdSecondsAgo: 7 * 86_400)
        let second = buyOrder(id: "0xb", createdSecondsAgo: 6 * 86_400)
        let lone = buyOrder(id: "0xc", expected: "9", createdSecondsAgo: 6 * 86_400)
        let resolution = SwapBuyTransactionMatcher.payoutResolution(
            among: [first, second, lone],
            in: [payout("aa", secondsAgo: 5 * 86_400), payout("bb", secondsAgo: 4 * 86_400)])
        XCTAssertTrue(resolution.assigned.isEmpty)
        XCTAssertEqual(resolution.contested, ["0xa", "0xb"])

        // Synced and read — but the wallet holds what may be their payouts, so it does not
        // vouch for "none arrived", and they are not let go on the provider's and the
        // chain's "nothing".
        var wallet = SwapTrackingService.WalletView(synced: true, walletId: "aa11", network: "0", historyPersisted: true)
        wallet.contested = resolution.contested
        for order in [first, second] {
            let walletReady = wallet.vouches(for: order, activeWalletId: "aa11", activeNetwork: "0")
            XCTAssertFalse(walletReady)
            XCTAssertFalse(mayLetGo(sinceAgedOut: 365 * 86_400, walletReady: walletReady, lookup: .absent))
        }
        // An order no transaction fits is judged as before.
        let walletReady = wallet.vouches(for: lone, activeWalletId: "aa11", activeNetwork: "0")
        XCTAssertTrue(walletReady)
        XCTAssertTrue(mayLetGo(sinceAgedOut: 365 * 86_400, walletReady: walletReady, lookup: .absent))
    }

    func testThePoolReachesBackToEveryOrderThatCanClaim() {
        // A completed long ago and names its payout; B is new, for the same amount.
        let aa = String(repeating: "a", count: 64)
        let old = buyOrder(
            id: "0xa", status: .completed, depositSeenSecondsAgo: 40 * 86_400, finalisedSecondsAgo: 600,
            createdSecondsAgo: 40 * 86_400, payoutHash: aa)
        let live = buyOrder(id: "0xb", status: .pending, createdSecondsAgo: 3_600)
        let own = payout(aa, secondsAgo: 40 * 86_400 - 600)
        let new = payout("bb", secondsAgo: 60)

        // Cut to the live order alone, the pool lacks A's payout. A names its own, so it
        // takes no look-alike; a completed order that names none would take B's — and so
        // would one whose hash is not a Dash transaction's.
        XCTAssertTrue(old.namesItsPayout)
        XCTAssertEqual(assignments([old, live], [new]), ["0xb": "bb"])
        for hash in [nil, "0x" + aa, "0xsource"] {
            var unnamedOld = old
            unnamedOld.outboundTxHash = hash
            XCTAssertFalse(unnamedOld.namesItsPayout)
            XCTAssertEqual(assignments([unnamedOld, live], [new]), ["0xa": "bb"])
        }
        // So the cutoff is the oldest claimant's, and with that pool each has its own.
        XCTAssertEqual(
            SwapBuyTransactionMatcher.fetchCutoff(forAssignmentsAmong: [old, live]),
            SwapBuyTransactionMatcher.fetchCutoff(for: old))
        XCTAssertEqual(assignments([old, live], [own, new]), ["0xa": aa, "0xb": "bb"])
        // Orders that can claim nothing do not widen it.
        let refunded = buyOrder(id: "0xc", status: .refunded, createdSecondsAgo: 90 * 86_400)
        XCTAssertEqual(
            SwapBuyTransactionMatcher.fetchCutoff(forAssignmentsAmong: [refunded, live]),
            SwapBuyTransactionMatcher.fetchCutoff(for: live))
        XCTAssertNil(SwapBuyTransactionMatcher.fetchCutoff(forAssignmentsAmong: [refunded]))
    }

    // MARK: Letting an order go

    private func mayLetGo(
        fundsInFlight: Bool = false,
        depositOnRecord: Bool = false,
        sinceAgedOut: Int64,
        providerAnswered: Bool = true,
        walletReady: Bool = true,
        watchesDeposit: Bool = true,
        lookup: SwapTrackingService.DepositLookup = .absent
    ) -> Bool {
        SwapTrackingService.mayLetGo(
            fundsInFlight: fundsInFlight, depositOnRecord: depositOnRecord,
            sinceAgedOut: sinceAgedOut, settleSeconds: 3_600,
            providerAnswered: providerAnswered, walletReady: walletReady,
            watchesDeposit: watchesDeposit, lookup: lookup)
    }

    func testAnUnpaidOrderIsLetGoOnlyOnAnswers() {
        XCTAssertTrue(mayLetGo(sinceAgedOut: 3_601))
        XCTAssertFalse(mayLetGo(sinceAgedOut: 3_600), "a late transfer may still land")
        XCTAssertTrue(mayLetGo(sinceAgedOut: 3_601, watchesDeposit: false, lookup: .unknown))
    }

    func testNoAmountOfElapsedTimeStandsInForAnAnswer() {
        let aYear = 365 * 86_400 as Int64
        // The balance lookup failed: the address is not known to be empty.
        XCTAssertFalse(mayLetGo(sinceAgedOut: 86_400 + 1, lookup: .unknown))
        XCTAssertFalse(mayLetGo(sinceAgedOut: aYear, lookup: .unknown))
        XCTAssertFalse(mayLetGo(sinceAgedOut: aYear, lookup: .seen))
        // A cold launch long afterwards: the provider request failed, the wallet is not synced.
        XCTAssertFalse(mayLetGo(sinceAgedOut: aYear, providerAnswered: false))
        XCTAssertFalse(mayLetGo(sinceAgedOut: aYear, walletReady: false))
        XCTAssertFalse(mayLetGo(fundsInFlight: true, sinceAgedOut: aYear, providerAnswered: false))
        XCTAssertFalse(mayLetGo(fundsInFlight: true, sinceAgedOut: aYear, walletReady: false))
        XCTAssertTrue(mayLetGo(fundsInFlight: true, sinceAgedOut: 1, lookup: .unknown))
        // Only an order whose deposit is on record goes without them, and only after its
        // grace: it keeps its row and is still matched to a late payout.
        XCTAssertFalse(mayLetGo(
            fundsInFlight: true, depositOnRecord: true, sinceAgedOut: SwapOrder.fundedGraceSeconds,
            providerAnswered: false, walletReady: false))
        XCTAssertTrue(mayLetGo(
            fundsInFlight: true, depositOnRecord: true, sinceAgedOut: SwapOrder.fundedGraceSeconds + 1,
            providerAnswered: false, walletReady: false))
    }

    func testAnotherWalletsSyncSaysNothingAboutAnOrder() {
        let order = buyOrder()   // made in wallet aa11 on network 0
        let own = SwapTrackingService.WalletView(synced: true, walletId: "aa11", network: "0", historyPersisted: true)
        XCTAssertTrue(own.vouches(for: order, activeWalletId: "aa11", activeNetwork: "0"))
        // The user switched to another, synced wallet.
        let other = SwapTrackingService.WalletView(synced: true, walletId: "bb22", network: "0", historyPersisted: true)
        XCTAssertTrue(order.isForeign(toWalletId: "bb22", network: "0"))
        XCTAssertFalse(other.vouches(for: order, activeWalletId: "bb22", activeNetwork: "0"))
        XCTAssertFalse(SwapTrackingService.WalletView(synced: true, walletId: "aa11", network: "1", historyPersisted: true)
            .vouches(for: order, activeWalletId: "aa11", activeNetwork: "1"))
        // The wallet was switched while the cycle's requests were out.
        XCTAssertFalse(own.vouches(for: order, activeWalletId: "bb22", activeNetwork: "0"))
        XCTAssertFalse(own.vouches(for: order, activeWalletId: nil, activeNetwork: "0"))
        XCTAssertFalse(SwapTrackingService.WalletView(synced: false, walletId: "aa11", network: "0")
            .vouches(for: order, activeWalletId: "aa11", activeNetwork: "0"))
        // An order whose owner was never recorded is judged by the wallet at hand, as before.
        var unknown = order
        unknown.ownerWalletId = nil
        unknown.ownerNetwork = nil
        XCTAssertFalse(unknown.isForeign(toWalletId: "bb22", network: "0"))
        // Half an owner still counts for the half that is known.
        var networkOnly = order
        networkOnly.ownerWalletId = nil
        XCTAssertFalse(networkOnly.isForeign(toWalletId: "bb22", network: "0"))
        XCTAssertTrue(networkOnly.isForeign(toWalletId: "bb22", network: "1"))
        XCTAssertTrue(other.vouches(for: unknown, activeWalletId: "bb22", activeNetwork: "0"))
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

    private func holds(_ asset: String, in balances: [SwapKitBalanceItem]) -> Bool {
        SwapTrackingService.depositLookup(of: asset, in: balances) == .seen
    }

    func testHoldsAssetMatchesTheIdentifierWhateverItsCase() {
        let asset = "ARB.USDT-0XFD086BC7"
        let held = [
            SwapKitBalanceItem(identifier: "ARB.ETH", value: "0"),
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "150"),
        ]
        XCTAssertTrue(holds(asset, in: held))
    }

    func testHoldsAssetIgnoresZeroOtherAssetsAndGarbage() {
        let asset = "ARB.USDT-0XFD086BC7"
        XCTAssertFalse(holds(asset, in: []))
        XCTAssertFalse(holds(asset, in: [
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "0"),
            SwapKitBalanceItem(identifier: "ARB.USDC-0xaf88d065", value: "9"),
            SwapKitBalanceItem(identifier: "ARB.ETH", value: "1.5"),
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "n/a"),
        ]))
    }

    func testAnUnreadableBalanceIsUnknownNotAbsent() {
        let asset = "ARB.USDT-0XFD086BC7"
        func lookup(_ value: String?) -> SwapTrackingService.DepositLookup {
            SwapTrackingService.depositLookup(of: asset, in: [
                SwapKitBalanceItem(identifier: "ARB.ETH", value: "0"),
                SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: value),
            ])
        }
        XCTAssertEqual(lookup("150"), .seen)
        XCTAssertEqual(lookup("0"), .absent)
        XCTAssertEqual(lookup(nil), .unknown)
        XCTAssertEqual(lookup("n/a"), .unknown)
        XCTAssertEqual(SwapTrackingService.depositLookup(of: asset, in: []), .absent)
        // …and an unknown lookup never lets the order go, whatever else answered.
        for value in [nil, "n/a"] as [String?] {
            XCTAssertFalse(mayLetGo(sinceAgedOut: 365 * 86_400, lookup: lookup(value)))
        }
        XCTAssertTrue(mayLetGo(sinceAgedOut: 365 * 86_400, lookup: lookup("0")))
        // Several native entries, none under our name: which one is ours is not known.
        XCTAssertEqual(SwapTrackingService.depositLookup(of: "MAYA.MAYA", in: [
            SwapKitBalanceItem(identifier: "MAYA.CACAO", value: "5"),
            SwapKitBalanceItem(identifier: "MAYA.OTHER", value: "5"),
        ]), .unknown)
    }

    func testABalanceEntryWithoutANameIsUnknownNotAbsent() throws {
        let asset = "ARB.USDT-0XFD086BC7"
        // As decoded from the wire: identifier null, missing, blank.
        for entry in [#"{"identifier":null,"value":"150"}"#, #"{"value":"150"}"#, #"{"identifier":" ","value":"150"}"#] {
            let json = #"[{"identifier":"ARB.ETH","value":"0"},"# + entry + "]"
            let balances = try JSONDecoder().decode([SwapKitBalanceItem].self, from: Data(json.utf8))
            let lookup = SwapTrackingService.depositLookup(of: asset, in: balances)
            XCTAssertEqual(lookup, .unknown, entry)
            XCTAssertFalse(mayLetGo(sinceAgedOut: 365 * 86_400, lookup: lookup), entry)
            // The same for a native coin, which is looked for by its chain.
            XCTAssertEqual(SwapTrackingService.depositLookup(of: "ARB.ETH", in: balances), .unknown, entry)
        }
        // An unnamed entry that holds nothing cannot be the deposit.
        XCTAssertEqual(SwapTrackingService.depositLookup(of: asset, in: [
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "0"),
            SwapKitBalanceItem(identifier: nil, value: "0"),
        ]), .absent)
        XCTAssertEqual(SwapTrackingService.depositLookup(of: asset, in: [
            SwapKitBalanceItem(identifier: nil, value: nil),
        ]), .unknown)
        // A named, positive entry is still the deposit, whatever else is unnamed.
        XCTAssertEqual(SwapTrackingService.depositLookup(of: asset, in: [
            SwapKitBalanceItem(identifier: nil, value: "7"),
            SwapKitBalanceItem(identifier: "ARB.USDT-0xFd086bC7", value: "150"),
        ]), .seen)
    }

    func testAMalformedBalanceAmountIsUnknownNotAbsent() {
        let asset = "ARB.USDT-0XFD086BC7"
        for value in ["0junk", "0,5", "-1", "-0", "0x0", "1e3", "", " ", "0\u{0665}", "0.0\u{FF11}"] {
            XCTAssertNil(SwapTrackingService.balanceAmount(value), value)
            // Under the asset's own name, and in an entry without a name.
            for identifier in ["ARB.USDT-0xFd086bC7", nil] as [String?] {
                let lookup = SwapTrackingService.depositLookup(
                    of: asset, in: [SwapKitBalanceItem(identifier: identifier, value: value)])
                XCTAssertEqual(lookup, .unknown, "\(value) \(identifier ?? "nil")")
                XCTAssertFalse(mayLetGo(sinceAgedOut: 365 * 86_400, lookup: lookup), value)
            }
        }
        XCTAssertEqual(SwapTrackingService.balanceAmount("0"), 0)
        XCTAssertEqual(SwapTrackingService.balanceAmount(" 0.000 "), 0)
        XCTAssertEqual(SwapTrackingService.balanceAmount("150.25"), Decimal(string: "150.25"))
        XCTAssertEqual(SwapTrackingService.balanceAmount(".5"), Decimal(string: "0.5"))
        XCTAssertEqual(SwapTrackingService.balanceAmount("5."), 5)
        XCTAssertNil(SwapTrackingService.balanceAmount(String(repeating: "9", count: 50_000) + "x"))
    }

    func testSyncDoneWithTheStoreBehindCannotLetAnUnpaidOrderGo() {
        // The sync reports done at block 1000 and the store read succeeds — but the store
        // has been written only part of the way, so an empty pool is not the wallet's word.
        let order = buyOrder(id: "0xa", createdSecondsAgo: 6 * 86_400)
        let walletId = Data([0xaa, 0x11])
        func wallet(writtenTo height: UInt32?, of id: Data = walletId) -> SwapTrackingService.WalletView {
            var wallet = SwapTrackingService.WalletView(synced: true, walletId: "aa11", network: "0")
            wallet.historyPersisted = SwapTrackingService.historyIsPersisted(
                upTo: 1_000, watermark: (id, height), walletId: "aa11")
            return wallet
        }
        func mayExpire(_ wallet: SwapTrackingService.WalletView) -> Bool {
            mayLetGo(
                sinceAgedOut: 365 * 86_400,
                walletReady: wallet.vouches(for: order, activeWalletId: "aa11", activeNetwork: "0"),
                lookup: .absent)
        }
        for behind in [wallet(writtenTo: 400), wallet(writtenTo: 999), wallet(writtenTo: nil),
                       wallet(writtenTo: 1_000, of: Data([0xbb, 0x22]))] {
            XCTAssertFalse(mayExpire(behind))
        }
        XCTAssertFalse(SwapTrackingService.historyIsPersisted(upTo: 1_000, watermark: nil, walletId: "aa11"))
        XCTAssertFalse(SwapTrackingService.historyIsPersisted(upTo: 0, watermark: (walletId, 0), walletId: "aa11"))
        // A wallet nobody asked about its store vouches for nothing.
        XCTAssertFalse(mayExpire(SwapTrackingService.WalletView(synced: true, walletId: "aa11", network: "0")))

        // The store catches up: the order, kept active, takes the payout that was on its
        // way in — and only with none there would it be let go.
        XCTAssertEqual(assignments([order], [payout("aa", secondsAgo: 5 * 86_400)]), ["0xa": "aa"])
        XCTAssertTrue(mayExpire(wallet(writtenTo: 1_000)))
        XCTAssertTrue(mayExpire(wallet(writtenTo: 1_001)))
    }

    func testAPayoutWrittenDuringThePollKeepsTheOrder() {
        // The cycle's first read found nothing for the order, and the provider's and the
        // chain's "nothing" came back. Before it is let go the wallet is read again.
        let order = buyOrder(id: "0xa", createdSecondsAgo: 6 * 86_400)
        let twin = buyOrder(id: "0xb", createdSecondsAgo: 6 * 86_400)
        func secondLook(_ orders: [SwapOrder], _ transactions: [PayoutFixture]) -> PayoutResolution<String> {
            let resolution = SwapBuyTransactionMatcher.payoutResolution(among: orders, in: transactions)
            return PayoutResolution(
                assigned: resolution.assigned.mapValues(\.txHashHexString), contested: resolution.contested)
        }
        XCTAssertTrue(SwapTrackingService.holdsNoPayout(for: order, in: secondLook([order], [])))
        // Its payout was written meanwhile: it stays, for a later poll to complete.
        let written = [payout("aa", secondsAgo: 5 * 86_400)]
        XCTAssertFalse(SwapTrackingService.holdsNoPayout(for: order, in: secondLook([order], written)))
        // So it does with a transaction that may be its payout or another order's.
        XCTAssertFalse(SwapTrackingService.holdsNoPayout(for: order, in: secondLook([order, twin], written)))
        // And when the second read fails.
        XCTAssertFalse(SwapTrackingService.holdsNoPayout(for: order, in: nil))
    }

    func testAFailedWalletReadCannotLetAnUnpaidOrderGo() {
        // A wallet read that failed leaves the cycle's wallet unsynced, so it vouches for
        // nothing — and without the wallet's word no order is let go.
        let order = buyOrder()
        let unread = SwapTrackingService.WalletView(synced: false, walletId: "aa11", network: "0")
        let walletReady = unread.vouches(for: order, activeWalletId: "aa11", activeNetwork: "0")
        XCTAssertFalse(walletReady)
        XCTAssertFalse(mayLetGo(sinceAgedOut: 365 * 86_400, walletReady: walletReady))
    }

    func testNativeCoinNamedDifferentlyByTheBalanceLookupStillCounts() {
        // Toncoin: `TON.TON` in the coin list, `TON.GRAM` from `/balance`.
        let ton = [
            SwapKitBalanceItem(identifier: "TON.GRAM", value: "12.5"),
            SwapKitBalanceItem(identifier: "TON.USDT-EQCxE6mU", value: "2"),
        ]
        XCTAssertTrue(holds("TON.TON", in: ton))
        XCTAssertTrue(holds("TON.USDT-EQCXE6MU", in: ton))
        XCTAssertFalse(holds("TON.TON", in: [SwapKitBalanceItem(identifier: "TON.GRAM", value: "0")]))
        // Listed under its own name: that entry decides, a sibling native does not.
        XCTAssertFalse(holds("MAYA.MAYA", in: [
            SwapKitBalanceItem(identifier: "MAYA.MAYA", value: "0"),
            SwapKitBalanceItem(identifier: "MAYA.CACAO", value: "5"),
        ]))
        // Two natives and neither is ours: nothing to mean.
        XCTAssertFalse(holds("MAYA.MAYA", in: [
            SwapKitBalanceItem(identifier: "MAYA.CACAO", value: "5"),
            SwapKitBalanceItem(identifier: "MAYA.OTHER", value: "5"),
        ]))
        // A token is never matched by the native balance, nor a coin by another chain's.
        XCTAssertFalse(holds("TON.USDT-EQCXE6MU", in: [SwapKitBalanceItem(identifier: "TON.GRAM", value: "9")]))
        XCTAssertFalse(holds("TON.TON", in: [SwapKitBalanceItem(identifier: "SOL.SOL", value: "9")]))
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

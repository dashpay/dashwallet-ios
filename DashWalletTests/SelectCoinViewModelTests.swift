//
//  SelectCoinViewModelTests.swift
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
import Combine
import XCTest

/// Answers each pool fetch from a script; a fetch scripted as held waits until it is released.
@MainActor
private final class ScriptedPoolsProvider: SwapProvider {
    var poolAnswers: [[String]] = []
    var poolsError: Error?
    private(set) var refreshed: [[String]] = []
    private var held: CheckedContinuation<Void, Never>?
    var holdsNextFetch = false
    var isHolding: Bool { held != nil }

    var displayName: String { "Scripted" }
    var routeAvailabilityChanges: AnyPublisher<SwapDirection, Never> { Empty().eraseToAnyPublisher() }

    func release() {
        held?.resume()
        held = nil
    }

    func fetchPools() async throws -> [SwapPool] {
        if let poolsError { throw poolsError }
        let assets = poolAnswers.removeFirst()
        if holdsNextFetch {
            holdsNextFetch = false
            await withCheckedContinuation { held = $0 }
        }
        // A zero price shows no fiat row, which keeps the currency exchanger out of the test.
        return assets.map { SwapPool(asset: $0, status: "available", assetPriceUSD: "0") }
    }

    func fetchInboundAddresses() async throws -> [SwapInboundAddress] {
        ["BTC", "ETH"].map {
            SwapInboundAddress(
                chain: $0, halted: false, address: nil, chainLpActionsPaused: nil, chainTradingPaused: nil,
                dustThreshold: nil, gasRate: nil, gasRateUnits: nil, globalTradingPaused: nil,
                outboundFee: nil, outboundTxSize: nil, pubKey: nil
            )
        }
    }

    func fetchPools(direction: SwapDirection) async throws -> [SwapPool] { try await fetchPools() }

    func refreshRouteAvailability(for pools: [SwapPool], direction: SwapDirection) {
        refreshed.append(pools.map { $0.asset })
    }

    func validateAddress(destination: String, toAsset: String) async -> String? { nil }
    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        throw SwapProviderError.unsupportedBuyOrder
    }
    func fetchSwapStatus(txid: String, depositAddress: String?) async throws -> SwapStatusResult {
        throw SwapProviderError.unsupportedBuyOrder
    }
}

/// Fails the way the HTTP client's non-2xx error describes itself.
private struct RefusedLoad: LocalizedError {
    var errorDescription: String? { "Status Code: 403, Data Length: 4545" }
}

/// Online, and silent: no status event starts a load the test did not ask for.
private final class SilentOnlineStatus: NetworkStatusProviding {
    var currentStatus: NetworkStatus { .online }
    var isOnline: Bool { true }
    var statusPublisher: AnyPublisher<NetworkStatus, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
final class SelectCoinViewModelTests: XCTestCase {
    /// Two loads overlap (the view's `.task` and a reconnect, say) and the older one ends last: the
    /// rows and the live checks stay on the newer load's pools.
    func testAnOlderLoadThatEndsLastDoesNotReplaceTheNewerOne() async {
        let provider = ScriptedPoolsProvider()
        provider.poolAnswers = [["BTC.BTC"], ["ETH.ETH"]]
        provider.holdsNextFetch = true
        let model = SelectCoinViewModel(swapProvider: provider, direction: .sell, networkStatus: SilentOnlineStatus())
        let checks = Task { await model.keepRouteAvailabilityFresh() }
        defer { checks.cancel() }

        let older = Task { await model.loadCoins() }
        while !provider.isHolding { await Task.yield() }
        await model.loadCoins(force: true)
        XCTAssertEqual(model.coins.map { $0.coin.swapAsset.uppercased() }, ["ETH.ETH"])

        provider.release()
        await older.value

        XCTAssertEqual(model.coins.map { $0.coin.swapAsset.uppercased() }, ["ETH.ETH"])
        XCTAssertEqual(provider.refreshed.last, ["ETH.ETH"])
        XCTAssertFalse(model.isLoading)
    }

    /// A coin list the service refuses (an HTML 403 from the edge in front of it, say) shows the
    /// plain message, not the HTTP client's "Status Code: 403, Data Length: …" text.
    func testAFailedLoadShowsAPlainMessage() async {
        let provider = ScriptedPoolsProvider()
        provider.poolsError = RefusedLoad()
        let model = SelectCoinViewModel(swapProvider: provider, direction: .sell, networkStatus: SilentOnlineStatus())

        await model.loadCoins()

        XCTAssertEqual(model.errorMessage, SelectCoinViewModel.loadFailedMessage)
        XCTAssertFalse(model.errorMessage?.contains("Status Code") ?? true)
    }
}

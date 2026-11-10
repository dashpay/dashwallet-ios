//
//  SwapRouteAvailabilityTests.swift
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

/// Scripted probe answers, keyed by provider and asset; anything unscripted routes.
@MainActor
private final class ProbeScript {
    var answers: [String: LiveRouteState] = [:]
    private(set) var calls: [String] = []
    private(set) var maxInFlight = 0
    private var inFlight = 0
    /// Holds each probe open for a moment so concurrent probes overlap and the limit is observable.
    var holdNanoseconds: UInt64 = 0
    /// When closed, every probe waits until `openGate()`.
    private var gateClosed = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    func closeGate() { gateClosed = true }

    func openGate() {
        gateClosed = false
        gateWaiters.forEach { $0.resume() }
        gateWaiters.removeAll()
    }

    func set(_ state: LiveRouteState, _ provider: RouteProvider, _ asset: String) {
        answers[Self.key(provider, asset)] = state
    }

    func calls(to provider: RouteProvider) -> [String] {
        let prefix = "\(provider)|"
        return calls.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    var probe: SwapRouteAvailability.Probe {
        { [unowned self] asset, provider, _ in
            let key = Self.key(provider, asset)
            self.calls.append(key)
            self.inFlight += 1
            self.maxInFlight = max(self.maxInFlight, self.inFlight)
            if self.holdNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: self.holdNanoseconds)
            }
            if self.gateClosed {
                await withCheckedContinuation { self.gateWaiters.append($0) }
            }
            self.inFlight -= 1
            return self.answers[key] ?? .available
        }
    }

    private static func key(_ provider: RouteProvider, _ asset: String) -> String {
        "\(provider)|\(asset.uppercased())"
    }
}

@MainActor
final class SwapRouteAvailabilityTests: XCTestCase {
    private let both: Set<RouteProvider> = [.near, .maya]

    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var script: ProbeScript!
    private var store: SwapRouteAvailability!

    override func setUp() async throws {
        clock = Date(timeIntervalSince1970: 1_800_000_000)
        script = ProbeScript()
        store = SwapRouteAvailability(now: { [unowned self] in self.clock })
    }

    /// Refreshes Sell for `capability` (asset → capable providers) in the dictionary's key order.
    private func refresh(_ capability: KeyValuePairs<String, Set<RouteProvider>>, direction: SwapDirection = .sell) async {
        let map = Dictionary(capability.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        await store.refresh(
            assets: capability.map { $0.key },
            direction: direction,
            capable: { map[$0.uppercased()] ?? [] },
            probe: script.probe
        )
    }

    private func label(_ asset: String, capable: Set<RouteProvider>, direction: SwapDirection = .sell) -> RouteProvider? {
        RouteProvider.label(forUsable: store.usableProviders(for: asset, capable: capable, direction: direction))
    }

    // MARK: Labels

    func testLabelFollowsTheUsableProviders() {
        XCTAssertEqual(RouteProvider.label(forUsable: [.near, .maya]), .multiple)
        XCTAssertEqual(RouteProvider.label(forUsable: [.near]), .near)
        XCTAssertEqual(RouteProvider.label(forUsable: [.maya]), .maya)
        XCTAssertNil(RouteProvider.label(forUsable: []))
    }

    func testNothingKnownKeepsTheStaticCapability() {
        XCTAssertEqual(label("BTC.BTC", capable: both), .multiple)
        XCTAssertEqual(label("MAYA.CACAO", capable: [.maya]), .maya)
    }

    // MARK: NEAR and Maya, each up or down

    func testBothProvidersRoutingIsMultiple() async {
        await refresh(["ETH.USDT": both])

        XCTAssertEqual(label("ETH.USDT", capable: both), .multiple)
    }

    /// NEAR up, Maya halted for the coin's chain (ETH trading paused on Maya, 2026-11-02).
    func testNearUpMayaHaltedLeavesNear() async {
        script.set(.halted, .maya, "ETH.USDT")

        await refresh(["ETH.USDT": both])

        XCTAssertEqual(label("ETH.USDT", capable: both), .near)
    }

    /// NEAR up in general but without a route for this coin, Maya routing it.
    func testNearNoRouteForTheCoinMayaUpLeavesMaya() async {
        script.set(.noRoute, .near, "ARB.USDT")

        await refresh(["ARB.USDT": both])

        XCTAssertEqual(label("ARB.USDT", capable: both), .maya)
    }

    /// NEAR down for DASH (every sentinel without a route, 2026-11-02), Maya routing.
    func testNearDownMayaUpLeavesMayaAndHaltsNearOnlyCoins() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }

        await refresh(["MAYA.CACAO": [.maya], "ARB.ETH": both, "SOL.SOL": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(label("ARB.ETH", capable: both), .maya)
        XCTAssertEqual(label("MAYA.CACAO", capable: [.maya]), .maya)
        XCTAssertTrue(store.usableProviders(for: "SOL.SOL", capable: [.near], direction: .sell).isEmpty)
    }

    func testNearDownMayaHaltedHaltsTheCoin() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.set(.halted, .maya, "ETH.USDT")
        script.set(.halted, .maya, "MAYA.CACAO")

        await refresh(["ETH.USDT": both, "MAYA.CACAO": [.maya]])

        XCTAssertTrue(store.usableProviders(for: "ETH.USDT", capable: both, direction: .sell).isEmpty)
        XCTAssertTrue(store.usableProviders(for: "MAYA.CACAO", capable: [.maya], direction: .sell).isEmpty)
    }

    /// The case from the bug report: ARB.USDT with no route on either provider.
    func testNoRouteOnEitherProviderHaltsTheCoin() async {
        script.set(.noRoute, .near, "ARB.USDT")
        script.set(.noRoute, .maya, "ARB.USDT")

        await refresh(["ARB.USDT": both])

        XCTAssertTrue(store.usableProviders(for: "ARB.USDT", capable: both, direction: .sell).isEmpty)
    }

    func testMayaOnlyCoinIsUnaffectedByNear() async {
        script.set(.noRoute, .near, "MAYA.CACAO")

        await refresh(["MAYA.CACAO": [.maya]])

        XCTAssertEqual(label("MAYA.CACAO", capable: [.maya]), .maya)
        XCTAssertFalse(script.calls(to: .near).contains("MAYA.CACAO"))
    }

    // MARK: NEAR sentinels

    func testNearDownSkipsEveryPerCoinNearProbe() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }

        await refresh(["ETH.USDT": both, "AVAX.AVAX": [.near], "TRON.TRX": [.near]])

        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH"], "two conclusive sentinels, nothing per coin")
        XCTAssertEqual(script.calls(to: .maya), ["ETH.USDT"])
    }

    func testOneRoutingSentinelProbesEveryNearCoin() async {
        script.set(.noRoute, .near, "BTC.BTC")

        await refresh(["ETH.USDT": both, "AVAX.AVAX": [.near], "TRON.TRX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(Set(script.calls(to: .near)), ["BTC.BTC", "ETH.ETH", "ETH.USDT", "AVAX.AVAX", "TRON.TRX"])
    }

    func testAnInconclusiveSentinelAsksTheThird() async {
        script.set(.unknown, .near, "BTC.BTC")
        script.set(.noRoute, .near, "ETH.ETH")

        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH", "SOL.SOL", "AVAX.AVAX"])
        XCTAssertEqual(store.nearVerdict(for: .sell), .up, "SOL.SOL routed")
    }

    /// The third sentinel stands in for an inconclusive one: two conclusive no-routes out of three
    /// still mean NEAR is down.
    func testTwoNoRoutesBesideAnInconclusiveSentinelMeanDown() async {
        script.set(.unknown, .near, "BTC.BTC")
        script.set(.noRoute, .near, "ETH.ETH")
        script.set(.noRoute, .near, "SOL.SOL")

        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertFalse(script.calls(to: .near).contains("AVAX.AVAX"))
    }

    /// Halts on the sentinels' chains are about those chains, not about NEAR.
    func testHaltedSentinelsDoNotMeanNearIsDown() async {
        script.set(.halted, .near, "BTC.BTC")
        script.set(.halted, .near, "ETH.ETH")
        script.set(.halted, .near, "SOL.SOL")

        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertNil(store.nearVerdict(for: .sell))
        XCTAssertEqual(label("AVAX.AVAX", capable: [.near]), .near)
    }

    /// A halted sentinel counts toward neither outcome, so SOL is asked in its place: halted beside
    /// one no-route settles nothing on its own.
    func testAHaltedSentinelIsStoodInFor() async {
        script.set(.halted, .near, "BTC.BTC")
        script.set(.noRoute, .near, "ETH.ETH")
        script.set(.noRoute, .near, "SOL.SOL")

        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH", "SOL.SOL"])
        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(store.state(of: .near, for: "BTC.BTC", direction: .sell), .halted, "its own answer")
    }

    func testAHaltedSentinelStoodInForByARoutingSOLMeansUp() async {
        script.set(.halted, .near, "BTC.BTC")
        script.set(.noRoute, .near, "ETH.ETH")

        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH", "SOL.SOL", "AVAX.AVAX"])
    }

    /// Two halted chains do not freeze an old outage: SOL routing shows the recovery.
    func testTwoHaltedSentinelsDoNotHideARecovery() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(store.nearVerdict(for: .sell), .down)

        clock += 121
        script.set(.halted, .near, "BTC.BTC")
        script.set(.halted, .near, "ETH.ETH")
        script.set(.available, .near, "SOL.SOL")
        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
    }

    /// No sentinel routes, but fewer than two answered conclusively: NEAR is not declared down, no
    /// coin is probed on its own, and the static labels stay.
    func testInconclusiveSentinelsLeaveNearOpen() async {
        script.set(.unknown, .near, "BTC.BTC")
        script.set(.noRoute, .near, "ETH.ETH")
        script.set(.unknown, .near, "SOL.SOL")

        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertNil(store.nearVerdict(for: .sell))
        XCTAssertFalse(script.calls(to: .near).contains("AVAX.AVAX"))
        XCTAssertEqual(label("AVAX.AVAX", capable: [.near]), .near)
    }

    /// Sentinel checks skip the per-coin back-off, so an inconclusive round must hold off on its
    /// own: the picker refreshes every minute, the sentinels are asked at most once per 2 minutes.
    func testAnInconclusiveSentinelRoundIsNotRepeatedForTwoMinutes() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.unknown, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])
        let round = ["BTC.BTC", "ETH.ETH", "SOL.SOL"]
        XCTAssertEqual(script.calls(to: .near), round)

        clock += 60
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(script.calls(to: .near), round, "a minute later the round is not sent again")

        clock += 61
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(script.calls(to: .near), round + round, "after two minutes the round runs again")
    }

    func testNoNearCapableCoinSkipsTheSentinels() async {
        await refresh(["MAYA.CACAO": [.maya]])

        XCTAssertTrue(script.calls(to: .near).isEmpty)
    }

    // MARK: Cache

    func testFreshAnswersAreNotAskedAgain() async {
        await refresh(["ETH.USDT": both])
        let first = script.calls.count

        await refresh(["ETH.USDT": both])

        XCTAssertEqual(script.calls.count, first)
    }

    /// A due answer is asked again, but keeps counting until the new one is in: the label does not
    /// fall back to the static guess in between.
    func testDueAnswersAreAskedAgainAndKeepCountingMeanwhile() async {
        script.set(.halted, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": both])
        XCTAssertEqual(label("ETH.USDT", capable: both), .near)

        clock += 601
        XCTAssertEqual(label("ETH.USDT", capable: both), .near, "still the last conclusive answer")

        script.set(.available, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": both])
        XCTAssertEqual(script.calls(to: .maya), ["ETH.USDT", "ETH.USDT"])
        XCTAssertEqual(label("ETH.USDT", capable: both), .multiple)
    }

    func testAnswersAreForgottenAfterHalfAnHour() async {
        script.set(.halted, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": both])

        clock += 1801

        XCTAssertNil(store.state(of: .maya, for: "ETH.USDT", direction: .sell))
        XCTAssertEqual(label("ETH.USDT", capable: both), .multiple)
    }

    /// A forgotten answer is reported, so the picker re-renders a halted row even when the re-check
    /// is inconclusive and stores nothing.
    func testAForgottenAnswerIsReported() async {
        script.set(.halted, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": [.maya]])
        XCTAssertEqual(store.state(of: .maya, for: "ETH.USDT", direction: .sell), .halted)

        var reported: [SwapDirection] = []
        let cancellable = store.changes.sink { reported.append($0) }
        defer { cancellable.cancel() }
        clock += 1801
        script.set(.unknown, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": [.maya]])

        XCTAssertEqual(reported, [.sell])
        XCTAssertNil(store.state(of: .maya, for: "ETH.USDT", direction: .sell))
    }

    func testAForgottenNearOutageIsReported() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(store.nearVerdict(for: .sell), .down)

        var reported: [SwapDirection] = []
        let cancellable = store.changes.sink { reported.append($0) }
        defer { cancellable.cancel() }
        clock += 1801
        SwapRouteAvailability.nearSentinels.forEach { script.set(.unknown, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(reported, [.sell])
        XCTAssertNil(store.nearVerdict(for: .sell))
        XCTAssertEqual(label("AVAX.AVAX", capable: [.near]), .near)
    }

    /// Nothing aged out: a refresh that learns nothing new reports nothing.
    func testARefreshWithNothingForgottenReportsNothing() async {
        script.set(.halted, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": [.maya]])

        var reported: [SwapDirection] = []
        let cancellable = store.changes.sink { reported.append($0) }
        defer { cancellable.cancel() }
        clock += 601
        await refresh(["ETH.USDT": [.maya]])

        XCTAssertTrue(reported.isEmpty)
    }

    /// A NEAR outage is re-checked after two minutes — with real requests, not the sentinels'
    /// cached no-routes — so a recovery shows quickly.
    func testNearOutageIsReCheckedAfterTwoMinutes() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(store.nearVerdict(for: .sell), .down)

        clock += 60
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH"], "not due yet")

        clock += 61
        XCTAssertEqual(store.nearVerdict(for: .sell), .down, "still counts until re-checked")
        script.set(.available, .near, "BTC.BTC")
        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH", "BTC.BTC", "AVAX.AVAX"])
    }

    /// When NEAR recovers, the other sentinels' no-routes from the outage are asked again in the
    /// same refresh instead of keeping those coins halted for ten minutes.
    func testARecoveryAsksTheOtherSentinelsAgain() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["ETH.ETH": [.near], "AVAX.AVAX": [.near]])
        XCTAssertEqual(store.state(of: .near, for: "ETH.ETH", direction: .sell), .noRoute)

        clock += 121
        SwapRouteAvailability.nearSentinels.forEach { script.set(.available, .near, $0) }
        await refresh(["ETH.ETH": [.near], "AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH", "BTC.BTC", "ETH.ETH", "AVAX.AVAX"])
        XCTAssertEqual(store.state(of: .near, for: "ETH.ETH", direction: .sell), .available)
    }

    /// A recovery keeps a sentinel's no-route measured in the same round: that coin is not asked
    /// a second time in the refresh.
    func testARecoveryKeepsANoRouteFromItsOwnRound() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["BTC.BTC": [.near], "AVAX.AVAX": [.near]])

        clock += 121
        script.set(.available, .near, "ETH.ETH")
        script.set(.available, .near, "AVAX.AVAX")
        await refresh(["BTC.BTC": [.near], "AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(script.calls(to: .near), ["BTC.BTC", "ETH.ETH", "BTC.BTC", "ETH.ETH", "AVAX.AVAX"])
        XCTAssertEqual(store.state(of: .near, for: "BTC.BTC", direction: .sell), .noRoute)
    }

    /// Re-confirming an outage does not bury a coin's own answer recorded after the round that
    /// first found the outage started.
    func testAReConfirmedOutageKeepsANewerPerCoinAnswer() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["ARB.USDT": [.near]])
        clock += 1
        store.record(.available, provider: .near, asset: "ARB.USDT", direction: .sell)

        clock += 121
        await refresh(["ARB.USDT": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(label("ARB.USDT", capable: [.near]), .near)
    }

    /// A coin's own answer recorded after the round that first found the outage started wins over it.
    func testANewerPerCoinAnswerOverridesTheNearOutage() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["ARB.USDT": [.near]])
        XCTAssertTrue(store.usableProviders(for: "ARB.USDT", capable: [.near], direction: .sell).isEmpty)

        clock += 1
        store.record(.available, provider: .near, asset: "ARB.USDT", direction: .sell)

        XCTAssertEqual(label("ARB.USDT", capable: [.near]), .near)
    }

    // MARK: Inconclusive answers

    func testAnInconclusiveAnswerIsNotCached() async {
        script.set(.unknown, .maya, "ETH.USDT")
        await refresh(["ETH.USDT": [.maya]])
        await refresh(["ETH.USDT": [.maya]])
        XCTAssertEqual(script.calls(to: .maya), ["ETH.USDT"], "backed off for two minutes, not polled every tick")

        clock += 121
        await refresh(["ETH.USDT": [.maya]])

        XCTAssertEqual(script.calls(to: .maya), ["ETH.USDT", "ETH.USDT"], "asked again, not blocked for ten minutes")
        XCTAssertEqual(label("ETH.USDT", capable: [.maya]), .maya)
    }

    func testAnInconclusiveAnswerDoesNotEraseAConclusiveOne() async {
        store.record(.halted, provider: .maya, asset: "ETH.USDT", direction: .sell)
        store.record(.unknown, provider: .maya, asset: "ETH.USDT", direction: .sell)

        XCTAssertEqual(store.state(of: .maya, for: "ETH.USDT", direction: .sell), .halted)
    }

    /// An inconclusive sentinel round keeps the verdict it had instead of dropping it.
    func testAnInconclusiveSentinelRoundKeepsThePreviousVerdict() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])

        clock += 121
        SwapRouteAvailability.nearSentinels.forEach { script.set(.unknown, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
    }

    // MARK: Cancellation

    func testCancellingTheRefreshDropsTheQueuedProbes() async {
        let coins = (1...10).map { "ETH.TOKEN\($0)" }
        let map = Dictionary(uniqueKeysWithValues: coins.map { ($0.uppercased(), Set<RouteProvider>([.maya])) })
        let store = self.store!
        let probe = script.probe
        script.closeGate()

        let task = Task { @MainActor in
            await store.refresh(assets: coins, direction: .sell, capable: { map[$0.uppercased()] ?? [] }, probe: probe)
        }
        await waitUntil { self.script.calls.count == 2 }
        task.cancel()
        script.openGate()
        await task.value

        XCTAssertEqual(script.calls.count, 2, "only the two in flight were sent")
        let answered = coins.filter { store.state(of: .maya, for: $0, direction: .sell) != nil }
        XCTAssertEqual(answered.count, 2, "dropped probes left no answer behind")
    }

    /// A refresh started while a stopped one still drains waits for it instead of doing nothing.
    func testARefreshStartedDuringADrainRunsAfterIt() async {
        let store = self.store!
        let probe = script.probe
        let first: [String: Set<RouteProvider>] = ["ETH.A": [.maya], "ETH.B": [.maya], "ETH.C": [.maya]]
        script.closeGate()

        let old = Task { @MainActor in
            await store.refresh(assets: ["ETH.A", "ETH.B", "ETH.C"], direction: .sell, capable: { first[$0] ?? [] }, probe: probe)
        }
        await waitUntil { self.script.calls.count == 2 }
        old.cancel()

        let new = Task { @MainActor in
            await store.refresh(assets: ["ETH.C"], direction: .sell, capable: { first[$0] ?? [] }, probe: probe)
        }
        await Task.yield()
        script.openGate()
        await old.value
        await new.value

        let calls = script.calls(to: .maya)
        XCTAssertEqual(Set(calls.prefix(2)), ["ETH.A", "ETH.B"], "the two the old refresh had in flight")
        XCTAssertEqual(calls.dropFirst(2).map { $0 }, ["ETH.C"], "the new refresh probed ETH.C after the drain")
    }

    // MARK: Quoting

    /// A real quote only leaves out a provider on an answer that is not yet due for a re-probe.
    func testQuotingIgnoresAnswersDueForAReProbe() async {
        store.record(.halted, provider: .maya, asset: "ETH.USDT", direction: .sell)
        XCTAssertEqual(store.usableProviders(for: "ETH.USDT", capable: both, direction: .sell, freshOnly: true), [.near])

        clock += 601

        XCTAssertEqual(store.usableProviders(for: "ETH.USDT", capable: both, direction: .sell), [.near], "the picker still reads it")
        XCTAssertEqual(store.usableProviders(for: "ETH.USDT", capable: both, direction: .sell, freshOnly: true), both)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "condition never became true")
    }

    func testDirectionsAreIndependent() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]], direction: .sell)

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertNil(store.nearVerdict(for: .buy))
        XCTAssertEqual(label("AVAX.AVAX", capable: [.near], direction: .buy), .near)
    }

    /// AC-11: Buy routes through NEAR only, so a NEAR outage on Buy halts every Buy coin,
    /// also one Maya carries on Sell.
    func testNearDownOnBuyHaltsEveryBuyCoinAndMayaNeverCounts() async {
        let capable = { (asset: String, direction: SwapDirection) in
            SwapKitSwapProvider.capableProviders(
                for: asset, direction: direction, nearOnly: ["AVAX.AVAX"], mayaOnly: ["MAYA.CACAO"], both: ["ETH.USDT"]
            )
        }
        XCTAssertEqual(capable("ETH.USDT", .sell), both)
        XCTAssertEqual(capable("ETH.USDT", .buy), [.near], "Maya never counts on Buy")
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }

        let buyCoins = ["ETH.USDT", "AVAX.AVAX"]
        await store.refresh(assets: buyCoins, direction: .buy, capable: { capable($0, .buy) }, probe: script.probe)

        XCTAssertEqual(store.nearVerdict(for: .buy), .down)
        XCTAssertTrue(script.calls(to: .maya).isEmpty)
        for coin in buyCoins {
            XCTAssertTrue(store.usableProviders(for: coin, capable: capable(coin, .buy), direction: .buy).isEmpty, coin)
        }
    }

    // MARK: Answers from outside the probes

    func testARecordedAnswerChangesTheLabelAndIsReported() {
        var reported: [SwapDirection] = []
        let cancellable = store.changes.sink { reported.append($0) }
        defer { cancellable.cancel() }

        store.record(.noRoute, provider: .maya, asset: "ARB.USDT", direction: .sell)
        store.record(.noRoute, provider: .maya, asset: "ARB.USDT", direction: .sell)

        XCTAssertEqual(label("ARB.USDT", capable: both), .near)
        XCTAssertEqual(reported, [.sell], "an unchanged answer is not reported again")
    }

    /// A picker probe still in flight when the address screen records a newer answer for the same
    /// coin does not overwrite it when it returns.
    func testAProbeThatReturnsAfterANewerAnswerIsDropped() async {
        script.set(.noRoute, .maya, "ETH.USDT")
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let task = Task { @MainActor in
            await store.refresh(assets: ["ETH.USDT"], direction: .sell, capable: { _ in [.maya] }, probe: probe)
        }
        await waitUntil { self.script.calls.count == 1 }

        store.record(.available, provider: .maya, asset: "ETH.USDT", direction: .sell)
        script.openGate()
        await task.value

        XCTAssertEqual(store.state(of: .maya, for: "ETH.USDT", direction: .sell), .available)
    }

    /// A sentinel's answer overtaken by a newer one for the same coin does not count in the round:
    /// BTC's stale no-route and ETH's no-route do not declare NEAR down over BTC's newer route.
    func testASentinelAnswerOvertakenByANewerOneIsNotCounted() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let task = Task { @MainActor in
            await store.refresh(assets: ["AVAX.AVAX"], direction: .sell, capable: { _ in [.near] }, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC"] }

        store.record(.available, provider: .near, asset: "BTC.BTC", direction: .sell)
        script.openGate()
        await task.value

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(store.state(of: .near, for: "BTC.BTC", direction: .sell), .available)
    }

    /// A sentinel no-route already counted is overtaken by a route for that coin while the next
    /// sentinel is asked: the round decides from what the store holds, so NEAR is up.
    func testACountedSentinelNoRouteOvertakenLaterInTheRoundIsNotCounted() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let task = Task { @MainActor in
            await store.refresh(assets: ["AVAX.AVAX"], direction: .sell, capable: { _ in [.near] }, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC"] }
        script.openGate()
        script.closeGate()
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC", "ETH.ETH"] }
        XCTAssertEqual(store.state(of: .near, for: "BTC.BTC", direction: .sell), .noRoute, "BTC's answer is stored")

        store.record(.available, provider: .near, asset: "BTC.BTC", direction: .sell)
        script.openGate()
        await task.value

        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
        XCTAssertEqual(store.state(of: .near, for: "BTC.BTC", direction: .sell), .available)
    }

    /// A counted sentinel no-route overtaken by a halt leaves BTC and ETH settling neither outcome,
    /// so SOL is asked as the stand-in and its route decides.
    func testACountedSentinelNoRouteOvertakenByAHaltAsksTheThird() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.set(.available, .near, "SOL.SOL")
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let task = Task { @MainActor in
            await store.refresh(assets: ["AVAX.AVAX"], direction: .sell, capable: { _ in [.near] }, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC"] }
        script.openGate()
        script.closeGate()
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC", "ETH.ETH"] }

        store.record(.halted, provider: .near, asset: "BTC.BTC", direction: .sell)
        script.openGate()
        await task.value

        XCTAssertEqual(Array(script.calls(to: .near).prefix(3)), ["BTC.BTC", "ETH.ETH", "SOL.SOL"])
        XCTAssertEqual(store.nearVerdict(for: .sell), .up)
    }

    /// A coin's answer stored before the round that finds the outage is hidden by it.
    func testAnAnswerFromBeforeTheOutageRoundIsHidden() async {
        await refresh(["AVAX.AVAX": [.near]])
        XCTAssertEqual(store.state(of: .near, for: "AVAX.AVAX", direction: .sell), .available)

        clock += 601
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        await refresh(["AVAX.AVAX": [.near]])

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(store.state(of: .near, for: "AVAX.AVAX", direction: .sell), .noRoute)
    }

    /// A probe asked before the round that finds the outage, returning while the round is asking,
    /// is ordered by when it was asked: the outage hides it.
    func testAProbeAskedBeforeTheOutageRoundIsHidden() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let check = Task { @MainActor in
            await store.probeNow(asset: "AVAX.AVAX", provider: .near, direction: .sell, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["AVAX.AVAX"] }
        let round = Task { @MainActor in
            await store.refresh(assets: ["AVAX.AVAX"], direction: .sell, capable: { _ in [.near] }, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["AVAX.AVAX", "BTC.BTC"] }
        script.openGate()
        _ = await check.value
        await round.value

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(store.state(of: .near, for: "AVAX.AVAX", direction: .sell), .noRoute)
    }

    /// The same with the picker closed meanwhile: the cancelled refresh still settles the round when
    /// its last sentinel returns, and the coin's newer route stays usable.
    func testACoinRouteRecordedBeforeACancelledOutageRoundEndsStaysUsable() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let task = Task { @MainActor in
            await store.refresh(assets: ["AVAX.AVAX"], direction: .sell, capable: { _ in [.near] }, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC"] }
        script.openGate()
        script.closeGate()
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC", "ETH.ETH"] }

        store.record(.available, provider: .near, asset: "AVAX.AVAX", direction: .sell)
        clock += 1
        task.cancel()
        script.openGate()
        await task.value

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(label("AVAX.AVAX", capable: [.near]), .near)
    }

    /// A coin's own route recorded while the round that finds the outage is still asking comes after
    /// that round started: the round finishing later does not hide it.
    func testACoinRouteRecordedDuringTheOutageRoundStaysUsable() async {
        SwapRouteAvailability.nearSentinels.forEach { script.set(.noRoute, .near, $0) }
        script.closeGate()
        let store: SwapRouteAvailability = self.store
        let probe = script.probe
        let task = Task { @MainActor in
            await store.refresh(assets: ["AVAX.AVAX"], direction: .sell, capable: { _ in [.near] }, probe: probe)
        }
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC"] }
        script.openGate()
        script.closeGate()
        await waitUntil { self.script.calls(to: .near) == ["BTC.BTC", "ETH.ETH"] }

        store.record(.available, provider: .near, asset: "AVAX.AVAX", direction: .sell)
        clock += 1
        script.openGate()
        await task.value

        XCTAssertEqual(store.nearVerdict(for: .sell), .down)
        XCTAssertEqual(store.state(of: .near, for: "AVAX.AVAX", direction: .sell), .available)
        XCTAssertEqual(label("AVAX.AVAX", capable: [.near]), .near)
    }

    // MARK: Load

    func testNoMoreThanTwoProbesAreInFlight() async {
        script.holdNanoseconds = 5_000_000
        let coins = (1...10).map { "ETH.TOKEN\($0)" }
        let map = Dictionary(uniqueKeysWithValues: coins.map { ($0.uppercased(), both) })

        await store.refresh(assets: coins, direction: .sell, capable: { map[$0.uppercased()] ?? [] }, probe: script.probe)

        XCTAssertEqual(script.maxInFlight, 2)
        XCTAssertEqual(script.calls.count, 1 + 20, "the first sentinel routes, then both providers for every coin")
    }
}

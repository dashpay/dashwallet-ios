import Foundation
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
@testable import dashpay
#else
@testable import ShieldedBalanceHarness
#endif

/// Holds every `prepare()` until the test completes it, like a key build in
/// progress.
@MainActor
private final class FakeProverBackend: ShieldedProverBackend {
    var isReady = false
    private(set) var prepareCount = 0
    private var pending: [CheckedContinuation<Bool, Never>] = []

    func prepare() async -> Bool {
        prepareCount += 1
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
    }

    func finish(ready: Bool) {
        isReady = ready
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: ready) }
    }
}

@MainActor
private final class TestClock {
    var current = Date(timeIntervalSince1970: 1_000)
    func advance(milliseconds: Int) { current += TimeInterval(milliseconds) / 1_000 }
}

@MainActor
final class ShieldedProverWarmupTests: XCTestCase {
    private var backend: FakeProverBackend!
    private var clock: TestClock!
    private var conditions = ShieldedProverWarmupConditions(isLowPowerModeEnabled: false, isInForeground: true)
    private var lines: [String] = []

    override func setUp() async throws {
        backend = FakeProverBackend()
        clock = TestClock()
        conditions = ShieldedProverWarmupConditions(isLowPowerModeEnabled: false, isInForeground: true)
        lines = []
    }

    private func makeWarmup() -> ShieldedProverWarmup {
        ShieldedProverWarmup(
            backend: backend,
            conditions: { [unowned self] in self.conditions },
            now: { [unowned self] in self.clock.current },
            log: { [unowned self] in self.lines.append($0) })
    }

    /// Lets the warm-up's completion hop back onto the main actor.
    private func drain() async {
        for _ in 0..<5 { await Task.yield() }
    }

    // MARK: - Policy

    func testOnlyAPositiveShieldedBalanceJustifiesASpeculativeWarmUp() {
        XCTAssertFalse(ShieldedProverWarmupPolicy.holdsSpendableShieldedFunds(.unavailable))
        XCTAssertFalse(ShieldedProverWarmupPolicy.holdsSpendableShieldedFunds(.restored(0)))
        XCTAssertFalse(ShieldedProverWarmupPolicy.holdsSpendableShieldedFunds(.refreshed(0)))
        XCTAssertTrue(ShieldedProverWarmupPolicy.holdsSpendableShieldedFunds(.restored(1)))
        XCTAssertTrue(ShieldedProverWarmupPolicy.holdsSpendableShieldedFunds(.refreshed(50_000_000_000)))
    }

    func testSpeculativeWarmUpWaitsForForegroundAndNormalPower() {
        let normal = ShieldedProverWarmupConditions(isLowPowerModeEnabled: false, isInForeground: true)
        let lowPower = ShieldedProverWarmupConditions(isLowPowerModeEnabled: true, isInForeground: true)
        let background = ShieldedProverWarmupConditions(isLowPowerModeEnabled: false, isInForeground: false)

        XCTAssertTrue(ShieldedProverWarmupPolicy.shouldStart(.shieldedBalance, conditions: normal))
        XCTAssertFalse(ShieldedProverWarmupPolicy.shouldStart(.shieldedBalance, conditions: lowPower))
        XCTAssertFalse(ShieldedProverWarmupPolicy.shouldStart(.shieldedBalance, conditions: background))

        // A chosen route or a confirmed proof pays the build anyway.
        for trigger in [ShieldedProverWarmupTrigger.shieldedRoute, .confirmedOperation] {
            XCTAssertTrue(ShieldedProverWarmupPolicy.shouldStart(trigger, conditions: lowPower))
            XCTAssertTrue(ShieldedProverWarmupPolicy.shouldStart(trigger, conditions: background))
        }
    }

    // MARK: - Warm-up state

    func testRepeatedRequestsStartOneBuild() async {
        let warmup = makeWarmup()
        warmup.request(.shieldedBalance)
        warmup.request(.shieldedRoute)
        warmup.request(.confirmedOperation)
        await drain()
        XCTAssertEqual(backend.prepareCount, 1)
        XCTAssertFalse(warmup.isReady)

        clock.advance(milliseconds: 1_500)
        backend.finish(ready: true)
        await drain()
        XCTAssertTrue(warmup.isReady)
        XCTAssertEqual(warmup.readyAt, clock.current)
        XCTAssertEqual(lines, [
            "SHIELDED-PROVER warm-up start trigger=shielded-balance",
            "SHIELDED-PROVER warm-up ready duration_ms=1500",
        ])

        warmup.request(.shieldedRoute)
        await drain()
        XCTAssertEqual(backend.prepareCount, 1)
    }

    func testAlreadyCachedKeyStartsNothing() async {
        backend.isReady = true
        let warmup = makeWarmup()
        warmup.request(.shieldedRoute)
        await drain()
        XCTAssertEqual(backend.prepareCount, 0)
        XCTAssertTrue(warmup.isReady)
        XCTAssertTrue(lines.isEmpty)
    }

    func testDeferredSpeculativeRequestLeavesRouteRequestFree() async {
        conditions.isLowPowerModeEnabled = true
        let warmup = makeWarmup()
        warmup.request(.shieldedBalance)
        warmup.request(.shieldedBalance)
        await drain()
        XCTAssertEqual(backend.prepareCount, 0)
        XCTAssertEqual(lines, ["SHIELDED-PROVER warm-up deferred trigger=shielded-balance low_power=true foreground=true"])

        warmup.request(.shieldedRoute)
        await drain()
        XCTAssertEqual(backend.prepareCount, 1)
    }

    func testGivingUpAllowsALaterRetry() async {
        let warmup = makeWarmup()
        warmup.request(.shieldedRoute)
        await drain()
        backend.finish(ready: false)
        await drain()
        XCTAssertFalse(warmup.isReady)
        XCTAssertEqual(lines.last, "SHIELDED-PROVER warm-up gave up duration_ms=0")

        warmup.request(.shieldedRoute)
        await drain()
        XCTAssertEqual(backend.prepareCount, 2)
    }

    // MARK: - Proof timing

    func testProofTimingWhenTheKeyWasWarm() async {
        backend.isReady = true
        let warmup = makeWarmup()
        let timing = warmup.beginProofOperation(.shieldedToCore)
        XCTAssertTrue(timing.readyAtConfirm)
        clock.advance(milliseconds: 2_000)
        let value = await timing.measure { () async -> Int in
            clock.advance(milliseconds: 900)
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(backend.prepareCount, 0)
        XCTAssertEqual(lines, [
            "SHIELDED-PROVER op=shielded-to-core ready_at_confirm=true ready_at_call=true ready_after_call_ms=0 "
                + "confirm_to_call_ms=2000 call_ms=900 succeeded=true",
        ])
    }

    func testConfirmingAColdProofStartsTheBuildAndReportsTheWait() async {
        let warmup = makeWarmup()
        let timing = warmup.beginProofOperation(.shieldedToShielded)
        await drain()
        XCTAssertFalse(timing.readyAtConfirm)
        XCTAssertEqual(backend.prepareCount, 1)
        XCTAssertEqual(lines, ["SHIELDED-PROVER warm-up start trigger=confirmed-operation"])

        clock.advance(milliseconds: 1_000)
        do {
            try await timing.measure {
                clock.advance(milliseconds: 2_500)
                backend.finish(ready: true)
                await drain()
                clock.advance(milliseconds: 1_200)
                throw CancellationError()
            }
            XCTFail("measure must rethrow the call's error")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        XCTAssertEqual(lines.last,
            "SHIELDED-PROVER op=shielded-to-shielded ready_at_confirm=false ready_at_call=false ready_after_call_ms=2500 "
                + "confirm_to_call_ms=1000 call_ms=3700 succeeded=false")
    }

    func testConfirmingWithoutRunningTheCallLogsNothing() {
        backend.isReady = true
        let warmup = makeWarmup()
        _ = warmup.beginProofOperation(.platformToShielded)
        XCTAssertTrue(lines.isEmpty)
    }
}

import Foundation
import XCTest
#if canImport(dashpay)
@testable import dashpay
#else
@testable import ShieldedBalanceHarness
#endif

@MainActor
private final class RecoveryTestClock {
    var delays: [TimeInterval] = []
    var onSleep: (() -> Void)?
    private var sleepers: [CheckedContinuation<Void, Error>] = []

    func sleep(_ seconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            delays.append(seconds)
            sleepers.append(continuation)
            onSleep?()
        }
    }

    func advance() {
        let ready = sleepers
        sleepers.removeAll()
        ready.forEach { $0.resume() }
    }
}

@MainActor
final class ShieldedRecoveryControllerTests: XCTestCase {
    func testOfflinePreparesLocallyThenOnlineRefreshesOnce() async {
        let prepared = expectation(description: "prepared offline")
        let refreshed = expectation(description: "refreshed online")
        var preparations = 0
        var syncs = 0
        let controller = ShieldedRecoveryController(
            prepare: { preparations += 1; if preparations == 1 { prepared.fulfill() } },
            sync: { syncs += 1; refreshed.fulfill() },
            isSyncing: { false }, sleep: { _ in })
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        XCTAssertEqual(syncs, 0)
        controller.connectivityChanged(isOnline: true)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(syncs, 1)
        controller.stop()
    }

    func testReconnectWaitsForRunningPassAndDrainsOnePendingRefresh() async {
        let prepared = expectation(description: "prepared")
        let deferred = expectation(description: "request checked while syncing")
        let refreshed = expectation(description: "deferred refresh")
        var syncing = true
        var preparations = 0
        var syncs = 0
        let controller = ShieldedRecoveryController(
            prepare: {
                preparations += 1
                if preparations == 1 { prepared.fulfill() }
                if preparations == 2 { deferred.fulfill() }
            },
            sync: { syncs += 1; refreshed.fulfill() },
            isSyncing: { syncing }, sleep: { _ in })
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [deferred], timeout: 2)
        XCTAssertEqual(syncs, 0)
        syncing = false
        controller.syncDidFinish()
        controller.syncDidFinish()
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(syncs, 1)
        controller.stop()
    }

    func testInitializationRetriesWithBackoffAndClearsFailure() async {
        let clock = RecoveryTestClock()
        let firstRetry = expectation(description: "first backoff")
        let secondRetry = expectation(description: "second backoff")
        let restored = expectation(description: "initialization recovered")
        var attempts = 0
        clock.onSleep = {
            if clock.delays.count == 1 { firstRetry.fulfill() }
            if clock.delays.count == 2 { secondRetry.fulfill() }
        }
        let controller = ShieldedRecoveryController(
            prepare: {
                attempts += 1
                if attempts <= 2 { throw NSError(domain: "synthetic bind", code: 1) }
                restored.fulfill()
            },
            sync: { XCTFail("Offline initialization must not force network sync") },
            isSyncing: { false }, sleep: clock.sleep)
        controller.start(isForeground: true)
        await fulfillment(of: [firstRetry], timeout: 2)
        XCTAssertNotNil(controller.lastError)
        clock.advance()
        await fulfillment(of: [secondRetry], timeout: 2)
        clock.advance()
        await fulfillment(of: [restored], timeout: 2)
        XCTAssertEqual(clock.delays, [1, 2])
        XCTAssertEqual(attempts, 3)
        XCTAssertNil(controller.lastError)
        controller.stop()
    }

    func testPathFlappingCancelsOldDebounceAndCoalescesRefresh() async {
        let clock = RecoveryTestClock()
        let prepared = expectation(description: "prepared")
        let firstDebounce = expectation(description: "first online hint")
        let secondDebounce = expectation(description: "second online hint")
        let refreshed = expectation(description: "one refresh")
        var preparations = 0
        var syncs = 0
        clock.onSleep = {
            if clock.delays.count == 1 { firstDebounce.fulfill() }
            if clock.delays.count == 2 { secondDebounce.fulfill() }
        }
        let controller = ShieldedRecoveryController(
            prepare: { preparations += 1; if preparations == 1 { prepared.fulfill() } },
            sync: { syncs += 1; refreshed.fulfill() },
            isSyncing: { false }, sleep: clock.sleep)
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [firstDebounce], timeout: 2)
        controller.connectivityChanged(isOnline: false)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [secondDebounce], timeout: 2)
        clock.advance()
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(syncs, 1)
        XCTAssertEqual(clock.delays, [0.5, 0.5])
        controller.stop()
    }

    func testStopCancelsRecoveryEvenWhenPreparationIgnoresCancellation() async {
        let started = expectation(description: "preparation started")
        let returned = expectation(description: "old preparation returned")
        var continuation: CheckedContinuation<Void, Never>?
        let controller = ShieldedRecoveryController(
            prepare: {
                await withCheckedContinuation { continuation = $0; started.fulfill() }
                returned.fulfill()
            },
            sync: { XCTFail("Stopped wallet cannot start a forced pass") },
            isSyncing: { false }, sleep: { _ in })
        controller.start(isForeground: true)
        controller.connectivityChanged(isOnline: true)
        controller.request()
        await fulfillment(of: [started], timeout: 2)
        controller.stop()
        continuation?.resume()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.lastError)
    }

    func testBackgroundCancelsInitializationRetryUntilForeground() async {
        let clock = RecoveryTestClock()
        let backoff = expectation(description: "retry waiting")
        let recovered = expectation(description: "foreground retry")
        clock.onSleep = { backoff.fulfill() }
        var attempts = 0
        let controller = ShieldedRecoveryController(
            prepare: {
                attempts += 1
                if attempts == 1 { throw NSError(domain: "synthetic bind", code: 1) }
                recovered.fulfill()
            },
            sync: { XCTFail("Still offline") },
            isSyncing: { false }, sleep: clock.sleep)
        controller.start(isForeground: true)
        await fulfillment(of: [backoff], timeout: 2)
        controller.foregroundChanged(isForeground: false)
        clock.advance()
        XCTAssertEqual(attempts, 1)
        controller.foregroundChanged(isForeground: true)
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertEqual(attempts, 2)
        controller.stop()
    }
    func testRequestDuringFailedPassDrainsOnceWithoutAutomaticNetworkRetry() async {
        let prepared = expectation(description: "prepared")
        let started = expectation(description: "first pass suspended")
        let refreshed = expectation(description: "pending reconnect drained")
        var continuation: CheckedContinuation<Void, Never>?
        var preparations = 0
        var syncs = 0
        let controller = ShieldedRecoveryController(
            prepare: { preparations += 1; if preparations == 1 { prepared.fulfill() } },
            sync: {
                syncs += 1
                if syncs == 1 {
                    await withCheckedContinuation { continuation = $0; started.fulfill() }
                    throw NSError(domain: "synthetic network failure", code: 1)
                }
                refreshed.fulfill()
            },
            isSyncing: { false }, sleep: { _ in })
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [started], timeout: 2)
        controller.request()
        controller.request()
        controller.syncDidFinish()
        continuation?.resume()
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(syncs, 2)
        XCTAssertNil(controller.lastError)
        controller.stop()
    }

    func testNetworkFailureWaitsForExplicitRecoveryInsteadOfInitializationBackoff() async {
        let prepared = expectation(description: "prepared")
        let failed = expectation(description: "network pass failed")
        var preparations = 0
        var syncs = 0
        let controller = ShieldedRecoveryController(
            prepare: { preparations += 1; if preparations == 1 { prepared.fulfill() } },
            sync: {
                syncs += 1
                failed.fulfill()
                throw NSError(domain: "synthetic network failure", code: 1)
            },
            isSyncing: { false }, sleep: { seconds in
                XCTAssertEqual(seconds, 0.5, "Network failures must not use initialization backoff")
            })
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(syncs, 1)
        XCTAssertNotNil(controller.lastError)
        controller.stop()
    }

    func testQueuedRuntimeRearmCannotReviveStoppedSessionAfterRestart() async {
        let queued = expectation(description: "old recovery queued")
        let restarted = expectation(description: "new recovery prepared")
        let drained = expectation(description: "old queue operation drained")
        var continuation: CheckedContinuation<Void, Never>?
        var preparations = 0
        var controller: ShieldedRecoveryController!
        controller = ShieldedRecoveryController(
            prepare: {
                preparations += 1
                guard preparations == 1 else { restarted.fulfill(); return }
                let generation = controller.generation
                await withCheckedContinuation { continuation = $0; queued.fulfill() }
                XCTAssertFalse(controller.isCurrentSession(generation),
                               "An old runtime queue entry must not restart a stopped wallet")
                drained.fulfill()
            },
            sync: { XCTFail("Offline recovery must not sync") },
            isSyncing: { false }, sleep: { _ in })
        controller.start(isForeground: true)
        await fulfillment(of: [queued], timeout: 2)
        controller.stop()
        controller.start(isForeground: true)
        await fulfillment(of: [restarted], timeout: 2)
        continuation?.resume()
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.lastError)
        controller.stop()
        controller = nil
    }

}

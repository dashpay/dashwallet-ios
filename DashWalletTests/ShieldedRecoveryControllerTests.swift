import Foundation
import XCTest
#if canImport(dashwallet)
@testable import dashwallet
#elseif canImport(dashpay)
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
    func testCoreFailureDoesNotSchedulePreparationOrRebuildRetries() async {
        var coreReady = false
        var attempts = 0
        let prepared = expectation(description: "Core became ready")
        let controller = ShieldedRecoveryController(
            prepare: { attempts += 1; prepared.fulfill() },
            sync: { XCTFail("Offline preparation must not sync") },
            isSyncing: { false },
            canPrepare: { coreReady },
            sleep: { _ in XCTFail("Core failure must not schedule Shielded retries") })
        controller.start(isForeground: true)
        for _ in 0..<3 {
            controller.request()
            controller.foregroundChanged(isForeground: true)
            await Task.yield()
        }
        XCTAssertEqual(attempts, 0)
        XCTAssertFalse(controller.isRecovering)
        coreReady = true
        controller.request(forceSync: false)
        await fulfillment(of: [prepared], timeout: 2)
        XCTAssertEqual(attempts, 1)
        controller.stop()
    }

    func testCoreLossBeforeQueuedPreparationDoesNotRebuildRuntime() async {
        var coreReady = true
        let controller = ShieldedRecoveryController(
            prepare: { XCTFail("Queued preparation must recheck Core readiness") },
            sync: { XCTFail("No sync after Core stops") },
            isSyncing: { false },
            canPrepare: { coreReady },
            sleep: { _ in XCTFail("No retries after Core stops") })
        controller.start(isForeground: true)
        coreReady = false
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(controller.isRecovering)
        XCTAssertNil(controller.lastError)
        controller.stop()
    }

    func testAbandonedPreparationEndsQuietlyAndAllowsANewRequest() async {
        let abandoned = expectation(description: "obsolete scope abandoned")
        let prepared = expectation(description: "new request prepared")
        var attempts = 0
        let controller = ShieldedRecoveryController(
            prepare: {
                attempts += 1
                if attempts == 1 {
                    abandoned.fulfill()
                    // Scope invalidation can throw without cancelling the Task.
                    XCTAssertFalse(Task.isCancelled)
                    throw CancellationError()
                }
                prepared.fulfill()
            },
            sync: { XCTFail("Offline requests must not sync") },
            isSyncing: { false },
            sleep: { _ in XCTFail("Abandoned work must not schedule backoff") })
        controller.start(isForeground: true)
        await fulfillment(of: [abandoned], timeout: 2)
        XCTAssertNil(controller.lastError)
        XCTAssertFalse(controller.isRecovering)
        controller.request(forceSync: false)
        await fulfillment(of: [prepared], timeout: 2)
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(controller.lastError)
        controller.stop()
    }

    func testAbandonedSyncEndsQuietlyWithoutRetryingTheOldScope() async {
        let prepared = expectation(description: "prepared")
        let abandoned = expectation(description: "old sync abandoned")
        let synced = expectation(description: "new request synced")
        var preparations = 0
        var syncs = 0
        var sleeps: [TimeInterval] = []
        let controller = ShieldedRecoveryController(
            prepare: {
                preparations += 1
                if preparations == 1 { prepared.fulfill() }
            },
            sync: {
                syncs += 1
                if syncs == 1 {
                    abandoned.fulfill()
                    XCTAssertFalse(Task.isCancelled)
                    throw CancellationError()
                }
                synced.fulfill()
            },
            isSyncing: { false }, sleep: { sleeps.append($0) })
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [abandoned], timeout: 2)
        XCTAssertNil(controller.lastError)
        XCTAssertFalse(controller.isRecovering)
        XCTAssertEqual(syncs, 1)
        XCTAssertEqual(sleeps, [0.5], "Only the connectivity debounce should run")
        controller.request()
        await fulfillment(of: [synced], timeout: 2)
        XCTAssertEqual(syncs, 2)
        controller.stop()
    }

    func testFreshForegroundPreparesWithoutForcingAnotherScan() async {
        let initial = expectation(description: "initial preparation")
        let connected = expectation(description: "reconnect scan")
        let foreground = expectation(description: "fresh foreground preparation")
        let stale = expectation(description: "stale foreground scan")
        var preparations = 0
        var syncs = 0
        var shouldRefresh = false
        let controller = ShieldedRecoveryController(
            prepare: {
                preparations += 1
                if preparations == 1 { initial.fulfill() }
                if preparations == 3 { foreground.fulfill() }
            },
            sync: {
                syncs += 1
                if syncs == 1 { connected.fulfill() }
                if syncs == 2 { stale.fulfill() }
            },
            isSyncing: { false }, shouldRefreshOnForeground: { shouldRefresh },
            sleep: { _ in })
        controller.start(isForeground: true)
        await fulfillment(of: [initial], timeout: 2)
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [connected], timeout: 2)
        controller.foregroundChanged(isForeground: false)
        controller.foregroundChanged(isForeground: true)
        await fulfillment(of: [foreground], timeout: 2)
        XCTAssertEqual(syncs, 1, "A recent scan must survive a quick app switch")
        shouldRefresh = true
        controller.foregroundChanged(isForeground: false)
        controller.foregroundChanged(isForeground: true)
        await fulfillment(of: [stale], timeout: 2)
        XCTAssertEqual(syncs, 2)
        controller.stop()
    }

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

    func testBackgroundCancelsReconnectDebounceBeforePreparation() async {
        let clock = RecoveryTestClock()
        let prepared = expectation(description: "initial preparation")
        let debouncing = expectation(description: "reconnect waiting")
        var attempts = 0
        let controller = ShieldedRecoveryController(
            prepare: { attempts += 1; if attempts == 1 { prepared.fulfill() } },
            sync: { XCTFail("Background reconnect must not sync") },
            isSyncing: { false }, sleep: clock.sleep)
        controller.start(isForeground: true)
        await fulfillment(of: [prepared], timeout: 2)
        clock.onSleep = { debouncing.fulfill() }
        controller.connectivityChanged(isOnline: true)
        await fulfillment(of: [debouncing], timeout: 2)
        controller.foregroundChanged(isForeground: false)
        clock.advance()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(controller.isRecovering)
        controller.stop()
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

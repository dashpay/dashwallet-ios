//
//  SwiftDashSDKCoreLifecycleTests.swift
//  DashWalletTests
//
//  Regression coverage for SDK lifecycle and freshness policies.
//

import XCTest
@testable import dashwallet

private enum CoreLifecycleTestError: Error {
    case start
}

@MainActor
final class SwiftDashSDKCoreLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testRestartRunsExactlyStopThenStartAndResetsBusyState() async throws {
        var events: [String] = []
        var restartingStates: [Bool] = []

        try await CoreSPVRestartOperation.run(
            setRestarting: { restartingStates.append($0) },
            stop: { events.append("stop") },
            start: { events.append("start") })

        XCTAssertEqual(events, ["stop", "start"])
        XCTAssertEqual(restartingStates, [true, false])
    }

    func testRestartPropagatesStartFailureAndAlwaysResetsBusyState() async {
        var events: [String] = []
        var restartingStates: [Bool] = []

        do {
            try await CoreSPVRestartOperation.run(
                setRestarting: { restartingStates.append($0) },
                stop: { events.append("stop") },
                start: {
                    events.append("start")
                    throw CoreLifecycleTestError.start
                })
            XCTFail("Expected restart failure")
        } catch CoreLifecycleTestError.start {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(events, ["stop", "start"])
        XCTAssertEqual(restartingStates, [true, false])
    }

    func testQueuedRestartsNeverOverlap() async {
        let queue = SerialAsyncLifecycleQueue()
        var events: [String] = []
        var operationsInFlight = 0
        var maximumOperationsInFlight = 0

        func operation(_ name: String) async {
            operationsInFlight += 1
            maximumOperationsInFlight = max(maximumOperationsInFlight, operationsInFlight)
            events.append("\(name)-stop")
            await Task.yield()
            events.append("\(name)-start")
            operationsInFlight -= 1
        }

        queue.enqueue { await operation("first") }
        let second = queue.enqueue { await operation("second") }
        await second.value

        XCTAssertEqual(maximumOperationsInFlight, 1)
        XCTAssertEqual(events, [
            "first-stop", "first-start",
            "second-stop", "second-start",
        ])
    }

    func testProcessCacheReusesValuesPerNetworkAndSeparatesNetworks() {
        final class Token {}

        let cache = ProcessNetworkValueCache<Token>()
        let mainnetFirst = cache.value(for: "mainnet") { Token() }
        let mainnetSecond = cache.value(for: "mainnet") { Token() }
        let testnet = cache.value(for: "testnet") { Token() }

        XCTAssertFalse(mainnetFirst.reused)
        XCTAssertTrue(mainnetSecond.reused)
        XCTAssertFalse(testnet.reused)
        XCTAssertTrue(mainnetFirst.value === mainnetSecond.value)
        XCTAssertFalse(mainnetFirst.value === testnet.value)
    }

    func testWatchdogRefreshesOnlyAfterFullScanBecomesStale() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-89),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))

        XCTAssertTrue(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-90),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))
    }

    func testWatchdogUsesMonitoringStartUntilFirstFullScan() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: nil,
            monitoringStartedAt: now.addingTimeInterval(-89),
            isSyncing: false,
            refreshInFlight: false))

        XCTAssertTrue(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: nil,
            monitoringStartedAt: now.addingTimeInterval(-90),
            isSyncing: false,
            refreshInFlight: false))
    }

    func testForegroundRefreshSkipsRecentFullScan() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-29),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))

        XCTAssertTrue(ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-30),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: false))
    }

    func testRefreshesAreDeduplicatedAgainstActiveWork() {
        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-300),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: true,
            refreshInFlight: false))

        XCTAssertFalse(ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: now,
            lastFullScanAt: now.addingTimeInterval(-300),
            monitoringStartedAt: now.addingTimeInterval(-300),
            isSyncing: false,
            refreshInFlight: true))
    }

    func testCoreToShieldedMinimumIsFirstWholeDuffStrictlyAbovePoolFee() {
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.minimumAmountDuffs(
                poolFeeCredits: 212_851_200),
            212_852)
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.minimumAmountDuffs(
                poolFeeCredits: 212_851_000),
            212_852)
    }
}

final class JoinDashPayRegistrationPolicyTests: XCTestCase {
    func testSDKUsernameWinsWhenLegacyMirrorWasClearedByNetworkSwitch() {
        XCTAssertTrue(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: true,
                sdkUsername: "alice",
                legacyRegistrationCompleted: false,
                legacyUsername: nil))
    }

    func testLegacyMirrorRemainsACompatibleFallback() {
        XCTAssertTrue(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: true,
                sdkUsername: nil,
                legacyRegistrationCompleted: true,
                legacyUsername: "alice"))
    }

    func testIdentityWithoutOwnedUsernameStillShowsJoinFlow() {
        XCTAssertFalse(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: false,
                sdkUsername: nil,
                legacyRegistrationCompleted: false,
                legacyUsername: nil))
    }

    func testLegacyUsernameWithoutCompletionDoesNotSuppressJoinFlow() {
        XCTAssertFalse(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: true,
                sdkUsername: nil,
                legacyRegistrationCompleted: false,
                legacyUsername: "stale"))
    }

    func testLegacyMirrorCannotLeakAcrossNetworkWithoutIdentity() {
        XCTAssertFalse(
            JoinDashPayRegistrationPolicy.hasRegisteredUsername(
                hasIdentity: false,
                sdkUsername: nil,
                legacyRegistrationCompleted: true,
                legacyUsername: "testnet-alice"))
    }
}

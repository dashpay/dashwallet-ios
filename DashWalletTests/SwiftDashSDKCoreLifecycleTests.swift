//
//  SwiftDashSDKCoreLifecycleTests.swift
//  DashWalletTests
//
//  Regression coverage for Core-only SPV restart and process-lifetime
//  network-scoped runtime caching.
//

import XCTest
@testable import dashwallet

private enum CoreLifecycleTestError: Error {
    case start
}

@MainActor
final class SwiftDashSDKCoreLifecycleTests: XCTestCase {
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

    func testSameSeedIdentityRecoveryDiscoversRefreshesAndAdoptsInOneRun() async throws {
        let identityId = Data(repeating: 0x16, count: 32)
        var storedIdentityIds: [Data] = []
        var events: [String] = []

        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            localIdentityIds: { storedIdentityIds },
            discover: {
                events.append("discover")
                storedIdentityIds = [identityId]
                return [identityId]
            },
            refreshNames: { identityIds in
                XCTAssertEqual(identityIds, [identityId])
                events.append("refresh")
            },
            adopt: {
                events.append("adopt")
                return true
            })

        XCTAssertEqual(events, ["discover", "refresh", "adopt"])
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 1, identityCount: 1, adopted: true))
    }

    func testSameSeedIdentityRecoveryUsesPersistedIdentityWithoutRescanning() async throws {
        let identityId = Data(repeating: 0x17, count: 32)
        var discoveryCalls = 0
        var refreshedIdentityIds: [Data] = []

        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            localIdentityIds: { [identityId] },
            discover: {
                discoveryCalls += 1
                return []
            },
            refreshNames: { refreshedIdentityIds = $0 },
            adopt: { true })

        XCTAssertEqual(discoveryCalls, 0)
        XCTAssertEqual(refreshedIdentityIds, [identityId])
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 0, identityCount: 1, adopted: true))
    }
}

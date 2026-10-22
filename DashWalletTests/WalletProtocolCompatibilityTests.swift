import Combine
import XCTest
#if canImport(ProtocolCompatibilityHarness)
@testable import ProtocolCompatibilityHarness
#else
@testable import dashpay
#endif

private final class CompatibilityClient: WalletProtocolCompatibilityClient, @unchecked Sendable {
    private let lock = NSLock()
    private var value = WalletProtocolCompatibility(
        generation: 0, status: .unavailable, verifiedVersion: nil,
        effectiveVersion: 12, maximumSupportedVersion: 14, newerProtocolAvailable: false)

    func beginCheck() throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value = make(.checking, generation: value.generation + 1)
        return value.generation
    }

    func snapshot() throws -> WalletProtocolCompatibility {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func refresh(generation: UInt64) throws -> WalletProtocolCompatibility {
        // The production executor must keep the blocking bridge off MainActor.
        guard !Thread.isMainThread else { throw NSError(domain: "blocking-main-thread", code: 1) }
        return finish(.checked, generation: generation)
    }

    /// Emulates a verified preflight on a clone advancing the native SDK.
    func completePreflight(version: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        value = WalletProtocolCompatibility(
            generation: value.generation, status: value.status,
            verifiedVersion: version, effectiveVersion: version,
            maximumSupportedVersion: 14, newerProtocolAvailable: version > 14)
    }

    func finish(_ status: WalletProtocolCompatibility.Status, generation: UInt64, version: UInt32? = nil) -> WalletProtocolCompatibility {
        lock.lock()
        defer { lock.unlock() }
        let result = make(status, generation: generation, version: version)
        if generation == value.generation { value = result }
        return result
    }

    private func make(_ status: WalletProtocolCompatibility.Status, generation: UInt64, version: UInt32? = nil) -> WalletProtocolCompatibility {
        WalletProtocolCompatibility(
            generation: generation, status: status,
            verifiedVersion: version ?? value.verifiedVersion ?? (status == .checked ? 14 : nil),
            effectiveVersion: value.effectiveVersion, maximumSupportedVersion: 14,
            newerProtocolAvailable: (version ?? value.verifiedVersion ?? 14) > 14)
    }
}

private actor ObservationTicks {
    private var pending: [CheckedContinuation<Void, Error>] = []
    private var calls = 0

    func wait() async throws {
        try await withCheckedThrowingContinuation {
            pending.append($0)
            calls += 1
        }
    }

    func waitForCalls(_ count: Int) async {
        while calls < count { await Task.yield() }
    }

    func tick() {
        pending.removeFirst().resume()
    }
}

private actor DelayedCompatibilityChecks {
    private var continuations: [CheckedContinuation<WalletProtocolCompatibility, Error>] = []
    private var admitted = 0

    func run() async throws -> WalletProtocolCompatibility {
        try await withCheckedThrowingContinuation {
            continuations.append($0)
            admitted += 1
        }
    }

    func waitForCalls(_ count: Int) async {
        while admitted < count { await Task.yield() }
    }

    func resolve(_ result: Result<WalletProtocolCompatibility, Error>, at index: Int = 0) {
        continuations.remove(at: index).resume(with: result)
    }
}

@MainActor
final class WalletProtocolCompatibilityTests: XCTestCase {
    #if canImport(ProtocolCompatibilityHarness)
    func testBothOpenFormsRequoteAfterPreflightAdvancesVersionWithoutBanner() async {
        let host = SwiftDashSDKHost.shared
        host.reset()
        host.version = 12
        let ticks = ObservationTicks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(waitForObservation: { try await ticks.wait() })
        let runtimeID = UUID()
        await controller.attach(client: client, network: "mainnet", runtimeID: runtimeID).value
        controller.markRuntimeReady(runtimeID: runtimeID)
        let send = SendQuoteObservationHarness(controller: controller)
        let internalTransfer = InternalQuoteObservationHarness(controller: controller)
        XCTAssertEqual(send.quotedVersion, 12)
        XCTAssertEqual(internalTransfer.quotedVersion, 12)
        await ticks.waitForCalls(1)

        // A verified preflight advances the SDK independently of the explicit
        // check. No banner or banner view model exists anywhere in this test.
        host.version = 14
        client.completePreflight(version: 14)
        await ticks.tick()
        await ticks.waitForCalls(2)
        XCTAssertEqual(send.quotedVersion, 14)
        XCTAssertEqual(internalTransfer.quotedVersion, 14)
        XCTAssertEqual(send.quoteRequests, 2)
        XCTAssertEqual(internalTransfer.quoteRequests, 2)
        XCTAssertNoThrow(try host.validatePlatformOperation(send.platformPreparation!))
        XCTAssertNoThrow(try host.validatePlatformOperation(internalTransfer.platformPreparation!))

        await controller.refresh().value
        XCTAssertEqual(send.quoteRequests, 2, "Check generation alone must not invalidate the quote")
        XCTAssertEqual(internalTransfer.quoteRequests, 2)
        controller.detach()
        await ticks.tick()
    }
    #endif

    func testRuntimePublishesPreflightVersionWithoutMountedBanner() async {
        let ticks = ObservationTicks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(waitForObservation: { try await ticks.wait() })
        let runtimeID = UUID()
        await controller.attach(client: client, network: "mainnet", runtimeID: runtimeID).value
        controller.markRuntimeReady(runtimeID: runtimeID)
        await ticks.waitForCalls(1)
        XCTAssertEqual(controller.snapshot?.effectiveVersion, 12)

        let changed = expectation(description: "Open form receives the effective-version change without a banner")
        let subscription = controller.$snapshot.compactMap { $0?.effectiveVersion }
            .removeDuplicates().filter { $0 == 14 }.sink { _ in changed.fulfill() }
        client.completePreflight(version: 14)
        await ticks.tick()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(controller.snapshot?.effectiveVersion, 14)
        XCTAssertEqual(try? client.snapshot().generation, 1, "Observation must not issue another network check")
        await ticks.waitForCalls(2)
        controller.detach()
        await ticks.tick()
        subscription.cancel()
    }

    func testDetachedObserverCannotSampleReplacementRuntime() async {
        let ticks = ObservationTicks()
        let controller = WalletProtocolCompatibilityController(waitForObservation: { try await ticks.wait() })
        await controller.attach(client: CompatibilityClient(), network: "mainnet", runtimeID: UUID()).value
        await ticks.waitForCalls(1)
        let replacement = CompatibilityClient()
        await controller.attach(client: replacement, network: "mainnet", runtimeID: UUID()).value
        await ticks.waitForCalls(2)
        replacement.completePreflight(version: 14)
        await ticks.tick() // The cancelled old runtime's outstanding timer.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(controller.snapshot?.effectiveVersion, 12)
        await ticks.tick()
        await ticks.waitForCalls(3)
        XCTAssertEqual(controller.snapshot?.effectiveVersion, 14)
        controller.detach()
        await ticks.tick()
        XCTAssertNil(controller.snapshot)
    }

    func testBannerDistinguishesUnavailableFromUnsupportedAndAllowsCore() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController()
        let model = ProtocolCompatibilityBannerViewModel(controller: controller)
        await controller.attach(client: client, network: "testnet", runtimeID: UUID()).value
        XCTAssertNil(model.message)
        _ = client.finish(.unavailable, generation: 1)
        controller.sample()
        XCTAssertEqual(model.snapshot?.status, .unavailable)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.message?.contains("newer protocol") == true)
        _ = client.finish(.checked, generation: 1, version: 15)
        controller.sample()
        XCTAssertEqual(model.snapshot?.verifiedVersion, 15)
        XCTAssertTrue(model.message?.contains("newer protocol") == true)
        #if TESTFLIGHT
        XCTAssertNil(model.updateURL)
        XCTAssertTrue(model.message?.contains("TestFlight") == true)
        #else
        XCTAssertEqual(model.updateURL?.host, "apps.apple.com")
        #endif
    }

    func testRefreshIsInformationalAndCoalescesRequests() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let task = controller.attach(client: client, network: "testnet", runtimeID: UUID())
        XCTAssertEqual(controller.snapshot?.status, .checking)
        let repeated = controller.refresh()
        await delayed.waitForCalls(1)
        await delayed.resolve(.success(client.finish(.checked, generation: 1)))
        await task.value
        await repeated.value
        XCTAssertEqual(controller.snapshot?.status, .checked)
        XCTAssertEqual(try client.snapshot().generation, 1)
    }

    func testForegroundJoinsPendingCheckWithoutDelayingRuntimeReadiness() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let id = UUID()
        let initial = controller.attach(client: client, network: "testnet", runtimeID: id)
        controller.markRuntimeReady(runtimeID: id)
        XCTAssertTrue(controller.isRuntimeReady)
        await delayed.waitForCalls(1)
        let foreground = controller.willEnterForeground()
        XCTAssertEqual(try client.snapshot().generation, 1)
        await delayed.resolve(.success(client.finish(.checked, generation: 1)))
        await initial.value
        await foreground.value
        XCTAssertEqual(controller.snapshot?.status, .checked)
    }

    func testOldSuccessCannotPublishIntoReplacementOnSameNetwork() async {
        let delayed = DelayedCompatibilityChecks()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let old = CompatibilityClient()
        let first = controller.attach(client: old, network: "testnet", runtimeID: UUID())
        await delayed.waitForCalls(1)
        let new = CompatibilityClient()
        let replacementID = UUID()
        let second = controller.attach(client: new, network: "testnet", runtimeID: replacementID)
        await delayed.waitForCalls(2)
        await delayed.resolve(.success(old.finish(.checked, generation: 1)))
        await first.value
        XCTAssertEqual(controller.runtimeID, replacementID)
        XCTAssertEqual(controller.snapshot?.status, .checking)
        await delayed.resolve(.success(new.finish(.checked, generation: 1)))
        await second.value
        XCTAssertEqual(controller.snapshot?.status, .checked)
    }

    func testOldFailureCannotClearNewRuntimeAndABAChangesRemainScoped() async {
        let delayed = DelayedCompatibilityChecks()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let first = controller.attach(client: CompatibilityClient(), network: "mainnet", runtimeID: UUID())
        await delayed.waitForCalls(1)
        let second = controller.attach(client: CompatibilityClient(), network: "testnet", runtimeID: UUID())
        await delayed.waitForCalls(2)
        let client = CompatibilityClient()
        let third = controller.attach(client: client, network: "mainnet", runtimeID: UUID())
        await delayed.waitForCalls(3)
        await delayed.resolve(.success(client.finish(.checked, generation: 1)), at: 2)
        await third.value
        await delayed.resolve(.failure(NSError(domain: "offline", code: 1)))
        await first.value
        await delayed.resolve(.failure(NSError(domain: "offline", code: 2)))
        await second.value
        XCTAssertEqual(controller.network, "mainnet")
        XCTAssertEqual(controller.snapshot?.status, .checked)
    }

    func testFailureLeavesBindingUsableAndManualRetryRestoresCompatibility() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let id = UUID()
        let first = controller.attach(client: client, network: "testnet", runtimeID: id)
        await delayed.waitForCalls(1)
        await delayed.resolve(.failure(NSError(domain: "offline", code: 1)))
        await first.value
        XCTAssertEqual(controller.snapshot?.status, .unavailable)
        XCTAssertEqual(controller.runtimeID, id)
        let retry = controller.refresh()
        await delayed.waitForCalls(2)
        await delayed.resolve(.success(client.finish(.checked, generation: 2)))
        await retry.value
        XCTAssertEqual(controller.snapshot?.status, .checked)
    }

    func testForegroundStartsAnInformationalCheck() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController()
        await controller.attach(client: client, network: "mainnet", runtimeID: UUID()).value
        XCTAssertEqual(controller.snapshot?.status, .checked)
        let task = controller.willEnterForeground()
        XCTAssertEqual(controller.snapshot?.status, .checking)
        XCTAssertEqual(try client.snapshot().generation, 2)
        await task.value
        XCTAssertEqual(controller.snapshot?.status, .checked)
    }

    func testDetachDiscardsCompletionWithoutChangingSDK() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let task = controller.attach(client: client, network: "testnet", runtimeID: UUID())
        await delayed.waitForCalls(1)
        controller.detach()
        XCTAssertEqual(try client.snapshot().generation, 1)
        await delayed.resolve(.success(client.finish(.checked, generation: 1)))
        await task.value
        XCTAssertNil(controller.snapshot)
        XCTAssertNil(controller.runtimeID)
    }

    func testRefreshCompletionUsesNewestAuthoritativeSnapshot() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, generation in
            let completed = client.finish(.checked, generation: generation)
            _ = client.finish(.checked, generation: generation, version: 15)
            return completed
        })
        await controller.attach(client: client, network: "testnet", runtimeID: UUID()).value
        XCTAssertEqual(controller.snapshot?.verifiedVersion, 15)
    }

    func testRuntimeReadinessCannotBePublishedByObsoleteRuntime() async {
        let controller = WalletProtocolCompatibilityController()
        let id = UUID()
        await controller.attach(client: CompatibilityClient(), network: "testnet", runtimeID: id).value
        XCTAssertFalse(controller.isRuntimeReady)
        controller.markRuntimeReady(runtimeID: UUID())
        XCTAssertFalse(controller.isRuntimeReady)
        controller.markRuntimeReady(runtimeID: id)
        XCTAssertTrue(controller.isRuntimeReady)
        controller.detach()
        XCTAssertFalse(controller.isRuntimeReady)
    }

    func testLocalSnapshotObservesUnsupportedVersionWithoutRefresh() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController()
        await controller.attach(client: client, network: "testnet", runtimeID: UUID()).value
        _ = client.finish(.checked, generation: 1, version: 15)
        controller.sample()
        XCTAssertEqual(controller.snapshot?.verifiedVersion, 15)
        XCTAssertEqual(controller.snapshot?.verifiedVersion, 15)
        XCTAssertEqual(try client.snapshot().generation, 1)
    }
    func testCheckingAndFailureAreSilentWithoutNewerEvidence() async {
        let delayed = DelayedCompatibilityChecks()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let model = ProtocolCompatibilityBannerViewModel(controller: controller)
        let id = UUID()
        let task = controller.attach(client: CompatibilityClient(), network: "testnet", runtimeID: id)
        controller.markRuntimeReady(runtimeID: id)
        XCTAssertNil(model.message)
        await delayed.waitForCalls(1)
        await delayed.resolve(.failure(NSError(domain: "offline", code: 1)))
        await task.value
        XCTAssertNil(model.message)
        XCTAssertTrue(controller.isRuntimeReady)
    }

    func testFailedRefreshPreservesVerifiedNewerProtocolNotice() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController()
        let model = ProtocolCompatibilityBannerViewModel(controller: controller)
        await controller.attach(client: client, network: "testnet", runtimeID: UUID()).value
        _ = client.finish(.checked, generation: 1, version: 15)
        controller.sample()
        _ = client.finish(.unavailable, generation: 1)
        controller.sample()
        XCTAssertNotNil(model.message)
        XCTAssertEqual(controller.snapshot?.status, .unavailable)
    }

}

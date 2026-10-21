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
        effectiveVersion: 12, maximumSupportedVersion: 14)

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
        return finish(.supported, generation: generation)
    }

    func finish(_ status: WalletProtocolCompatibility.Status, generation: UInt64) -> WalletProtocolCompatibility {
        lock.lock()
        defer { lock.unlock() }
        let result = make(status, generation: generation)
        if generation == value.generation { value = result }
        return result
    }

    private func make(_ status: WalletProtocolCompatibility.Status, generation: UInt64) -> WalletProtocolCompatibility {
        WalletProtocolCompatibility(
            generation: generation, status: status,
            verifiedVersion: status == .unsupported ? 15 : (status == .supported ? 14 : nil),
            effectiveVersion: 14, maximumSupportedVersion: 14)
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
    func testBannerDistinguishesUnavailableFromUnsupportedAndAllowsCore() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController()
        let model = ProtocolCompatibilityBannerViewModel(controller: controller)
        await controller.attach(client: client, network: "testnet", runtimeID: UUID()).value
        XCTAssertNil(model.message)
        _ = client.finish(.unavailable, generation: 1)
        controller.sample()
        XCTAssertEqual(model.snapshot?.status, .unavailable)
        XCTAssertTrue(model.message?.contains("Core") == true)
        XCTAssertFalse(model.message?.contains("newer version") == true)
        _ = client.finish(.unsupported, generation: 1)
        controller.sample()
        XCTAssertEqual(model.snapshot?.status, .unsupported)
        XCTAssertTrue(model.message?.contains("newer version") == true)
        #if TESTFLIGHT
        XCTAssertNil(model.updateURL)
        XCTAssertTrue(model.message?.contains("TestFlight") == true)
        #else
        XCTAssertEqual(model.updateURL?.host, "apps.apple.com")
        #endif
    }

    func testRefreshClosesGateSynchronouslyAndCoalescesRequests() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let task = controller.attach(client: client, network: "testnet", runtimeID: UUID())
        XCTAssertEqual(controller.snapshot?.status, .checking)
        let repeated = controller.refresh()
        await delayed.waitForCalls(1)
        await delayed.resolve(.success(client.finish(.supported, generation: 1)))
        await task.value
        await repeated.value
        XCTAssertEqual(controller.snapshot?.status, .supported)
        XCTAssertEqual(try client.snapshot().generation, 1)
    }

    func testForegroundSupersedesPendingNativeResult() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let initial = controller.attach(client: client, network: "testnet", runtimeID: UUID())
        await delayed.waitForCalls(1)
        let preForegroundResult = client.finish(.supported, generation: 1)
        let foreground = controller.willEnterForeground()
        XCTAssertEqual(controller.snapshot?.status, .checking)
        XCTAssertEqual(try client.snapshot().generation, 2)
        await delayed.waitForCalls(2)
        await delayed.resolve(.success(preForegroundResult))
        await initial.value
        XCTAssertEqual(controller.snapshot?.status, .checking)
        await delayed.resolve(.success(client.finish(.supported, generation: 2)))
        await foreground.value
        XCTAssertEqual(controller.snapshot?.status, .supported)
        XCTAssertEqual(controller.snapshot?.generation, 2)
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
        await delayed.resolve(.success(old.finish(.supported, generation: 1)))
        await first.value
        XCTAssertEqual(controller.runtimeID, replacementID)
        XCTAssertEqual(controller.snapshot?.status, .checking)
        await delayed.resolve(.success(new.finish(.supported, generation: 1)))
        await second.value
        XCTAssertEqual(controller.snapshot?.status, .supported)
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
        await delayed.resolve(.success(client.finish(.supported, generation: 1)), at: 2)
        await third.value
        await delayed.resolve(.failure(NSError(domain: "offline", code: 1)))
        await first.value
        await delayed.resolve(.failure(NSError(domain: "offline", code: 2)))
        await second.value
        XCTAssertEqual(controller.network, "mainnet")
        XCTAssertEqual(controller.snapshot?.status, .supported)
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
        await delayed.resolve(.success(client.finish(.supported, generation: 2)))
        await retry.value
        XCTAssertEqual(controller.snapshot?.status, .supported)
    }

    func testForegroundInvalidatesPriorSuccessBeforeAwait() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController()
        await controller.attach(client: client, network: "mainnet", runtimeID: UUID()).value
        XCTAssertEqual(controller.snapshot?.status, .supported)
        let task = controller.willEnterForeground()
        XCTAssertEqual(controller.snapshot?.status, .checking)
        XCTAssertEqual(try client.snapshot().generation, 2)
        await task.value
        XCTAssertEqual(controller.snapshot?.status, .supported)
    }

    func testDetachInvalidatesNativeAdmissionAndDiscardsCompletion() async {
        let delayed = DelayedCompatibilityChecks()
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, _ in try await delayed.run() })
        let task = controller.attach(client: client, network: "testnet", runtimeID: UUID())
        await delayed.waitForCalls(1)
        controller.detach()
        XCTAssertEqual(try client.snapshot().generation, 2)
        await delayed.resolve(.success(client.finish(.supported, generation: 1)))
        await task.value
        XCTAssertNil(controller.snapshot)
        XCTAssertNil(controller.runtimeID)
    }

    func testRefreshCompletionUsesNewestAuthoritativeSnapshot() async {
        let client = CompatibilityClient()
        let controller = WalletProtocolCompatibilityController(execute: { _, generation in
            let completed = client.finish(.supported, generation: generation)
            _ = client.finish(.unsupported, generation: generation)
            return completed
        })
        await controller.attach(client: client, network: "testnet", runtimeID: UUID()).value
        XCTAssertEqual(controller.snapshot?.status, .unsupported)
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
        _ = client.finish(.unsupported, generation: 1)
        controller.sample()
        XCTAssertEqual(controller.snapshot?.status, .unsupported)
        XCTAssertEqual(controller.snapshot?.verifiedVersion, 15)
        XCTAssertEqual(try client.snapshot().generation, 1)
    }
}

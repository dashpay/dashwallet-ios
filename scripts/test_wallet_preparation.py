#!/usr/bin/env python3
"""Exercise wallet-opening state and safe diagnostics without the legacy app test target."""
from pathlib import Path
import os
import subprocess
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="wallet-preparation-tests-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "WalletPreparationHarness"
    tests = package / "Tests" / "WalletPreparationHarnessTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    for name in ("WalletLifecycleTransitionState", "WalletPreparationFailure", "WalletLocalStoreResetter"):
        source = repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK" / f"{name}.swift"
        test = repository / "DashWalletTests" / f"{name}Tests.swift"
        (sources / source.name).symlink_to(source)
        (tests / test.name).symlink_to(test)
    # Only unrelated app dependencies are substituted; state and diagnostics
    # are the production files, including their real Combine publishers.
    (sources / "AppDependencies.swift").write_text('''
enum WalletEnvironment { enum NetworkKind { case mainnet, testnet, devnet } }
enum DWLogger { static func log(_ message: String) {} }
@MainActor final class SwiftDashSDKSPVCoordinator {
    static let shared = SwiftDashSDKSPVCoordinator()
    var preparations = 0
    func prepareForNetworkSwitch() { preparations += 1 }
}
@MainActor final class PlatformAddressSyncCoordinator {
    static let shared = PlatformAddressSyncCoordinator()
    var preparations = 0
    func prepareForNetworkSwitch() { preparations += 1 }
}
''')
    # Exercise the real automatic entry points and serial queue, substituting
    # only SDK bring-up. This catches guards placed before enqueueing instead
    # of at execution, as well as the separate BGAppRefresh entry point.
    runtime = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKWalletRuntime.swift").read_text()
    background = (repository / "DashWallet/Sources/Infrastructure/Notifications/BackgroundRefreshCoordinator.swift").read_text()

    def declaration(source, start):
        offset = source.index(start)
        opening = source.index("{", offset)
        # Match the body, including nested closures (none of these declarations
        # contain braces in string literals).
        depth = 1
        closing = opening + 1
        while depth:
            depth += (source[closing] == "{") - (source[closing] == "}")
            closing += 1
        return source[offset:closing]

    methods = "\n".join(declaration(runtime, start).replace("private func", "func", 1) for start in (
        "    enum RefreshTrigger: String {",
        "    func retryWalletPreparation() async {",
        "    enum LocalStoreResetOutcome",
        "    func resetLocalStoresAndRetry(",
        "    private func enqueueRefresh(trigger:",
        "    private func handleObservedNetworkChange()",
        "    private func enqueueAwaitable(_ op:",
    ))
    # Its closure default contains braces before the method body.
    rearm_start = runtime.index("    func rearmPlatformSync(")
    rearm_end = runtime.index("\n    /// Awaitable counterpart", rearm_start)
    methods += "\n" + runtime[rearm_start:rearm_end]
    (sources / "AutomaticPreparation.swift").write_text(
        "import Foundation\n@MainActor\n" + declaration(runtime, "final class SerialAsyncLifecycleQueue {")
        + "\n" + declaration(background, "struct BackgroundRefreshStartGate {")
        + "\n@MainActor enum BackgroundRefreshCoordinator {\n"
        + declaration(background, "    static func defaultRuntimeStart(") + "\n}\n"
        + '''
@MainActor final class SwiftDashSDKWalletRuntime {
    static let shared = SwiftDashSDKWalletRuntime()
    let lifecycleQueue = SerialAsyncLifecycleQueue()
    var refreshCalls = 0
    /// Order of the reset operation's steps, for the ordering assertions.
    var events: [String] = []
    func enqueue(_ op: @escaping @MainActor () async -> Void) { lifecycleQueue.enqueue(op) }
    func drain() async { await lifecycleQueue.enqueue {}.value }
    func refresh(trigger: RefreshTrigger) async {
        refreshCalls += 1
        events.append("refresh")
        try? await WalletLifecycleTransitionState.shared.prepareWallet {} failure: { _ in nil }
    }
    func resolveCurrentNetwork() -> Result<WalletEnvironment.NetworkKind, NSError> { .success(.testnet) }
    func isCoreRuntimeReady(for network: WalletEnvironment.NetworkKind) -> Bool {
        WalletLifecycleTransitionState.shared.phase == .idle
    }
    func fullReset(lastError: String?, forWipe: Bool) async { events.append("fullReset") }
    func dropLocalStoreDerivedState() { events.append("drop") }
    func clearLocalStoreMaintenanceFlags() { events.append("flags") }
    func selectSolePersistedNetworkIfNeeded(currentNetwork: WalletEnvironment.NetworkKind) -> Bool {
        events.append("soleNetwork")
        return false
    }
    func publishActiveWalletDidChange(reason: String) { events.append("publish") }
''' + methods + "\n}\n")
    (tests / "AutomaticPreparationTests.swift").write_text(r'''
import XCTest
@testable import WalletPreparationHarness

/// Stands in for `WalletLocalStoreResetter`: records the call in the
/// runtime's event order and throws on request.
final class FakeResetter: WalletLocalStoreResetting, @unchecked Sendable {
    var error: WalletLocalStoreResetError?
    var calls = 0
    func resetAllScopes() async throws -> WalletLocalStoreResetReport {
        calls += 1
        await MainActor.run { SwiftDashSDKWalletRuntime.shared.events.append("delete") }
        if let error { throw error }
        return WalletLocalStoreResetReport(removed: [.init(root: "Platform", scope: "testnet")])
    }
}

@MainActor final class AutomaticPreparationTests: XCTestCase {
    let state = WalletLifecycleTransitionState.shared
    let runtime = SwiftDashSDKWalletRuntime.shared
    override func setUp() async throws {
        await runtime.drain()
        state.finish()
        runtime.refreshCalls = 0
        runtime.events = []
        SwiftDashSDKSPVCoordinator.shared.preparations = 0
        PlatformAddressSyncCoordinator.shared.preparations = 0
    }
    override func tearDown() async throws {
        await runtime.drain()
        state.finish()
    }
    func failOpen() async {
        do {
            try await state.prepareWallet { throw NSError(domain: NSCocoaErrorDomain, code: 134100) }
                failure: { WalletPreparationFailure(error: $0) }
            XCTFail("Expected database-open failure")
        } catch {}
    }
    func testAllQueuedNotificationsPreserveFailureAndDiagnostic() async {
        for trigger: SwiftDashSDKWalletRuntime.RefreshTrigger in [
            .startIfReady, .walletMaterialChanged, .networkDidChange, .walletDidChange, .walletRowsChanged
        ] {
            // Failure happens ahead of the notification inside the same queue.
            state.finish()
            runtime.enqueue { await self.failOpen() }
            runtime.enqueueRefresh(trigger: trigger)
            await runtime.drain()
            guard case let .failedWalletOpen(detail) = state.phase else { return XCTFail("Lost failure") }
            XCTAssertEqual(state.preparationFailure, detail)
            XCTAssertEqual(runtime.refreshCalls, 0, "Automatic trigger: \(trigger)")
        }
    }
    func testNetworkNotificationAfterFailedOpenDoesNotDetachOrRefresh() async {
        await failOpen()
        let failure = state.preparationFailure
        runtime.handleObservedNetworkChange()
        await runtime.drain()
        XCTAssertEqual(SwiftDashSDKSPVCoordinator.shared.preparations, 0)
        XCTAssertEqual(PlatformAddressSyncCoordinator.shared.preparations, 0)
        XCTAssertEqual(runtime.refreshCalls, 0)
        XCTAssertEqual(state.preparationFailure, failure)
    }
    func testNormalNetworkNotificationStillClearsMirrorsBeforeQueuedRefresh() async {
        runtime.handleObservedNetworkChange()
        XCTAssertEqual(SwiftDashSDKSPVCoordinator.shared.preparations, 1)
        XCTAssertEqual(PlatformAddressSyncCoordinator.shared.preparations, 1)
        XCTAssertEqual(runtime.refreshCalls, 0)
        await runtime.drain()
        XCTAssertEqual(runtime.refreshCalls, 1)
    }
    func testNetworkNotificationStillRespectsFailureAheadInQueue() async {
        runtime.enqueue { await self.failOpen() }
        runtime.handleObservedNetworkChange()
        await runtime.drain()
        XCTAssertEqual(runtime.refreshCalls, 0)
        XCTAssertNotNil(state.preparationFailure)
    }
    func testBackgroundRechecksFailureAfterWaitingForQueue() async {
        runtime.enqueue { await self.failOpen() }
        let ready = await BackgroundRefreshCoordinator.defaultRuntimeStart(while: .init(isWanted: { true }))
        XCTAssertFalse(ready)
        XCTAssertEqual(runtime.refreshCalls, 0)
        XCTAssertNotNil(state.preparationFailure)
    }
    func testExpiredBackgroundStartIsStillRejected() async {
        var wanted = true
        runtime.enqueue { wanted = false }
        _ = await BackgroundRefreshCoordinator.defaultRuntimeStart(while: .init(isWanted: { wanted }))
        XCTAssertEqual(runtime.refreshCalls, 0)
    }
    func testOrdinaryBackgroundStartStillWorks() async {
        let ready = await BackgroundRefreshCoordinator.defaultRuntimeStart(while: .init(isWanted: { true }))
        XCTAssertTrue(ready)
        XCTAssertEqual(runtime.refreshCalls, 1)
    }
    func testResetSkipsWhenNoFailureIsShowing() async throws {
        let resetter = FakeResetter()
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(runtime.refreshCalls, 0)
        XCTAssertEqual(runtime.events, [])
    }
    func testResetSkipsStorageFailures() async throws {
        do {
            try await state.prepareWallet { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
                failure: { WalletPreparationFailure(error: $0) }
        } catch {}
        let resetter = FakeResetter()
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(resetter.calls, 0)
        guard case .failedWalletOpen = state.phase else { return XCTFail("The card must stay") }
    }
    func testResetOrdersTeardownDropFlagsDeleteRefreshThenPublish() async throws {
        await failOpen()
        runtime.events = []
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: FakeResetter())
        XCTAssertEqual(outcome, .reset)
        XCTAssertEqual(runtime.events, ["fullReset", "drop", "flags", "delete", "soleNetwork", "refresh", "publish"])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
    }
    func testResetFailsClosedWhenDeletionFails() async throws {
        await failOpen()
        let failure = state.preparationFailure
        let resetter = FakeResetter()
        resetter.error = .removalFailed(root: "Shielded", scope: "testnet", code: "NSCocoaErrorDomain:513")
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Expected the deletion error")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, resetter.error)
        }
        XCTAssertEqual(runtime.refreshCalls, 0)
        XCTAssertEqual(state.preparationFailure, failure)
        guard case .failedWalletOpen = state.phase else { return XCTFail("The card must stay") }
    }
    func testQueuedRetryAheadOfResetMakesItSkip() async throws {
        await failOpen()
        let resetter = FakeResetter()
        runtime.enqueue { await self.runtime.refresh(trigger: .startIfReady) }
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(state.phase, .idle)
    }
    func testExplicitRetryAndSyncNowCanStillRecover() async {
        await failOpen()
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
        await failOpen()
        await runtime.rearmPlatformSync()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
        XCTAssertEqual(runtime.refreshCalls, 2)
    }
}
''')
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "WalletPreparationHarness", platforms: [.macOS("15.0")], targets: [
    .target(name: "WalletPreparationHarness"),
    .testTarget(name: "WalletPreparationHarnessTests", dependencies: ["WalletPreparationHarness"])
])
''')
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(package / "modules")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(package / "modules")
    subprocess.run(["xcrun", "swift", "test", "--package-path", str(package),
                    "--scratch-path", str(package / ".build"), "--cache-path", str(package / "cache"),
                    "--config-path", str(package / "configuration"), "--security-path", str(package / "security"),
                    "--disable-sandbox"], check=True, env=environment)

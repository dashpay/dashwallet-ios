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
@MainActor final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    var suspended = false
    var validationError: Error?
    var releaseError: Error?
    func validateLocalStoreReset() throws {
        if let validationError { throw validationError }
    }
    func waitForLocalStoreRelease() async throws {
        if let releaseError { throw releaseError }
    }
    func suspendModelContainerOpens() async { suspended = true }
    func resumeModelContainerOpens() { suspended = false }
}
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

    host = (repository / "DashWallet/Sources/Infrastructure/SwiftDashSDK/SwiftDashSDKHost.swift").read_text()
    # Run the real startup/recovery control flow against a persister that can
    # fail one wallet creation. A fresh host/manager reads the same rows and
    # real on-disk recovery marker, reproducing the next-launch boundary.
    recovery_methods = "\n".join(declaration(host, start).replace("private func", "func", 1) for start in (
        "    func start(network:",
        "    private func loadPersistedWallet(",
        "    private func resolveActiveWallet(",
        "    private func registryNetworkKind(",
        "    private func recoverPersistedWallet(",
        "    func validateLocalStoreReset()",
    ))
    (sources / "HostRecoveryHarness.swift").write_text(r'''
import Foundation
import CoreFoundation
import OSLog
enum Network: String {
    case mainnet, testnet, devnet, regtest
    var networkName: String { rawValue }
}
struct ManagedPlatformWallet { let walletId: Data }
extension WalletEnvironment {
    static var active: [NetworkKind: Data] = [:]
    static func activeWalletId(for kind: NetworkKind) -> Data? { active[kind] }
    static func setActiveWalletId(_ id: Data, for kind: NetworkKind) { active[kind] = id }
}
@MainActor final class PlatformWalletManager {
    static var rows: [Data: ManagedPlatformWallet] = [:]
    static var failingMnemonic: String?
    static var createAttempts: [String] = []
    static var shutdowns = 0
    var wallets: [Data: ManagedPlatformWallet] = [:]
    var firstWallet: ManagedPlatformWallet? { wallets.values.first }
    func loadFromPersistor() async throws -> [ManagedPlatformWallet] {
        wallets = Self.rows
        return Array(wallets.values)
    }
    func createWallet(mnemonic: String, network: Network, name: String,
                      createDefaultAccounts: Bool, birthHeight: UInt32) throws -> ManagedPlatformWallet {
        Self.createAttempts.append(mnemonic)
        if mnemonic == Self.failingMnemonic { throw NSError(domain: "InjectedWrite", code: 1) }
        let wallet = ManagedPlatformWallet(walletId: Data(mnemonic.utf8))
        wallets[wallet.walletId] = wallet
        Self.rows[wallet.walletId] = wallet
        return wallet
    }
    func deleteWallet(walletId: Data) throws { wallets[walletId] = nil; Self.rows[walletId] = nil }
    func shutdown() async { Self.shutdowns += 1 }
}
@MainActor final class HostRecoveryHarness {
    static let logger = Logger(subsystem: "wallet-preparation-tests", category: "recovery")
    enum HostError: Error { case walletNotFound(Network), walletBootstrapFailed(Error), mnemonicRoundTripMismatch, invalidMnemonic }
    struct RuntimeHandles { let manager: PlatformWalletManager; let network: Network }
    static var directory: URL!
    static var unreadableKeychain = false
    static var invalidMaterial = false
    var manager: PlatformWalletManager?
    var wallet: ManagedPlatformWallet?
    var runningNetwork: Network?
    var hasConfiguredStoreRuntime = false
    func buildRuntime(for network: Network) async throws -> RuntimeHandles {
        hasConfiguredStoreRuntime = true
        return .init(manager: .init(), network: network)
    }
    func publish(handles: RuntimeHandles, wallet: ManagedPlatformWallet) {
        manager = handles.manager; self.wallet = wallet; runningNetwork = handles.network
    }
    func provisionDevnetWallets(handles: RuntimeHandles) async -> ManagedPlatformWallet? { nil }
    func unlockDashPayContactCrypto(manager: PlatformWalletManager, wallet: ManagedPlatformWallet) {}
    static func strictlyPersistedMnemonics() throws -> [(walletId: Data, mnemonic: String)] {
        if unreadableKeychain { throw NSError(domain: "InjectedKeychain", code: 1) }
        return ["wallet-a", "wallet-b"].map { (Data($0.utf8), $0) }
    }
    static func persistedSDKWalletNetworks(in entries: [(walletId: Data, mnemonic: String)]) throws -> Set<Network> {
        if invalidMaterial { throw HostError.invalidMnemonic }
        return [.mainnet]
    }
    static func recoverablePersistedMnemonics(_ entries: [(walletId: Data, mnemonic: String)],
                                             for network: Network) -> [(walletId: Data, mnemonic: String)] { entries }
    static func importedWalletBirthHeight(for network: Network) -> UInt32 { 200000 }
    func localStoreRecovery(for network: Network) throws -> WalletLocalStoreRecovery {
        WalletLocalStoreRecovery(directory: Self.directory)
    }
''' + recovery_methods + "\n}\n")
    (tests / "HostRecoveryTests.swift").write_text(r'''
import XCTest
@testable import WalletPreparationHarness
@MainActor final class HostRecoveryTests: XCTestCase {
    override func setUp() async throws {
        HostRecoveryHarness.directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: HostRecoveryHarness.directory, withIntermediateDirectories: true)
        HostRecoveryHarness.unreadableKeychain = false
        HostRecoveryHarness.invalidMaterial = false
        PlatformWalletManager.rows = [:]
        PlatformWalletManager.failingMnemonic = nil
        PlatformWalletManager.createAttempts = []
        PlatformWalletManager.shutdowns = 0
        WalletEnvironment.active = [:]
    }
    override func tearDown() async throws {
        try FileManager.default.removeItem(at: HostRecoveryHarness.directory)
    }
    func testPartialRecoveryFailsThenNextLaunchCreatesOnlyMissingWallet() async throws {
        PlatformWalletManager.failingMnemonic = "wallet-b"
        let first = HostRecoveryHarness()
        do {
            _ = try await first.start(network: .mainnet)
            XCTFail("One restored wallet must not mask another's failure")
        } catch {}
        XCTAssertNil(first.wallet)
        XCTAssertEqual(PlatformWalletManager.rows.count, 1)
        XCTAssertEqual(PlatformWalletManager.shutdowns, 1)
        XCTAssertTrue(try first.localStoreRecovery(for: .mainnet).isPending())
        PlatformWalletManager.failingMnemonic = nil
        let nextLaunch = HostRecoveryHarness()
        _ = try await nextLaunch.start(network: .mainnet)
        XCTAssertEqual(PlatformWalletManager.rows.count, 2)
        XCTAssertEqual(PlatformWalletManager.createAttempts, ["wallet-a", "wallet-b", "wallet-b"])
        XCTAssertFalse(try nextLaunch.localStoreRecovery(for: .mainnet).isPending())
    }
    func testUnreadableKeychainKeepsRecoveryPendingAndRetriesLater() async throws {
        HostRecoveryHarness.unreadableKeychain = true
        let first = HostRecoveryHarness()
        do { _ = try await first.start(network: .mainnet); XCTFail("Expected strict read failure") } catch {}
        XCTAssertTrue(try first.localStoreRecovery(for: .mainnet).isPending())
        XCTAssertTrue(PlatformWalletManager.createAttempts.isEmpty)
        HostRecoveryHarness.unreadableKeychain = false
        _ = try await HostRecoveryHarness().start(network: .mainnet)
        XCTAssertEqual(PlatformWalletManager.rows.count, 2)
    }
    func testCrashAfterAllRowsBeforeMarkerRemovalDoesNotRecreateWallets() async throws {
        for name in ["wallet-a", "wallet-b"] {
            let id = Data(name.utf8)
            PlatformWalletManager.rows[id] = .init(walletId: id)
        }
        let host = HostRecoveryHarness()
        try host.localStoreRecovery(for: .mainnet).begin()
        _ = try await host.start(network: .mainnet)
        XCTAssertTrue(PlatformWalletManager.createAttempts.isEmpty)
        XCTAssertFalse(try host.localStoreRecovery(for: .mainnet).isPending())
    }
    func testHealthyStoreDoesNotRequireReadingEveryMnemonic() async throws {
        let id = Data("wallet-a".utf8)
        PlatformWalletManager.rows[id] = .init(walletId: id)
        HostRecoveryHarness.unreadableKeychain = true
        _ = try await HostRecoveryHarness().start(network: .mainnet)
        XCTAssertTrue(PlatformWalletManager.createAttempts.isEmpty)
    }
    func testNativeRuntimeLatchSurvivesShutdownAndRequiresFreshHost() async throws {
        let host = HostRecoveryHarness()
        try host.validateLocalStoreReset()
        let handles = try await host.buildRuntime(for: .testnet)
        await handles.manager.shutdown()
        XCTAssertThrowsError(try host.validateLocalStoreReset()) { error in
            XCTAssertEqual(error as? WalletLocalStoreResetError, .restartRequired)
        }
        try HostRecoveryHarness().validateLocalStoreReset()
    }
    func testResetPreflightRejectsUnreadableOrMalformedRecoveryMaterial() throws {
        HostRecoveryHarness.unreadableKeychain = true
        XCTAssertThrowsError(try HostRecoveryHarness().validateLocalStoreReset())
        HostRecoveryHarness.unreadableKeychain = false
        HostRecoveryHarness.invalidMaterial = true
        XCTAssertThrowsError(try HostRecoveryHarness().validateLocalStoreReset())
    }
}
''')
    (sources / "ProcessNetworkValueCache.swift").write_text(
        "import Foundation\n@MainActor\n" + declaration(host, "final class ProcessNetworkValueCache<"))
    cache_tests = (repository / "DashWalletTests/SwiftDashSDKCoreLifecycleTests.swift").read_text()
    import re
    methods_to_test = re.findall(r"    func (testProcessCache\w+)\(", cache_tests)
    (tests / "ProcessNetworkValueCacheTests.swift").write_text(
        "import XCTest\n@testable import WalletPreparationHarness\nprivate enum CoreLifecycleTestError: Error { case start }\n@MainActor final class ProcessNetworkValueCacheTests: XCTestCase {\n"
        + "\n".join(declaration(cache_tests, "    func " + name + "(") for name in methods_to_test) + "\n}\n")

    send_service = (repository / "DashWallet/Sources/Models/Transactions/WalletSendService.swift").read_text()
    (sources / "AuthenticationGate.swift").write_text(
        "import Foundation\n" + declaration(send_service, "enum AuthenticationGate {") + r"""
@MainActor enum WalletSendService {
    struct Logger { func info(_ message: String) {} }
    static let logger = Logger()
}
@MainActor final class AuthenticationService {
    enum AuthOutcome { case authenticated, cancelled, failed }
    static let shared = AuthenticationService()
    var didAuthenticate = false
    var cancelled = false
    var started = false
    var continuation: CheckedContinuation<AuthOutcome, Never>?
    func authenticate(usingBiometrics: Bool, spendAmount: UInt64?) async -> AuthOutcome {
        started = true
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in self.cancelled = true }
        }
    }
    func finishDismissal(_ result: AuthOutcome) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: result)
    }
}
""")
    (tests / "AuthenticationGateTests.swift").write_text(r"""
import XCTest
@testable import WalletPreparationHarness
@MainActor final class AuthenticationGateTests: XCTestCase {
    func testTimeoutCancelsRequestAndWaitsForPromptDismissal() async throws {
        let service = AuthenticationService.shared
        service.cancelled = false
        service.started = false
        var returned = false
        let request = Task {
            let result = await AuthenticationGate.authenticate(biometric: false, timeout: 0.01)
            returned = true
            return result
        }
        while !service.cancelled { await Task.yield() }
        XCTAssertTrue(service.started)
        XCTAssertFalse(returned, "The overlay must stay hidden until the PIN modal is dismissed")
        service.finishDismissal(.cancelled)
        let result = await request.value
        XCTAssertEqual(result, .timedOut)
    }
    func testSuccessfulRequestIsNotCancelledByItsOldWatchdog() async throws {
        let service = AuthenticationService.shared
        service.cancelled = false
        service.started = false
        let request = Task { await AuthenticationGate.authenticate(biometric: false, timeout: 0.01) }
        while !service.started { await Task.yield() }
        service.finishDismissal(.authenticated)
        let result = await request.value
        XCTAssertEqual(result, .ok)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(service.cancelled)
    }
}
""")

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
    var refreshFailure: WalletPreparationFailure?
    @discardableResult
    func refresh(trigger: RefreshTrigger, runtimeAlreadyStopped: Bool = false) async -> WalletPreparationFailure? {
        refreshCalls += 1
        events.append("refresh")
        if runtimeAlreadyStopped { assert(WalletLifecycleTransitionState.shared.phase == .resettingLocalStores) }
        if let refreshFailure { return refreshFailure }
        try? await WalletLifecycleTransitionState.shared.prepareWallet {} failure: { _ in nil }
        return nil
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

actor SuspendingResetter: WalletLocalStoreResetting {
    var started = false
    var continuation: CheckedContinuation<Void, Never>?
    func resetAllScopes() async throws -> WalletLocalStoreResetReport {
        started = true
        await withCheckedContinuation { continuation = $0 }
        return WalletLocalStoreResetReport(removed: [])
    }
    func release() { continuation?.resume() }
}

@MainActor final class AutomaticPreparationTests: XCTestCase {
    let state = WalletLifecycleTransitionState.shared
    let runtime = SwiftDashSDKWalletRuntime.shared
    override func setUp() async throws {
        await runtime.drain()
        state.finish()
        runtime.refreshCalls = 0
        runtime.refreshFailure = nil
        runtime.events = []
        SwiftDashSDKHost.shared.validationError = nil
        SwiftDashSDKHost.shared.releaseError = nil
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
    func testNativeRuntimeRequiresRelaunchWithoutDeletingOrClearingFlags() async throws {
        await failOpen()
        let originalPhase = state.phase
        SwiftDashSDKHost.shared.validationError = WalletLocalStoreResetError.restartRequired
        let resetter = FakeResetter()
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Reset must refuse native workers from an earlier runtime")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, .restartRequired)
        }
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(runtime.events, [])
        XCTAssertEqual(state.phase, originalPhase)
        XCTAssertFalse(SwiftDashSDKHost.shared.suspended)
    }
    func testRetainedStoreAfterTeardownCannotReachFileDeletion() async throws {
        await failOpen()
        let originalPhase = state.phase
        SwiftDashSDKHost.shared.releaseError = WalletLocalStoreResetError.storesStillInUse
        let resetter = FakeResetter()
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("A retained store must block deletion")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, .storesStillInUse)
        }
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(runtime.events, ["fullReset", "drop"])
        XCTAssertEqual(state.phase, originalPhase)
        XCTAssertFalse(SwiftDashSDKHost.shared.suspended)
    }
    func testResetRejectsConcurrentWipeWhileDeletionIsSuspended() async throws {
        await failOpen()
        let resetter = SuspendingResetter()
        let reset = Task { try await runtime.resetLocalStoresAndRetry(resetter: resetter) }
        while await !resetter.started { await Task.yield() }
        XCTAssertEqual(state.phase, .resettingLocalStores)
        XCTAssertTrue(SwiftDashSDKHost.shared.suspended)
        XCTAssertFalse(state.tryBegin(.wiping(title: nil)))
        XCTAssertFalse(state.tryBegin(.switchingNetwork(from: .testnet, to: .mainnet)))
        await resetter.release()
        _ = try await reset.value
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(SwiftDashSDKHost.shared.suspended)
    }
    func testResetFailureDuringRestartKeepsFreshDiagnostic() async throws {
        await failOpen()
        let failure = WalletPreparationFailure(error: NSError(domain: "SDKBootstrap", code: 42))
        runtime.refreshFailure = failure
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: FakeResetter())
        XCTAssertEqual(outcome, .failed(failure))
        XCTAssertEqual(state.phase, .failedWalletOpen(failure))
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertFalse(SwiftDashSDKHost.shared.suspended)
    }
    func testResetFromNetworkSwitchFailureRestoresOriginalCardOnDeletionError() async throws {
        let phase = WalletLifecycleTransitionState.Phase.failedNetworkSwitch(from: .mainnet, target: .testnet, message: "failure")
        let failure = WalletPreparationFailure(error: NSError(domain: NSCocoaErrorDomain, code: 134100))
        state.restoreAfterLocalStoreReset(phase: phase, failure: failure)
        let resetter = FakeResetter()
        resetter.error = .removalFailed(root: "Platform", scope: "testnet", code: "NSCocoaErrorDomain:513")
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Expected failure")
        } catch {}
        XCTAssertEqual(state.phase, phase)
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertFalse(SwiftDashSDKHost.shared.suspended)
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
    func testRetryAfterResetFailureDoesNotDismissAnUnresolvedStartupError() async throws {
        await failOpen()
        let failure = WalletPreparationFailure(error: NSError(domain: "SDKBootstrap", code: 42))
        runtime.refreshFailure = failure
        _ = try await runtime.resetLocalStoresAndRetry(resetter: FakeResetter())
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .failedWalletOpen(failure))
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

//
//  AutomaticPreparationTests.swift
//  DashWalletTests
//
//  `SwiftDashSDKWalletRuntime`'s automatic-preparation admission, the
//  background-refresh start gate and the local-store reset over a runtime
//  whose rebuild is a recorder: the serial lifecycle queue, the queued
//  operations and a `WalletLifecycleTransitionState` of the test's own are
//  production; the rebuild steps, the host's reset admission and the balance
//  mirrors are stand-ins. Nothing here touches the process singletons, which
//  the host app's real runtime keeps driving while the tests run.
//

import XCTest
import SwiftDashSDK
@testable import dashpay

/// Stands in for the runtime's own rebuild: counts refreshes, records the
/// order of the reset's steps, and drives the open's classification through
/// the real `prepareWallet` the way `refresh` does.
@MainActor
final class RecordingLifecycleSteps: WalletRuntimeLifecycleSteps {
    private let state: WalletLifecycleTransitionState
    var refreshCalls = 0
    /// Order of the reset operation's steps, for the ordering assertions.
    var events: [String] = []
    /// Returned around the open, as the wallet-presence gate and the
    /// unclassified-start fallback do in production.
    var refreshFailure: WalletPreparationFailure?
    /// Classified by the open itself (the `prepareWallet` failure closure).
    var openFailure: WalletPreparationFailure?
    /// The open failed with a cause the host left unclassified (closure nil):
    /// the production fallback record is returned after `finish()`.
    var unclassifiedOpenFailure: WalletPreparationFailure?
    /// The open succeeded and a later start step (SPV) failed.
    var postOpenFailure: WalletPreparationFailure?

    init(state: WalletLifecycleTransitionState) {
        self.state = state
    }

    @discardableResult
    func refresh(
        trigger: SwiftDashSDKWalletRuntime.RefreshTrigger, runtimeAlreadyStopped: Bool
    ) async -> WalletPreparationFailure? {
        refreshCalls += 1
        events.append("refresh")
        if runtimeAlreadyStopped {
            XCTAssertEqual(state.phase, .resettingLocalStores)
        }
        if let refreshFailure { return refreshFailure }
        if let openFailure {
            try? await state.prepareWallet {
                throw NSError(domain: "Open", code: 1)
            } failure: { _ in openFailure }
            return state.preparationFailure ?? openFailure
        }
        if let unclassifiedOpenFailure {
            try? await state.prepareWallet {
                throw NSError(domain: "Open", code: 2)
            } failure: { _ in nil }
            return unclassifiedOpenFailure
        }
        try? await state.prepareWallet {} failure: { _ in nil }
        return postOpenFailure
    }

    func fullReset(lastError: String?, forWipe: Bool, preservingShieldedRecovery: Bool) async {
        events.append("fullReset")
    }

    func dropLocalStoreDerivedState() { events.append("drop") }

    func clearLocalStoreMaintenanceFlags() { events.append("flags") }

    func selectSolePersistedNetworkIfNeeded(currentNetwork: Network) -> Bool {
        events.append("soleNetwork")
        return false
    }

    func publishActiveWalletDidChange(reason: String) { events.append("publish") }

    func resolveCurrentNetwork() -> Result<Network, SwiftDashSDKWalletRuntime.RuntimeError> { .success(.testnet) }

    func isCoreRuntimeReady(for network: Network) -> Bool {
        state.phase == .idle
    }
}

/// The host's reset admission: records the suspension and throws on request.
@MainActor
final class RecordingResetAdmission: WalletLocalStoreResetAdmitting {
    var suspended = false
    var validationError: Error?
    var releaseError: Error?

    func validateLocalStoreReset() async throws {
        if let validationError { throw validationError }
    }

    func suspendModelContainerOpens() async { suspended = true }

    func waitForLocalStoreRelease() async throws {
        if let releaseError { throw releaseError }
    }

    func resumeModelContainerOpens() { suspended = false }
}

@MainActor
final class RecordingNetworkSwitchMirror: NetworkSwitchPreparing {
    var preparations = 0

    func prepareForNetworkSwitch() { preparations += 1 }
}

/// Stands in for `WalletLocalStoreResetter`: records the call in the
/// steps' event order and throws on request.
final class FakeResetter: WalletLocalStoreResetting, @unchecked Sendable {
    private let steps: RecordingLifecycleSteps
    var error: WalletLocalStoreResetError?
    var calls = 0

    init(steps: RecordingLifecycleSteps) {
        self.steps = steps
    }

    func resetAllScopes() async throws -> WalletLocalStoreResetReport {
        calls += 1
        await MainActor.run { steps.events.append("delete") }
        if let error { throw error }
        return WalletLocalStoreResetReport(removed: [.init(root: "Platform", scope: "testnet")])
    }
}

actor SuspendingResetter: WalletLocalStoreResetting {
    /// Fulfilled when the deletion is suspended inside the reset.
    nonisolated let started = XCTestExpectation(description: "Deletion started")
    var continuation: CheckedContinuation<Void, Never>?

    func resetAllScopes() async throws -> WalletLocalStoreResetReport {
        started.fulfill()
        await withCheckedContinuation { continuation = $0 }
        return WalletLocalStoreResetReport(removed: [])
    }

    func release() { continuation?.resume() }
}

@MainActor
final class AutomaticPreparationTests: XCTestCase {
    private var state: WalletLifecycleTransitionState!
    private var steps: RecordingLifecycleSteps!
    private var host: RecordingResetAdmission!
    private var coreMirror: RecordingNetworkSwitchMirror!
    private var platformMirror: RecordingNetworkSwitchMirror!
    private var runtime: SwiftDashSDKWalletRuntime!

    override func setUp() async throws {
        state = WalletLifecycleTransitionState()
        steps = RecordingLifecycleSteps(state: state)
        host = RecordingResetAdmission()
        coreMirror = RecordingNetworkSwitchMirror()
        platformMirror = RecordingNetworkSwitchMirror()
        runtime = SwiftDashSDKWalletRuntime(collaborators: .init(
            steps: steps, lifecycleState: state, host: host, coreMirror: coreMirror, platformMirror: platformMirror))
    }

    override func tearDown() async throws {
        await drain()
    }

    /// Returns once every operation queued so far has run.
    private func drain() async {
        await runtime.enqueueAwaitable {}.value
    }

    private func makeResetter() -> FakeResetter { FakeResetter(steps: steps) }

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
            await drain()
            guard case let .failedWalletOpen(detail) = state.phase else { return XCTFail("Lost failure") }
            XCTAssertEqual(state.preparationFailure, detail)
            XCTAssertEqual(steps.refreshCalls, 0, "Automatic trigger: \(trigger)")
        }
    }

    func testNetworkNotificationAfterFailedOpenDoesNotDetachOrRefresh() async {
        await failOpen()
        let failure = state.preparationFailure
        runtime.handleObservedNetworkChange()
        await drain()
        XCTAssertEqual(coreMirror.preparations, 0)
        XCTAssertEqual(platformMirror.preparations, 0)
        XCTAssertEqual(steps.refreshCalls, 0)
        XCTAssertEqual(state.preparationFailure, failure)
    }

    func testNormalNetworkNotificationStillClearsMirrorsBeforeQueuedRefresh() async {
        runtime.handleObservedNetworkChange()
        XCTAssertEqual(coreMirror.preparations, 1)
        XCTAssertEqual(platformMirror.preparations, 1)
        XCTAssertEqual(steps.refreshCalls, 0)
        await drain()
        XCTAssertEqual(steps.refreshCalls, 1)
    }

    func testNetworkNotificationStillRespectsFailureAheadInQueue() async {
        runtime.enqueue { await self.failOpen() }
        runtime.handleObservedNetworkChange()
        await drain()
        XCTAssertEqual(steps.refreshCalls, 0)
        XCTAssertNotNil(state.preparationFailure)
    }

    func testBackgroundRechecksFailureAfterWaitingForQueue() async {
        runtime.enqueue { await self.failOpen() }
        let ready = await BackgroundRefreshCoordinator.defaultRuntimeStart(
            while: .init(isWanted: { true }), runtime: runtime)
        XCTAssertFalse(ready)
        XCTAssertEqual(steps.refreshCalls, 0)
        XCTAssertNotNil(state.preparationFailure)
    }

    func testExpiredBackgroundStartIsStillRejected() async {
        var wanted = true
        runtime.enqueue { wanted = false }
        _ = await BackgroundRefreshCoordinator.defaultRuntimeStart(
            while: .init(isWanted: { wanted }), runtime: runtime)
        XCTAssertEqual(steps.refreshCalls, 0)
    }

    func testOrdinaryBackgroundStartStillWorks() async {
        let ready = await BackgroundRefreshCoordinator.defaultRuntimeStart(
            while: .init(isWanted: { true }), runtime: runtime)
        XCTAssertTrue(ready)
        XCTAssertEqual(steps.refreshCalls, 1)
    }

    func testResetSkipsWhenNoFailureIsShowing() async throws {
        let resetter = makeResetter()
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(steps.refreshCalls, 0)
        XCTAssertEqual(steps.events, [])
    }

    func testResetSkipsStorageFailures() async throws {
        do {
            try await state.prepareWallet { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)) }
                failure: { WalletPreparationFailure(error: $0) }
        } catch {}
        let resetter = makeResetter()
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(resetter.calls, 0)
        guard case .failedWalletOpen = state.phase else { return XCTFail("The card must stay") }
    }

    func testResetOrdersTeardownDropDeleteFlagsRefreshThenPublish() async throws {
        await failOpen()
        steps.events = []
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: makeResetter())
        XCTAssertEqual(outcome, .reset)
        XCTAssertEqual(steps.events, ["fullReset", "drop", "delete", "flags", "soleNetwork", "refresh", "publish"])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
    }

    func testResetFailsClosedWhenDeletionFails() async throws {
        await failOpen()
        let failure = state.preparationFailure
        let resetter = makeResetter()
        resetter.error = .removalFailed(root: "Shielded", scope: "testnet", code: "NSCocoaErrorDomain:513")
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Expected the deletion error")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, resetter.error)
        }
        XCTAssertEqual(steps.refreshCalls, 0)
        XCTAssertEqual(state.preparationFailure, failure)
        guard case .failedWalletOpen = state.phase else { return XCTFail("The card must stay") }
    }

    func testEnumerationFailureKeepsEveryMaintenanceFlag() async throws {
        await failOpen()
        let resetter = makeResetter()
        resetter.error = .enumerationFailed(root: "SPV", code: "NSCocoaErrorDomain:257")
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Expected the enumeration error")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, resetter.error)
        }
        // No store was touched, so the next launch still applies every
        // armed resync marker and wide-scan flag to the surviving stores.
        XCTAssertEqual(steps.events, ["fullReset", "drop", "delete"])
    }

    func testRemovalFailureKeepsEveryMaintenanceFlag() async throws {
        await failOpen()
        let resetter = makeResetter()
        // Whatever was removed before the failure is rebuilt by the host,
        // which re-arms the CoinJoin scan as it recreates rows; the resync
        // markers stay for every surviving header store.
        resetter.error = .removalFailed(root: "SPV", scope: "testnet", code: "NSCocoaErrorDomain:513")
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Expected the removal error")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, resetter.error)
        }
        XCTAssertEqual(steps.events, ["fullReset", "drop", "delete"])
        guard case .failedWalletOpen = state.phase else { return XCTFail("The card must stay") }
    }

    func testNativeRuntimeRequiresRelaunchWithoutDeletingOrClearingFlags() async throws {
        await failOpen()
        let originalPhase = state.phase
        host.validationError = WalletLocalStoreResetError.restartRequired
        let resetter = makeResetter()
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Reset must refuse native workers from an earlier runtime")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, .restartRequired)
        }
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(steps.events, [])
        XCTAssertEqual(state.phase, originalPhase)
        XCTAssertFalse(host.suspended)
    }

    func testRetainedStoreAfterTeardownCannotReachFileDeletion() async throws {
        await failOpen()
        let originalPhase = state.phase
        host.releaseError = WalletLocalStoreResetError.storesStillInUse
        let resetter = makeResetter()
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("A retained store must block deletion")
        } catch let error as WalletLocalStoreResetError {
            XCTAssertEqual(error, .storesStillInUse)
        }
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(steps.events, ["fullReset", "drop"])
        XCTAssertEqual(state.phase, originalPhase)
        XCTAssertFalse(host.suspended)
    }

    func testResetRejectsConcurrentWipeWhileDeletionIsSuspended() async throws {
        await failOpen()
        let resetter = SuspendingResetter()
        let runtime = runtime!
        let reset = Task { try await runtime.resetLocalStoresAndRetry(resetter: resetter) }
        await fulfillment(of: [resetter.started], timeout: 5)
        XCTAssertEqual(state.phase, .resettingLocalStores)
        XCTAssertTrue(host.suspended)
        XCTAssertFalse(state.tryBegin(.wiping(title: nil)))
        XCTAssertFalse(state.tryBegin(.switchingNetwork(from: .testnet, to: .mainnet)))
        await resetter.release()
        _ = try await reset.value
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(host.suspended)
    }

    func testResetFailureDuringRestartKeepsFreshDiagnostic() async throws {
        await failOpen()
        let failure = WalletPreparationFailure(error: NSError(domain: "SDKBootstrap", code: 42))
        steps.refreshFailure = failure
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: makeResetter())
        XCTAssertEqual(outcome, .failed(failure))
        XCTAssertEqual(state.phase, .failedWalletOpen(failure))
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertFalse(host.suspended)
    }

    func testResetFromNetworkSwitchFailureRestoresOriginalCardOnDeletionError() async throws {
        let phase = WalletLifecycleTransitionState.Phase.failedNetworkSwitch(from: .mainnet, target: .testnet, message: "failure")
        let failure = WalletPreparationFailure(error: NSError(domain: NSCocoaErrorDomain, code: 134100))
        state.restoreAfterLocalStoreReset(phase: phase, failure: failure)
        let resetter = makeResetter()
        resetter.error = .removalFailed(root: "Platform", scope: "testnet", code: "NSCocoaErrorDomain:513")
        do {
            _ = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
            XCTFail("Expected failure")
        } catch {}
        XCTAssertEqual(state.phase, phase)
        XCTAssertEqual(state.preparationFailure, failure)
        XCTAssertFalse(host.suspended)
    }

    func testQueuedRetryAheadOfResetMakesItSkip() async throws {
        await failOpen()
        let resetter = makeResetter()
        let steps = steps!
        runtime.enqueue { await steps.refresh(trigger: .startIfReady, runtimeAlreadyStopped: false) }
        let outcome = try await runtime.resetLocalStoresAndRetry(resetter: resetter)
        XCTAssertEqual(outcome, .skipped)
        XCTAssertEqual(resetter.calls, 0)
        XCTAssertEqual(state.phase, .idle)
    }

    func testRetryAfterResetFailureDoesNotDismissAnUnresolvedStartupError() async throws {
        await failOpen()
        let failure = WalletPreparationFailure(error: NSError(domain: "SDKBootstrap", code: 42))
        steps.refreshFailure = failure
        _ = try await runtime.resetLocalStoresAndRetry(resetter: makeResetter())
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
        XCTAssertEqual(steps.refreshCalls, 2)
    }

    func testRetryFromTheKeysCardKeepsItOnlyWhenTheOpenWasNotReached() async {
        let keys = WalletPreparationFailure(keys: .unreadable, status: -25291)
        state.fail(.failedWalletOpen(keys))
        // The wallet-presence gate refused before the open: the same keychain
        // failure, and its store record must not replace the keys card.
        steps.refreshFailure = WalletPreparationFailure(error: NSError(domain: "Presence", code: 2))
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .failedWalletOpen(keys))
        XCTAssertEqual(state.preparationFailure, keys)
        // The open ran and classified a store failure: it replaces the card.
        steps.refreshFailure = nil
        let store = WalletPreparationFailure(error: NSError(domain: "SwiftData.SwiftDataError", code: 1))
        steps.openFailure = store
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .failedWalletOpen(store))
        // The open ran and classified nothing (walletNotFound, SDK init): the
        // automatic kick's rule — the fallback record is no card at all.
        state.fail(.failedWalletOpen(keys))
        steps.openFailure = nil
        steps.unclassifiedOpenFailure = WalletPreparationFailure(error: NSError(domain: "Fallback", code: 3))
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
        // The open succeeded and SPV failed afterwards: same, no card.
        state.fail(.failedWalletOpen(keys))
        steps.unclassifiedOpenFailure = nil
        steps.postOpenFailure = WalletPreparationFailure(error: NSError(domain: "SPV", code: 4))
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .idle)
        // A store card keeps today's rule: any returned record replaces it.
        steps.postOpenFailure = nil
        await failOpen()
        let other = WalletPreparationFailure(error: NSError(domain: "Presence", code: 2))
        steps.refreshFailure = other
        await runtime.retryWalletPreparation()
        XCTAssertEqual(state.phase, .failedWalletOpen(other))
    }

    func testKeysCardIsClearedByTheNextAutomaticKick() async {
        state.fail(.failedWalletOpen(WalletPreparationFailure(keys: .unreadable, status: -25308)))
        runtime.enqueueRefresh(trigger: .startIfReady)
        await drain()
        XCTAssertEqual(steps.refreshCalls, 1)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.preparationFailure)
        // A store card still refuses the automatic kick.
        await failOpen()
        runtime.enqueueRefresh(trigger: .startIfReady)
        await drain()
        XCTAssertEqual(steps.refreshCalls, 1)
        guard case .failedWalletOpen = state.phase else { return XCTFail("Store card dismissed by an automatic kick") }
    }

    func testKicksAreDeferredWhileACardFlowHoldsTheWindowAndReplayedOnRelease() async {
        let keys = WalletPreparationFailure(keys: .unreadable, status: -25291)
        state.fail(.failedWalletOpen(keys))
        // The phrase modal, Help or the share sheet is up: a connectivity or
        // foreground kick must not move the phase from under it.
        state.holdRecoveryPresentation()
        runtime.enqueueRefresh(trigger: .startIfReady)
        runtime.handleObservedNetworkChange()
        await drain()
        XCTAssertEqual(steps.refreshCalls, 0)
        XCTAssertEqual(state.phase, .failedWalletOpen(keys))
        // Release reports the refused kick; its replay clears the card.
        XCTAssertTrue(state.releaseRecoveryPresentation())
        runtime.enqueueRefresh(trigger: .startIfReady)
        await drain()
        XCTAssertEqual(steps.refreshCalls, 1)
        XCTAssertEqual(state.phase, .idle)
    }
}

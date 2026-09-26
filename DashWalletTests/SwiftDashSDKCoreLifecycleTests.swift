//
//  SwiftDashSDKCoreLifecycleTests.swift
//  DashWalletTests
//
//  Regression coverage for SDK lifecycle and freshness policies.
//

import XCTest
import SwiftDashSDK
@testable import dashpay

private enum CoreLifecycleTestError: Error {
    case start
}

@MainActor
final class SwiftDashSDKCoreLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testNameEndpointFailureDoesNotBlockAdoptingDiscoveredIdentity() async throws {
        let id = Data([1])
        var adopted = false
        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            localIdentityIds: { [id] }, discover: { XCTFail("Already discovered"); return [] },
            refreshNames: { _ in throw NSError(domain: "test", code: 1) },
            adopt: { adopted = true; return true })
        XCTAssertTrue(adopted)
        XCTAssertTrue(outcome.adopted)
        XCTAssertTrue(outcome.identitiesPersisted)
    }

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

    // MARK: - Devnet start preflight

    /// The runtime discovers devnet peers before the SDK is built; the SPV
    /// start that follows reuses exactly those peers instead of fetching
    /// `/masternodes` a second time.
    func testDevnetPreflightPeersAreReusedForTheSameConfiguration() {
        let preflight = DevnetStartPreflight(
            scope: "devnet-moutai",
            quorumURL: "https://quorum.example",
            peers: ["1.2.3.4:20001"])

        XCTAssertEqual(
            preflight.peers(forScope: "devnet-moutai", quorumURL: "https://quorum.example"),
            ["1.2.3.4:20001"])
    }

    /// Devnet settings can change between a preflight and the start it was
    /// made for. Peers discovered for devnet A must never configure a client
    /// for devnet B — nor peers from a different quorum service.
    func testDevnetPreflightIsDiscardedWhenTheConfigurationChanged() {
        let preflight = DevnetStartPreflight(
            scope: "devnet-a",
            quorumURL: "https://a.example",
            peers: ["1.2.3.4:20001"])

        XCTAssertNil(preflight.peers(forScope: "devnet-b", quorumURL: "https://a.example"))
        XCTAssertNil(preflight.peers(forScope: "devnet-a", quorumURL: "https://b.example"))
    }

    /// An empty peer set is not a usable preflight: the start must rediscover
    /// rather than configure a peer-restricted client with no peers.
    func testEmptyDevnetPreflightIsNotReused() {
        let preflight = DevnetStartPreflight(
            scope: "devnet-a", quorumURL: "https://a.example", peers: [])

        XCTAssertNil(preflight.peers(forScope: "devnet-a", quorumURL: "https://a.example"))
    }

    // MARK: - Selectable wallet material memo

    /// The memo answers only for the inventory it was derived from, so a
    /// changed wallet set re-runs the classification instead of returning a
    /// stale verdict.
    func testSelectableWalletMaterialMemoAnswersOnlyForItsOwnInventory() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "memo.\(UUID().uuidString)"))
        let ids = [Data([0x01]), Data([0x02])]
        let fingerprint = WalletEnvironment.SelectableWalletMaterialMemo.fingerprint(of: ids)

        WalletEnvironment.SelectableWalletMaterialMemo(
            fingerprint: fingerprint, selectable: false).save(to: defaults)
        let loaded = try XCTUnwrap(
            WalletEnvironment.SelectableWalletMaterialMemo.load(from: defaults))

        XCTAssertEqual(loaded.verdict(for: fingerprint), false)
        let changed = WalletEnvironment.SelectableWalletMaterialMemo.fingerprint(
            of: ids + [Data([0x03])])
        XCTAssertNil(loaded.verdict(for: changed))
    }

    /// The fingerprint identifies a SET of ids: Keychain enumeration order
    /// must not invalidate a good memo and force the derivation again.
    func testSelectableWalletMaterialFingerprintIsOrderIndependent() {
        let ids = [Data([0x0a]), Data([0x0b]), Data([0xff])]

        XCTAssertEqual(
            WalletEnvironment.SelectableWalletMaterialMemo.fingerprint(of: ids),
            WalletEnvironment.SelectableWalletMaterialMemo.fingerprint(of: ids.reversed()))
    }

    func testAbsentSelectableWalletMaterialMemoLoadsAsNil() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "memo.\(UUID().uuidString)"))

        XCTAssertNil(WalletEnvironment.SelectableWalletMaterialMemo.load(from: defaults))
    }

    // MARK: - Wallet presence

    /// A failed Keychain inventory read is "unknown", not "absent": the
    /// status is kept for the log, a non-Keychain error has none.
    func testKeychainReadFailureClassifiesAsUnknownPresenceWithItsStatus() {
        let failed = SwiftDashSDKHost.PersistedWalletPresence.classify(
            .failure(WalletStorageError.keychainError(errSecInteractionNotAllowed)))

        XCTAssertEqual(failed, .unknown(errSecInteractionNotAllowed))
        XCTAssertTrue(failed.isUnknown)
        XCTAssertEqual(
            SwiftDashSDKHost.PersistedWalletPresence.classify(.failure(CoreLifecycleTestError.start)),
            .unknown(nil))
    }

    func testInventoryReadClassifiesPresentAndAbsent() {
        XCTAssertEqual(
            SwiftDashSDKHost.PersistedWalletPresence.classify(.success([Data([0x01])])), .present)
        XCTAssertEqual(SwiftDashSDKHost.PersistedWalletPresence.classify(.success([])), .absent)
        XCTAssertFalse(SwiftDashSDKHost.PersistedWalletPresence.absent.isUnknown)
    }

    /// The app-level presence keeps "unknown" apart from both answers and
    /// never consults the selectable-material derivation for it — that
    /// derivation reads the same Keychain.
    func testAppWalletPresenceHoldsUnknownWithoutDerivingMaterial() {
        var derived = false
        let presence = WalletEnvironment.walletPresence(
            hostPresence: .unknown(nil),
            hasSelectableMaterial: { derived = true; return true })

        XCTAssertEqual(presence, .unknown)
        XCTAssertFalse(derived)
        XCTAssertEqual(
            WalletEnvironment.walletPresence(hostPresence: .absent, hasSelectableMaterial: { true }),
            .absent)
    }

    /// A present mnemonic counts only when this build can select it — the
    /// rule `hasWallet` applies (devnet-only material in a shipping build
    /// routes to setup, not to a `walletNotFound` dead end) — and a gate
    /// whose own read failed answers nil, which is unknown, not present.
    func testAppWalletPresenceAppliesTheSelectableMaterialGate() {
        XCTAssertEqual(
            WalletEnvironment.walletPresence(hostPresence: .present, hasSelectableMaterial: { true }),
            .present)
        XCTAssertEqual(
            WalletEnvironment.walletPresence(hostPresence: .present, hasSelectableMaterial: { false }),
            .absent)
        XCTAssertEqual(
            WalletEnvironment.walletPresence(hostPresence: .present, hasSelectableMaterial: { nil }),
            .unknown)
    }

    // MARK: - Launch decision

    /// A launch in the background defers the wallet work to the first
    /// activation, exactly once; a foreground launch defers nothing.
    func testBackgroundLaunchDefersTheWalletWorkToTheFirstActivationOnce() {
        let background = LaunchDecision(applicationState: .background)
        XCTAssertTrue(background.isDeferred)
        XCTAssertTrue(background.takeAtActivation())
        XCTAssertFalse(background.isDeferred)
        XCTAssertFalse(background.takeAtActivation(), "later activations run nothing")

        let foreground = LaunchDecision(applicationState: .inactive)
        XCTAssertFalse(foreground.isDeferred)
        XCTAssertFalse(foreground.takeAtActivation())
        XCTAssertFalse(LaunchDecision(applicationState: .active).isDeferred)
    }

    /// A link delivered while the launch is deferred is kept and handed
    /// back exactly once after the activation; a later link replaces an
    /// earlier one; a foreground launch, and a deferred launch once taken,
    /// keep nothing (the handler proceeds as usual).
    func testLinksDeliveredWhileDeferredAreKeptAndReplayedOnce() throws {
        let decision = LaunchDecision(applicationState: .background)
        let first = try XCTUnwrap(URL(string: "dash:XfirstAddress"))
        let second = try XCTUnwrap(URL(string: "dash:XsecondAddress"))
        XCTAssertTrue(decision.holdIfPending(url: first))
        XCTAssertTrue(decision.holdIfPending(url: second), "a later link replaces the earlier one")
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        XCTAssertTrue(decision.holdIfPending(userActivity: activity))

        XCTAssertTrue(decision.takeAtActivation())
        XCTAssertEqual(decision.takePendingURL(), second)
        XCTAssertNil(decision.takePendingURL(), "replayed once")
        XCTAssertTrue(decision.takePendingUserActivity() === activity)
        XCTAssertNil(decision.takePendingUserActivity())
        XCTAssertFalse(decision.holdIfPending(url: first), "after the activation links are handled at once")

        let foreground = LaunchDecision(applicationState: .inactive)
        XCTAssertFalse(foreground.holdIfPending(url: first))
        XCTAssertNil(foreground.takePendingURL())
    }

    /// A recover import in flight refuses a second submission, and only the
    /// completion of the current attempt counts: a stale one is ignored, so
    /// it can neither clear a newer command nor advance setup.
    func testRecoverImportAttemptsAdmitOneAtATimeAndIgnoreStaleCompletions() {
        let attempts = RecoverImportAttempts()
        XCTAssertFalse(attempts.isInFlight)

        let first = attempts.begin()
        XCTAssertTrue(attempts.isInFlight)
        XCTAssertTrue(attempts.finish(first))
        XCTAssertFalse(attempts.isInFlight)
        XCTAssertFalse(attempts.finish(first), "an attempt finishes once")

        let second = attempts.begin()
        let third = attempts.begin()
        XCTAssertFalse(attempts.finish(second), "an older attempt's completion is stale")
        XCTAssertTrue(attempts.isInFlight, "the current attempt is still running")
        XCTAssertTrue(attempts.finish(third))
        XCTAssertFalse(attempts.isInFlight)

        let fourth = attempts.begin()
        attempts.invalidate()
        XCTAssertFalse(attempts.isInFlight, "leaving the flow ends the attempt")
        XCTAssertFalse(attempts.finish(fourth), "its completion is stale")
    }

    /// The recover flow's two decisions: at submission an import in flight
    /// wins over everything, otherwise a missing PIN defers the command to
    /// the PIN step and an existing PIN executes now; at execution only a
    /// definite "absent" imports — unreadable retries, present completes
    /// into the wallet that is there.
    func testRecoverImportRoutingCoversSubmissionAndExecution() {
        XCTAssertEqual(RecoverImportRouting.atSubmission(inFlight: true, shouldSetPin: true), .ignoreWhileInFlight)
        XCTAssertEqual(RecoverImportRouting.atSubmission(inFlight: true, shouldSetPin: false), .ignoreWhileInFlight)
        XCTAssertEqual(RecoverImportRouting.atSubmission(inFlight: false, shouldSetPin: true), .deferUntilPinSet)
        XCTAssertEqual(RecoverImportRouting.atSubmission(inFlight: false, shouldSetPin: false), .executeNow)

        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .unknown), .retryUnreadable)
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .absent), .importWallet)
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .present), .completeWithExistingWallet)
    }

    /// Regression: the first attempt persisted the current network's wallet
    /// and failed provisioning the other one; the retry then failed for an
    /// ordinary reason; the retry after that must still resume. The route
    /// is derived from the keychain at each execution ("is the typed
    /// phrase's own wallet stored?"), never from a remembered outcome, so
    /// nothing in between can clear it: the same inputs give the same
    /// route on every attempt. Without that wallet, "present" is a wallet
    /// that landed meanwhile and setup completes into it.
    func testRetryAfterAPartialImportRerunsTheImportWhateverHappenedInBetween() {
        // Attempt 1: nothing stored yet — import (persists the wallet, then fails provisioning).
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .absent, walletForPhrasePersisted: false), .importWallet)
        // Attempt 2: the phrase's wallet is stored — import again (resume). It fails for another reason.
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .present, walletForPhrasePersisted: true), .importWallet)
        // Attempt 3: same inputs, same route — the ordinary failure changed nothing.
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .present, walletForPhrasePersisted: true), .importWallet)

        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .present, walletForPhrasePersisted: false), .completeWithExistingWallet,
                       "a wallet that is not the phrase's own landed meanwhile")
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .unknown, walletForPhrasePersisted: true), .retryUnreadable,
                       "an unreadable keychain still waits, even mid-resume")
        XCTAssertEqual(RecoverImportRouting.atExecution(presence: .absent, walletForPhrasePersisted: true), .importWallet)
    }

    /// While the launch decision is pending, the runtime refuses automatic
    /// kicks (the sync monitor's connectivity kick, a network change); once
    /// the activation's wallet start releases the hold they pass again. A
    /// launch that never raised the hold is unaffected.
    func testAutomaticRuntimeKicksAreHeldWhileTheLaunchDecisionIsPending() {
        XCTAssertTrue(SwiftDashSDKWalletRuntime.automaticStartAllowedForLaunchDecision("foreground launch"))

        SwiftDashSDKWalletRuntime.holdAutomaticStartsUntilLaunchDecision()
        XCTAssertFalse(SwiftDashSDKWalletRuntime.automaticStartAllowedForLaunchDecision("connectivity-return kick"))
        XCTAssertFalse(SwiftDashSDKWalletRuntime.automaticStartAllowedForLaunchDecision("networkDidChange"))

        SwiftDashSDKWalletRuntime.releaseAutomaticStartsForLaunchDecision()
        XCTAssertTrue(SwiftDashSDKWalletRuntime.automaticStartAllowedForLaunchDecision("startIfReady"))
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

    /// The value-returning variant is one link of the same serial chain:
    /// its result comes back to the caller, its error propagates, and ops
    /// enqueued around it stay strictly ordered.
    func testEnqueueAwaitableReturnsValueThrowsAndKeepsChainOrder() async throws {
        let queue = SerialAsyncLifecycleQueue()
        var events: [String] = []

        queue.enqueue { events.append("before") }
        let value = try await queue.enqueueAwaitable { () async throws -> Int in
            events.append("awaitable")
            return 41
        }
        queue.enqueue { events.append("after") }

        XCTAssertEqual(value, 41)
        XCTAssertEqual(events, ["before", "awaitable"])

        do {
            _ = try await queue.enqueueAwaitable { () async throws -> Int in
                events.append("throwing")
                throw CoreLifecycleTestError.start
            }
            XCTFail("Expected the enqueued error to propagate")
        } catch CoreLifecycleTestError.start {
            // Expected — and the chain must survive a thrown link.
        }

        _ = try await queue.enqueueAwaitable { () async throws -> Int in
            events.append("tail")
            return 0
        }
        XCTAssertEqual(events, ["before", "awaitable", "after", "throwing", "tail"])
    }

    func testStallMonitorClassifiesLatenciesAroundTheMicrohangFloor() {
        XCTAssertNil(MainThreadStallMonitor.stallMilliseconds(forLatency: 0.0001))
        XCTAssertNil(MainThreadStallMonitor.stallMilliseconds(forLatency: 0.249))
        XCTAssertEqual(MainThreadStallMonitor.stallMilliseconds(forLatency: 0.25), 250)
        XCTAssertEqual(MainThreadStallMonitor.stallMilliseconds(forLatency: 1.512), 1512)
    }

    func testProcessCacheReusesValuesPerNetworkAndSeparatesNetworks() {
        final class Token: Sendable {}

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

    func testProcessCacheCoalescesConcurrentAsyncOpensAndRetriesFailures() async throws {
        final class Token: Sendable {}
        let cache = ProcessNetworkValueCache<Token>()
        var creates = 0
        var resumeOpen: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await cache.valueAsync(for: "testnet") {
                creates += 1
                await withCheckedContinuation { resumeOpen = $0 }
                return Token()
            }
        }
        while resumeOpen == nil { await Task.yield() }
        let second = Task { @MainActor in
            try await cache.valueAsync(for: "testnet") {
                XCTFail("An in-flight open must be reused")
                return Token()
            }
        }
        await Task.yield()
        resumeOpen?.resume()
        let initial = try await first.value
        let concurrent = try await second.value
        XCTAssertEqual(creates, 1)
        XCTAssertTrue(initial.value === concurrent.value)
        XCTAssertEqual(initial.source, .created)
        XCTAssertEqual(concurrent.source, .shared)
        let cached = try await cache.valueAsync(for: "testnet") { Token() }
        XCTAssertEqual(cached.source, .cached)
        XCTAssertTrue(cached.value === initial.value)
        do {
            _ = try await cache.valueAsync(for: "mainnet") { throw CoreLifecycleTestError.start }
            XCTFail("A failed open must throw")
        } catch CoreLifecycleTestError.start {}
        let retried = try await cache.valueAsync(for: "mainnet") { Token() }
        XCTAssertEqual(retried.source, .created)
        XCTAssertFalse(retried.value === initial.value)
    }

    func testConcurrentFailedOpenWaitersShareOneFreshRetry() async throws {
        let cache = ProcessNetworkValueCache<Int>()
        var releaseFailure: CheckedContinuation<Void, Never>?
        var releaseRetry: CheckedContinuation<Void, Never>?
        var entered = 0
        var failed = 0
        var retryCreates = 0
        let callers = (0..<8).map { _ in
            Task { @MainActor in
                entered += 1
                do {
                    _ = try await cache.valueAsync(for: "testnet") {
                        await withCheckedContinuation { releaseFailure = $0 }
                        throw CoreLifecycleTestError.start
                    }
                    XCTFail("Initial open must fail")
                    return -1
                } catch {
                    failed += 1
                    // Retry immediately, before other waiters necessarily resume.
                    return try await cache.valueAsync(for: "testnet") {
                        retryCreates += 1
                        guard retryCreates == 1 else {
                            XCTFail("An older waiter discarded the active retry")
                            return -1
                        }
                        await withCheckedContinuation { releaseRetry = $0 }
                        return 42
                    }.value
                }
            }
        }
        while entered < callers.count || releaseFailure == nil { await Task.yield() }
        releaseFailure?.resume()
        while failed < callers.count || releaseRetry == nil { await Task.yield() }
        releaseRetry?.resume()
        for caller in callers {
            let value = try await caller.value
            XCTAssertEqual(value, 42)
        }
        XCTAssertEqual(retryCreates, 1, "Old waiters must not remove or bypass the new in-flight retry")
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
            .init(discoveredCount: 1, identityCount: 1, adopted: true, identitiesPersisted: true))
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
            .init(discoveredCount: 0, identityCount: 1, adopted: true, identitiesPersisted: true))
    }

    // MARK: - StartupIdentityRecoveryPolicy

    private static let allStatuses: [WalletStartupStatus] = [
        .ready, .noIdentity, .partialNoIdentity, .partialAccountsPending,
        .discoveryFailed, .seedBindingUnverified, .identityScanIncomplete,
    ]

    private static let flags = [false, true]

    func testPipelineRunsWhenNoReadinessPassRan() {
        for discovered in Self.flags {
            XCTAssertEqual(
                StartupIdentityRecoveryPolicy.decision(
                    readinessStatus: nil, readinessIdentityId: nil, readinessDiscoveredThisStart: discovered, hasLocalIdentity: false),
                .runPipeline)
        }
    }

    func testKnownIdentityAlwaysReachesThePipeline() {
        // The guard behind adoption: whatever the status says, an identity the
        // readiness pass knows about goes through the pipeline (name refresh
        // then adopt) — past the memo when it was discovered in this start,
        // under the memo when it was already on file. Never a skip, never an
        // adoption without the name refresh.
        let identityId = Data(repeating: 0x18, count: 32)
        for status in Self.allStatuses {
            XCTAssertEqual(
                StartupIdentityRecoveryPolicy.decision(
                    readinessStatus: status, readinessIdentityId: identityId, readinessDiscoveredThisStart: false, hasLocalIdentity: true),
                .runPipeline,
                "\(status)")
            XCTAssertEqual(
                StartupIdentityRecoveryPolicy.decision(
                    readinessStatus: status, readinessIdentityId: identityId, readinessDiscoveredThisStart: true, hasLocalIdentity: false),
                .refreshNamesAndAdopt,
                "\(status) discovered")
        }
    }

    func testProvenAbsenceOnlySettlesWhenTheStoreAgrees() {
        // Rust proved the seed owns no identity, but the SwiftData mirror
        // still holds rows (or the lookup was inconclusive): adopt them
        // without a scan rather than retiring the backstop for the process.
        for discovered in Self.flags {
            for local: Bool? in [true, nil] {
                XCTAssertEqual(
                    StartupIdentityRecoveryPolicy.decision(
                        readinessStatus: .noIdentity, readinessIdentityId: nil,
                        readinessDiscoveredThisStart: discovered, hasLocalIdentity: local),
                    .runPipelineWithoutDiscovery,
                    "local=\(String(describing: local))")
            }
        }
    }

    func testOnlyProvenAbsenceSettlesTheBackstop() {
        for discovered in Self.flags {
            XCTAssertEqual(
                StartupIdentityRecoveryPolicy.decision(
                    readinessStatus: .noIdentity, readinessIdentityId: nil,
                    readinessDiscoveredThisStart: discovered, hasLocalIdentity: false),
                .skipSettled)
        }
    }

    func testLocalDiscoveryFaultRunsThePipelineWithoutAScan() {
        // The SDK says a rescan cannot answer it (`discoveryWorthRetrying ==
        // false`, `identityIsSettled == false`): no unbudgeted scan, but the
        // rows that do exist locally are still refreshed and adopted.
        for discovered in Self.flags {
            XCTAssertEqual(
                StartupIdentityRecoveryPolicy.decision(
                    readinessStatus: .discoveryFailed, readinessIdentityId: nil,
                    readinessDiscoveredThisStart: discovered, hasLocalIdentity: false),
                .runPipelineWithoutDiscovery)
        }
    }

    func testSameSeedIdentityRecoveryNeverScansWhenDiscoveryIsNotAllowed() async throws {
        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            allowDiscovery: false,
            localIdentityIds: { [] },
            discover: { XCTFail("must not scan"); return [] },
            refreshNames: { _ in XCTFail("nothing to refresh") },
            adopt: { XCTFail("nothing to adopt"); return false })
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 0, identityCount: 0, adopted: false, identitiesPersisted: false))
    }

    func testEveryOtherIdentitylessStatusRunsThePipeline() {
        // `.partialNoIdentity` (Platform or scan key unreachable, and the
        // decoder's fallback for unknown FFI statuses) is the SDK's "ask
        // again"; the settled statuses without an identity are unexpected
        // pairs and fail towards the pipeline.
        for status in Self.allStatuses where status != .noIdentity && status != .discoveryFailed {
            for discovered in Self.flags {
                XCTAssertEqual(
                    StartupIdentityRecoveryPolicy.decision(
                        readinessStatus: status, readinessIdentityId: nil,
                        readinessDiscoveredThisStart: discovered, hasLocalIdentity: false),
                    .runPipeline,
                    "\(status) discovered=\(discovered)")
            }
        }
    }

    func testProbeRerunOnlyWhenTheBudgetCutTheContactStepsShort() {
        func rerun(
            budgetExhausted: Bool = true, dashPaySyncRan: Bool = false, pending: UInt32 = 0,
            seedUnverified: Bool = false, scanIncomplete: Bool = false, found: Bool = true
        ) -> Bool {
            StartupIdentityRecoveryPolicy.probeNeedsFullRerun(
                identityFound: found, budgetExhausted: budgetExhausted, dashPaySyncRan: dashPaySyncRan,
                contactAccountsPending: pending, seedBindingUnverified: seedUnverified,
                identityScanIncomplete: scanIncomplete)
        }
        XCTAssertTrue(rerun())
        XCTAssertTrue(rerun(dashPaySyncRan: true, pending: 2))
        XCTAssertFalse(rerun(dashPaySyncRan: true, pending: 0))
        // The contact pass was degraded or failed by Platform, not cut by the
        // budget: a re-run under the default budget hits the same error.
        XCTAssertFalse(rerun(budgetExhausted: false))
        // Nothing to re-run for: the probe found no identity.
        XCTAssertFalse(rerun(found: false))
        // The drain was skipped for an unverified seed binding: the SDK fails
        // that closed on every budget, so a re-run would be pure latency.
        XCTAssertFalse(rerun(pending: 3, seedUnverified: true))
        // The probe's own scan was cut off: a re-run would rescan from scratch
        // under the default budget instead of reusing the identity.
        XCTAssertFalse(rerun(scanIncomplete: true))
    }

    func testShortStartupBudgetOnlyForGeneratedWalletKnownToHaveNoLocalIdentity() {
        XCTAssertEqual(
            StartupIdentityRecoveryPolicy.startupBudget(isGeneratedOnDevice: true, hasLocalIdentity: false),
            StartupIdentityRecoveryPolicy.generatedWalletStartupBudget)
        XCTAssertNil(StartupIdentityRecoveryPolicy.startupBudget(isGeneratedOnDevice: true, hasLocalIdentity: true))
        // Inconclusive lookup (fetch failed, no wallet row) keeps the default.
        XCTAssertNil(StartupIdentityRecoveryPolicy.startupBudget(isGeneratedOnDevice: true, hasLocalIdentity: nil))
        XCTAssertNil(StartupIdentityRecoveryPolicy.startupBudget(isGeneratedOnDevice: false, hasLocalIdentity: false))
        XCTAssertNil(StartupIdentityRecoveryPolicy.startupBudget(isGeneratedOnDevice: false, hasLocalIdentity: true))
        XCTAssertNil(StartupIdentityRecoveryPolicy.startupBudget(isGeneratedOnDevice: false, hasLocalIdentity: nil))
    }

    func testSameSeedIdentityRecoveryUsesReadinessIdentityWhenTheStoreLags() async throws {
        // Readiness discovered the identity but the persister has not landed
        // the row yet: the pipeline must refresh + adopt on the known id and
        // never run a second discovery scan.
        let identityId = Data(repeating: 0x19, count: 32)
        var discoveryCalls = 0
        var refreshedIdentityIds: [Data] = []

        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            knownIdentityIds: [identityId],
            localIdentityIds: { [] },
            discover: {
                discoveryCalls += 1
                return []
            },
            refreshNames: { refreshedIdentityIds = $0 },
            adopt: { true })

        XCTAssertEqual(discoveryCalls, 0)
        XCTAssertEqual(refreshedIdentityIds, [identityId])
        // The store never confirmed the row: the caller must not settle on it.
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 0, identityCount: 1, adopted: true, identitiesPersisted: false))
    }

    func testSameSeedIdentityRecoveryPersistenceIsPerActedOnIdentityNotPerWallet() async throws {
        // The wallet already has identity A on file; the readiness verdict
        // carries a new identity B whose row never landed. A must not vouch
        // for B.
        let identityA = Data(repeating: 0x1b, count: 32)
        let identityB = Data(repeating: 0x1c, count: 32)
        var localIds: [Data] = []
        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            knownIdentityIds: [identityB],
            localIdentityIds: {
                defer { localIds = [identityA] }   // A shows up on the re-read only
                return localIds
            },
            discover: { XCTFail("known identity must not be rediscovered"); return [] },
            refreshNames: { XCTAssertEqual($0, [identityB]) },
            adopt: { true })
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 0, identityCount: 1, adopted: true, identitiesPersisted: false))
    }

    func testSameSeedIdentityRecoveryReportsPersistenceFromTheStoreNotTheIds() async throws {
        // Discovery returned an id the persister never landed: acted on as a
        // hydration fallback, but reported as not persisted.
        let identityId = Data(repeating: 0x1a, count: 32)
        let outcome = try await SameSeedIdentityRecoveryPipeline.run(
            localIdentityIds: { [] },
            discover: { [identityId] },
            refreshNames: { _ in },
            adopt: { true })
        XCTAssertEqual(
            outcome,
            .init(discoveredCount: 1, identityCount: 1, adopted: true, identitiesPersisted: false))
    }

    // MARK: - GeneratedWalletIdentityMarker

    func testGeneratedWalletMarkerMarksClearsAndIsolatesWallets() throws {
        let suiteName = "SwiftDashSDKCoreLifecycleTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generated = Data(repeating: 0x21, count: 32)
        let imported = Data(repeating: 0x22, count: 32)

        XCTAssertFalse(GeneratedWalletIdentityMarker.isMarked(walletId: generated, defaults: defaults))

        GeneratedWalletIdentityMarker.mark(walletId: generated, defaults: defaults)
        XCTAssertTrue(GeneratedWalletIdentityMarker.isMarked(walletId: generated, defaults: defaults))
        XCTAssertFalse(GeneratedWalletIdentityMarker.isMarked(walletId: imported, defaults: defaults))

        // Clearing is idempotent and per wallet.
        GeneratedWalletIdentityMarker.clear(walletId: imported, defaults: defaults)
        XCTAssertTrue(GeneratedWalletIdentityMarker.isMarked(walletId: generated, defaults: defaults))
        GeneratedWalletIdentityMarker.clear(walletId: generated, defaults: defaults)
        XCTAssertFalse(GeneratedWalletIdentityMarker.isMarked(walletId: generated, defaults: defaults))
        GeneratedWalletIdentityMarker.clear(walletId: generated, defaults: defaults)
        XCTAssertFalse(GeneratedWalletIdentityMarker.isMarked(walletId: generated, defaults: defaults))
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

    func testStoppedPlatformSyncRequiresRuntimeRearm() {
        XCTAssertTrue(
            PlatformSyncRearmPolicy.requiresRuntimeRearm(
                isRunning: false,
                hasWalletManager: false))
        XCTAssertTrue(
            PlatformSyncRearmPolicy.requiresRuntimeRearm(
                isRunning: true,
                hasWalletManager: false))
        XCTAssertFalse(
            PlatformSyncRearmPolicy.requiresRuntimeRearm(
                isRunning: true,
                hasWalletManager: true))
    }

    /// A Platform outage must not cost the user a working Core runtime: with
    /// Core up and Platform down, the triggers that fire on their own (launch,
    /// foreground, the sync strip's Retry, "Sync Now") elide the rebuild whose
    /// `fullReset` would stop SPV, clear the balance and empty the home
    /// transaction list. This is the offline-launch regression in table form.
    func testCoreOnlyTriggersElideTheRebuildWhilePlatformIsDown() {
        typealias Trigger = SwiftDashSDKWalletRuntime.RefreshTrigger

        // Core up, Platform down.
        for trigger in [Trigger.startIfReady, .platformSyncRearm] {
            XCTAssertTrue(
                RuntimeRefreshPolicy.shouldSkipRebuild(
                    trigger: trigger, isCoreReady: true, isFullyReady: false),
                "\(trigger.rawValue) must not rebuild a healthy Core because Platform is down")
        }

        // A network switch still rebuilds on Core alone — it detached the SPV
        // subscriptions that only a rebuild re-attaches.
        XCTAssertFalse(
            RuntimeRefreshPolicy.shouldSkipRebuild(
                trigger: .networkDidChange, isCoreReady: true, isFullyReady: false))
        XCTAssertTrue(
            RuntimeRefreshPolicy.shouldSkipRebuild(
                trigger: .networkDidChange, isCoreReady: true, isFullyReady: true))

        // A wallet change never elides, however ready the runtime looks.
        for trigger in [Trigger.walletMaterialChanged, .walletDidChange] {
            XCTAssertFalse(
                RuntimeRefreshPolicy.shouldSkipRebuild(
                    trigger: trigger, isCoreReady: true, isFullyReady: true),
                "\(trigger.rawValue) must always rebind the wallet")
        }

        // Nothing elides when Core itself is down.
        for trigger in [Trigger.startIfReady, .platformSyncRearm, .networkDidChange] {
            XCTAssertFalse(
                RuntimeRefreshPolicy.shouldSkipRebuild(
                    trigger: trigger, isCoreReady: false, isFullyReady: false),
                "\(trigger.rawValue) must rebuild when Core is not running")
        }
    }

    /// `switchNetwork(to:)` detaches the SPV progress/peer/balance publishers and
    /// clears wallet state BEFORE its own refresh reaches the lifecycle queue,
    /// without clearing Core's running flag. A refresh queued in that window
    /// must not elide: `isCoreRuntimeReady` reports `false` there because
    /// `subscriptionsDetached` is set, so every trigger rebuilds and the
    /// publishers are re-attached. Eliding instead would strand the runtime with
    /// no subscriptions and a cleared balance that no later refresh repairs.
    func testNoTriggerElidesWhileSwitchPreparationHasDetachedSubscriptions() {
        typealias Trigger = SwiftDashSDKWalletRuntime.RefreshTrigger
        let target = Network.testnet

        // The state `prepareForNetworkSwitch()` leaves behind: host still bound,
        // Core SPV still flagged running on the target, publishers detached.
        // Readiness is computed here rather than asserted as a literal, so
        // dropping the `subscriptionsDetached` term from the predicate fails
        // this test instead of silently restoring the defect.
        let preparedCoreReady = RuntimeReadinessPolicy.isCoreReady(
            boundNetwork: target, target: target, hasBoundWallet: true,
            isSPVRunning: true, subscriptionsDetached: true)
        XCTAssertFalse(preparedCoreReady, "detached subscriptions must make Core unready")

        let preparedFullyReady = RuntimeReadinessPolicy.isFullyReady(
            isCoreReady: preparedCoreReady, isBlastRunning: true,
            blastNetwork: target, target: target)
        XCTAssertFalse(preparedFullyReady, "full readiness must not outrank detached Core")

        // With those computed values, nothing may elide the rebuild.
        for trigger in [Trigger.startIfReady, .platformSyncRearm, .networkDidChange,
                        .walletMaterialChanged, .walletDidChange] {
            XCTAssertFalse(
                RuntimeRefreshPolicy.shouldSkipRebuild(
                    trigger: trigger, isCoreReady: preparedCoreReady, isFullyReady: preparedFullyReady),
                "\(trigger.rawValue) must rebuild while the switch preparation has detached the subscriptions")
        }

        // Re-attaching the publishers makes the same runtime ready again, and
        // the Core-only triggers go back to eliding.
        let reattachedCoreReady = RuntimeReadinessPolicy.isCoreReady(
            boundNetwork: target, target: target, hasBoundWallet: true,
            isSPVRunning: true, subscriptionsDetached: false)
        XCTAssertTrue(reattachedCoreReady, "re-attached subscriptions must restore Core readiness")

        for trigger in [Trigger.startIfReady, .platformSyncRearm] {
            XCTAssertTrue(
                RuntimeRefreshPolicy.shouldSkipRebuild(
                    trigger: trigger, isCoreReady: reattachedCoreReady, isFullyReady: false))
        }
    }

    func testWalletWithoutPlatformPaymentAccountUsesNeutralState() {
        let availability = PlatformAccountAvailabilityPolicy.resolve(
            hasWalletRecord: true,
            hasPlatformPaymentAccount: false)

        XCTAssertEqual(availability, .unavailable)
        XCTAssertNil(
            PlatformSyncStatusPresentationPolicy.visibleError(
                availability: availability,
                lastError: "Platform wallet not configured"))
    }

    func testMissingWalletRecordRemainsUnknownInsteadOfClaimingNoPlatformWallet() {
        XCTAssertEqual(
            PlatformAccountAvailabilityPolicy.resolve(
                hasWalletRecord: false,
                hasPlatformPaymentAccount: false),
            .unknown)
    }

    func testPlatformActivityConvertsCreditsToDuffsBeforeMatchingUnshield() {
        let creditedAmount: UInt64 = 10_000_000_000

        XCTAssertEqual(
            PlatformAddressActivityUnitPolicy.duffs(fromCredits: creditedAmount),
            10_000_000)
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: 10_000_000))
        // Non-positive deltas are never own-operation residue.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: 0))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: -1))
        // A credits-vs-duffs unit mixup must never pass as a match.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldCoversDelta(
            creditedAmountCredits: creditedAmount,
            observedDeltaDuffs: Int64(creditedAmount)))
    }

    func testOwnUnshieldSuppressionAcceptsOnlyLiveUnshieldWithPlatformCounterparty() {
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.unshield.rawValue,
            counterpartyLength: 21))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.shieldedSpend.rawValue,
            counterpartyLength: 21))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.shieldedSpend.rawValue,
            counterpartyLength: 43))
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.isOwnUnshieldCandidate(
            kindTag: ShieldedActivityItem.Kind.received.rawValue,
            counterpartyLength: 21))
    }

    func testOwnUnshieldSuppressionDoesNotMatchAnExternalReceive() {
        // Different address: never suppressed, whatever the amount.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1external",
            creditedAmountCredits: 10_000_000_000,
            observedDeltaDuffs: 10_000_000))
        // Same address, delta LARGER than the credited principal: more
        // money arrived than the own unshield explains — not residue.
        XCTAssertFalse(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 10_000_000_000,
            observedDeltaDuffs: 10_000_001))
    }

    func testOwnUnshieldSuppressionCoversTopUpResidue() {
        // Shielded identity top-up: unshield lands 0.05, the top-up claims
        // most of it before the next sync, so the observed delta is the
        // small remainder — still the own operation's residue.
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 5_000_000_000,
            observedDeltaDuffs: 198_000))
        // The full principal (no follow-on spend) still matches.
        XCTAssertTrue(PlatformAddressActivityUnitPolicy.unshieldResidueMatches(
            destinationAddress: "tdash1own",
            observedAddress: "tdash1own",
            creditedAmountCredits: 5_000_000_000,
            observedDeltaDuffs: 5_000_000))
    }

    func testPlatformActivityUnitMigrationKeepsPrereleaseVersion() {
        XCTAssertEqual(NormalizePlatformAddressActivityUnits().version, 20260727140000)
    }

    func testPlatformActivityInitialBaselineIncludesZeroBalanceAddresses() {
        let balances = PlatformAddressActivityUnitPolicy.initialBaselineBalances(addresses: [
            DerivedPlatformAddress(
                address: "tdash1zero",
                accountIndex: 0,
                addressIndex: 0,
                isUsed: false,
                balance: 0),
            DerivedPlatformAddress(
                address: "tdash1funded",
                accountIndex: 0,
                addressIndex: 1,
                isUsed: true,
                balance: 5_000),
        ])

        XCTAssertEqual(balances["tdash1zero"], 0)
        XCTAssertEqual(balances["tdash1funded"], 5)
    }

    func testReceiveFilterAcceptsOnlySDKClassifiedExternalReceives() {
        XCTAssertTrue(ReceivedAtAddressTransactionFilter.matches(
            direction: .received,
            ownOutputAddresses: ["yReceive"],
            address: "yReceive"))
        XCTAssertFalse(ReceivedAtAddressTransactionFilter.matches(
            direction: .moved,
            ownOutputAddresses: ["yReceive"],
            address: "yReceive"))
        XCTAssertFalse(ReceivedAtAddressTransactionFilter.matches(
            direction: .received,
            ownOutputAddresses: ["yDifferent"],
            address: "yReceive"))
    }

    func testReceiveCoreContextMappingAndStatusNeverRegresses() {
        XCTAssertEqual(ReceiveReceiptPolicy.coreStatus(context: 0), .mempool)
        XCTAssertEqual(ReceiveReceiptPolicy.coreStatus(context: 1), .instantSend)
        XCTAssertEqual(ReceiveReceiptPolicy.coreStatus(context: 2), .inBlock)
        XCTAssertEqual(ReceiveReceiptPolicy.coreStatus(context: 3), .chainLocked)
        XCTAssertNil(ReceiveReceiptPolicy.coreStatus(context: 4))
        XCTAssertEqual(
            ReceiveReceiptPolicy.strongestStatus(
                current: .inBlock,
                observed: .mempool),
            .inBlock)
    }

    func testReceiveShieldedCooldownSkipIsNotProjected() {
        XCTAssertFalse(ReceiveReceiptPolicy.shouldProjectShieldedResult(
            success: true,
            cooldownSkip: true))
        XCTAssertFalse(ReceiveReceiptPolicy.shouldProjectShieldedResult(
            success: false,
            cooldownSkip: false))
        XCTAssertTrue(ReceiveReceiptPolicy.shouldProjectShieldedResult(
            success: true,
            cooldownSkip: false))
    }

    func testAttendedPlatformRefreshRequiresRunningAvailableAccount() {
        XCTAssertFalse(ReceiveReceiptPolicy.canRefreshPlatform(
            isRunning: false,
            availability: .available))
        XCTAssertFalse(ReceiveReceiptPolicy.canRefreshPlatform(
            isRunning: true,
            availability: .unknown))
        XCTAssertFalse(ReceiveReceiptPolicy.canRefreshPlatform(
            isRunning: true,
            availability: .unavailable))
        XCTAssertTrue(ReceiveReceiptPolicy.canRefreshPlatform(
            isRunning: true,
            availability: .available))
    }

    func testCoreToShieldedPoolFeeDuffsRoundsUpToCoverTheCreditFee() {
        // A 200-credit remainder rounds up to the next whole duff…
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.poolFeeDuffs(poolFeeCredits: 212_851_200),
            212_852)
        // …while an exact duff multiple must NOT gain a spurious +1.
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.poolFeeDuffs(poolFeeCredits: 212_851_000),
            212_851)
    }

    func testCoreToShieldedLockValueIsAmountPlusRoundedUpFee() {
        // Fee-on-top: the lock delivers the full typed amount to the pool.
        XCTAssertEqual(
            CoreToShieldedAmountPolicy.lockValueDuffs(
                forAmountDuffs: 1_000_000,
                poolFeeCredits: 212_851_200),
            1_212_852)
    }

    func testCoreToShieldedLockValueFailsClosedOnOverflow() {
        XCTAssertNil(
            CoreToShieldedAmountPolicy.lockValueDuffs(
                forAmountDuffs: UInt64.max,
                poolFeeCredits: 212_851_200))
    }

    // MARK: Core → Platform static reserve policy
    //
    // Pure reserve math for the DPP static address-funding floor. Runtime
    // failure to resolve the SDK estimate is ViewModel/coordinator state
    // handled in `InternalTransferViewModel` and exercised by the testnet
    // smoke while the unit-test target stays broken.

    private static let addressFundingReserveCredits: UInt64 = 62_000_000

    func testCoreToPlatformReserveIsTheRoundedUpStaticFundingFee() {
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.reserveDuffs(
                forAmountDuffs: 5_000_000,
                reserveCredits: Self.addressFundingReserveCredits),
            62_000)
        // An exact duff multiple must NOT gain a spurious +1.
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.reserveDuffs(reserveCredits: 15_000_000),
            15_000)
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.reserveDuffs(reserveCredits: 15_000_001),
            15_001)
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.lockValueDuffs(
                forAmountDuffs: 5_000_000,
                reserveCredits: Self.addressFundingReserveCredits),
            5_062_000)
    }

    func testCoreToPlatformTinyAmountLocksAmountPlusStaticReserve() {
        let reserve = CoreToPlatformAmountPolicy.reserveDuffs(
            forAmountDuffs: 1,
            reserveCredits: Self.addressFundingReserveCredits)
        XCTAssertEqual(reserve, 62_000)
        let lock = CoreToPlatformAmountPolicy.lockValueDuffs(
            forAmountDuffs: 1,
            reserveCredits: Self.addressFundingReserveCredits)
        XCTAssertEqual(lock, 62_001)
    }

    func testCoreToPlatformMaxAmountLockEqualsTheSpendable() {
        // Confirmation/execution consistency at Max: the amount Max fills
        // (spendable − rounded-up fee) locks EXACTLY the spendable balance
        // — the confirmed Total, the frozen submission lock, and the
        // executed lock all come from `lockValueDuffs`, so they cannot
        // diverge.
        let spendable: UInt64 = 4_043_550_440
        let maxAmount = CoreToPlatformAmountPolicy.maxAmountDuffs(
            spendableDuffs: spendable,
            reserveCredits: Self.addressFundingReserveCredits)
        XCTAssertEqual(maxAmount, spendable - 62_000)
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.lockValueDuffs(
                forAmountDuffs: maxAmount,
                reserveCredits: Self.addressFundingReserveCredits),
            spendable)
    }

    func testCoreToPlatformMaxFailsClosedWhenTheBalanceCannotFund() {
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.maxAmountDuffs(
                spendableDuffs: 62_000,
                reserveCredits: Self.addressFundingReserveCredits),
            0)
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.maxAmountDuffs(
                spendableDuffs: 62_001,
                reserveCredits: Self.addressFundingReserveCredits),
            1)
    }

    func testCoreToPlatformMaxNeverFillsAnAmountContinueRejects() {
        // At the UInt64 boundary the duffs→credits conversion overflows, so
        // an uncapped Max would fill an amount `lockValueDuffs` refuses.
        // Max caps at the largest representable amount instead — every
        // filled amount stays submittable.
        let maxAmount = CoreToPlatformAmountPolicy.maxAmountDuffs(
            spendableDuffs: .max,
            reserveCredits: Self.addressFundingReserveCredits)
        XCTAssertEqual(maxAmount, UInt64.max / 1000)
        XCTAssertNotNil(
            CoreToPlatformAmountPolicy.lockValueDuffs(
                forAmountDuffs: maxAmount,
                reserveCredits: Self.addressFundingReserveCredits))
    }

    func testCoreToPlatformMaxHeldBackExcludesTheFundingReserve() {
        // The held-back notice describes what STAYS in Core after the Max
        // lock executes. The reserve leaves Core inside the lock, so it
        // must never be counted as held back.
        let spendable: UInt64 = 4_043_550_440
        let maxAmount = CoreToPlatformAmountPolicy.maxAmountDuffs(
            spendableDuffs: spendable,
            reserveCredits: Self.addressFundingReserveCredits)

        // Whole balance spendable: Max locks all of it — nothing stays in
        // Core, so no notice.
        XCTAssertNil(
            CoreToPlatformAmountPolicy.maxHeldBackDuffs(
                coreBalanceDuffs: spendable,
                maxAmountDuffs: maxAmount,
                reserveCredits: Self.addressFundingReserveCredits))

        // With unconfirmed coins on top of the spendable envelope, the
        // held-back value is exactly those coins.
        let unconfirmed: UInt64 = 123_456
        XCTAssertEqual(
            CoreToPlatformAmountPolicy.maxHeldBackDuffs(
                coreBalanceDuffs: spendable + unconfirmed,
                maxAmountDuffs: maxAmount,
                reserveCredits: Self.addressFundingReserveCredits),
            unconfirmed)
    }

    func testCoreToPlatformLockValueFailsClosedOnOverflow() {
        // amount × 1000 credits overflows.
        XCTAssertNil(
            CoreToPlatformAmountPolicy.reserveDuffs(
                forAmountDuffs: UInt64.max,
                reserveCredits: Self.addressFundingReserveCredits))
        XCTAssertNil(
            CoreToPlatformAmountPolicy.lockValueDuffs(
                forAmountDuffs: UInt64.max,
                reserveCredits: Self.addressFundingReserveCredits))
        // The largest amount whose credits fit still resolves (amount +
        // reserve cannot overflow once amount × 1000 fits — the checked
        // add in `lockValueDuffs` is defensive).
        let nearMax = UInt64.max / 1000
        XCTAssertNotNil(
            CoreToPlatformAmountPolicy.lockValueDuffs(
                forAmountDuffs: nearMax,
                reserveCredits: Self.addressFundingReserveCredits))
    }

    func testCoreToPlatformAddressPairUsesTwoUnusedP2PKHAddresses() throws {
        let used = try platformFundingAddress(
            hashByte: 0x01,
            addressIndex: 0,
            isUsed: true)
        let recipient = try platformFundingAddress(hashByte: 0x02, addressIndex: 1)
        let remainder = try platformFundingAddress(hashByte: 0x03, addressIndex: 2)

        let pair = try PlatformAddressSyncCoordinator.resolveCoreToPlatformAddressPair(
            from: [remainder, used, recipient])

        XCTAssertEqual(pair.recipient.row, recipient)
        XCTAssertEqual(pair.remainder.row, remainder)
    }

    func testCoreToPlatformAddressPairFallsBackToUsedRemainderAddress() throws {
        let recipient = try platformFundingAddress(hashByte: 0x01, addressIndex: 0)
        let usedRemainder = try platformFundingAddress(
            hashByte: 0x02,
            addressIndex: 1,
            isUsed: true)

        let pair = try PlatformAddressSyncCoordinator.resolveCoreToPlatformAddressPair(
            from: [usedRemainder, recipient])

        XCTAssertEqual(pair.recipient.row, recipient)
        XCTAssertEqual(pair.remainder.row, usedRemainder)
    }

    func testCoreToPlatformAddressPairRequiresTwoP2PKHAddresses() throws {
        let recipient = try platformFundingAddress(hashByte: 0x01, addressIndex: 0)
        let p2shOnly = try platformFundingAddress(
            typeByte: 0x80,
            hashByte: 0x02,
            addressIndex: 1)

        XCTAssertThrowsError(
            try PlatformAddressSyncCoordinator.resolveCoreToPlatformAddressPair(
                from: [p2shOnly, recipient]))
    }

    private func platformFundingAddress(
        typeByte: UInt8 = 0xb0,
        hashByte: UInt8,
        accountIndex: UInt32 = 0,
        addressIndex: UInt32,
        isUsed: Bool = false
    ) throws -> DerivedPlatformAddress {
        let payload = Data([typeByte] + Array(repeating: hashByte, count: 20))
        let address = try XCTUnwrap(Bech32m.encode(hrp: "tdash", data: payload))
        return DerivedPlatformAddress(
            address: address,
            accountIndex: accountIndex,
            addressIndex: addressIndex,
            isUsed: isUsed,
            balance: 0)
    }

    func testShieldedSweepChoosesPrefixWithLargestNetPayout() {
        let fees: [Int: UInt64] = [2: 100, 3: 150]

        let candidate = ShieldedSweepPlanner.bestCandidate(
            noteValues: [1_000, 1_000, 1],
            feeForActions: { fees[$0] })

        XCTAssertEqual(
            candidate,
            ShieldedSweepCandidate(
                amountCredits: 1_900,
                inputCredits: 2_000,
                feeCredits: 100,
                noteCount: 2))
        XCTAssertEqual(
            ShieldedSweepPlanner.revalidate(
                noteValues: [1_000, 1_000, 1],
                amountCredits: 1_900,
                feeForActions: { fees[$0] }),
            candidate)
    }

    func testShieldedSweepUsesSpendablePrefixWhenFullPrefixCannotPayFee() {
        let notes = [UInt64(200), 100] + Array(repeating: UInt64(1), count: 14)

        let candidate = ShieldedSweepPlanner.bestCandidate(
            noteValues: notes,
            feeForActions: { actions in actions <= 2 ? 100 : 1_000 })

        XCTAssertEqual(
            candidate,
            ShieldedSweepCandidate(
                amountCredits: 200,
                inputCredits: 300,
                feeCredits: 100,
                noteCount: 2))
    }

    func testShieldedSweepStopsAtTheActionBudget() {
        // The 20 KiB `max_state_transition_size` ceiling, not the 16-action
        // consensus cap, is what bounds a bundle: a 7-action transition is
        // ~21,699 B and DAPI rejects it. The planner must stop at the budget
        // even when every further note would raise the payout.
        let notes = Array(repeating: UInt64(1_000), count: 12)
        let budget = ShieldedActionBudget.maxActionsPerTransition

        let candidate = ShieldedSweepPlanner.bestCandidate(
            noteValues: notes,
            feeForActions: { _ in 100 })

        XCTAssertEqual(candidate?.noteCount, budget)
        XCTAssertEqual(candidate?.inputCredits, UInt64(budget) * 1_000)
        XCTAssertEqual(candidate?.amountCredits, UInt64(budget) * 1_000 - 100)
    }

    func testShieldedSweepSkipsNotesWorthLessThanTheirAction() {
        // A note below the marginal fee of the action that would spend it
        // lowers the payout, so the planner must leave it. The 1-credit note
        // here is exactly that case: taking it would cost 50 and gain 1.
        let fees: [Int: UInt64] = [2: 100, 3: 150]

        let candidate = ShieldedSweepPlanner.bestCandidate(
            noteValues: [1_000, 500, 1],
            feeForActions: { fees[$0] })

        XCTAssertEqual(candidate?.noteCount, 2)
        XCTAssertEqual(candidate?.inputCredits, 1_500)
        XCTAssertEqual(candidate?.amountCredits, 1_400)

        // And a follow-up sweep of that leftover pays out nothing, which is
        // what tells the UI to stop inviting the user to retry.
        XCTAssertNil(
            ShieldedSweepPlanner.bestCandidate(
                noteValues: [1],
                feeForActions: { fees[$0] }))
    }

    func testShieldedSpendableBalanceSubtractsFeeReserve() {
        XCTAssertEqual(
            TransferSpendAmountPolicy.spendableCredits(
                balanceCredits: 10_000_000_000,
                feeReserveCredits: 2_000_000_000),
            8_000_000_000)
        XCTAssertEqual(
            TransferSpendAmountPolicy.spendableCredits(
                balanceCredits: 1_000_000_000,
                feeReserveCredits: 2_000_000_000),
            0)
    }

    func testPlatformShieldScreenshotRegressionUsesSDKSelectableCapacity() {
        let capacity = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 3_921_114_000,
            usableBalanceCredits: 3_623_849_220,
            feeReserveCredits: 1_000_000_000,
            maxShieldableCredits: 2_623_849_220)

        // Old aggregate-balance Max from the report must be rejected.
        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 2_921_114_000,
            capacity: capacity))
        // The displayed Max is the SDK ceiling floored to whole duffs.
        XCTAssertEqual(
            PlatformShieldAmountPolicy.maximumDuffs(capacity: capacity),
            2_623_849)
        XCTAssertTrue(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 2_623_849_000,
            capacity: capacity))
    }

    func testPlatformShieldRejectsOneDuffAboveDisplayedMax() {
        let capacity = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 3_921_114_000,
            usableBalanceCredits: 3_623_849_220,
            feeReserveCredits: 1_000_000_000,
            maxShieldableCredits: 2_623_849_220)

        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 2_623_850_000,
            capacity: capacity))
    }

    func testPlatformShieldRejectsZeroAndUnshieldableCapacity() {
        let unshieldable = PlatformShieldCapacity(
            canShield: false,
            accountBalanceCredits: 3_921_114_000,
            usableBalanceCredits: 0,
            feeReserveCredits: 1_000_000_000,
            maxShieldableCredits: 0,
            reason: "insufficient headroom")

        XCTAssertEqual(
            PlatformShieldAmountPolicy.maximumDuffs(capacity: unshieldable),
            0)
        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 1_000,
            capacity: unshieldable))

        let shieldable = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 3_921_114_000,
            usableBalanceCredits: 3_623_849_220,
            feeReserveCredits: 1_000_000_000,
            maxShieldableCredits: 2_623_849_220)
        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 0,
            capacity: shieldable))
    }

    func testPlatformShieldMaxFloorsSubDuffCredits() {
        let capacity = PlatformShieldCapacity(
            canShield: true,
            accountBalanceCredits: 5_000,
            usableBalanceCredits: 5_000,
            feeReserveCredits: 1_000,
            maxShieldableCredits: 3_999)

        XCTAssertEqual(
            PlatformShieldAmountPolicy.maximumDuffs(capacity: capacity),
            3)
    }

    func testPlatformShieldHeldBackNoticeUsesDisplayedAggregateBalance() {
        XCTAssertEqual(
            PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: 4_500_000_000,
                accountBalanceCredits: 3_921_114_000,
                submittedDuffs: 2_623_849),
            1_876_151_000)

        // If the published aggregate briefly lags, do not understate the
        // account-level remainder reported by the coherent SDK preflight.
        XCTAssertEqual(
            PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: 3_000_000_000,
                accountBalanceCredits: 3_921_114_000,
                submittedDuffs: 2_623_849),
            1_297_265_000)
    }

    func testPlatformShieldHeldBackIsZeroForOverflowAndFullySubmittedBalance() {
        XCTAssertEqual(
            PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: 4_500_000_000,
                accountBalanceCredits: 3_921_114_000,
                submittedDuffs: UInt64.max),
            0)
        XCTAssertEqual(
            PlatformShieldAmountPolicy.heldBackCredits(
                displayedPlatformCredits: 2_623_849_000,
                accountBalanceCredits: 2_623_849_000,
                submittedDuffs: 2_623_849),
            0)
    }

    func testPlatformShieldFailsClosedWithoutResolvedPreflight() {
        XCTAssertFalse(PlatformShieldAmountPolicy.canSubmit(
            requestedCredits: 1_000,
            capacity: nil))
    }

    func testPlatformShieldStaleCacheWaitsForBalancePublication() {
        XCTAssertFalse(PlatformShieldAmountPolicy.shouldRefreshPreflight(
            after: .other,
            awaitingPlatformResync: true))
        XCTAssertTrue(PlatformShieldAmountPolicy.shouldRefreshPreflight(
            after: .balancePublished,
            awaitingPlatformResync: true))
        XCTAssertTrue(PlatformShieldAmountPolicy.shouldRefreshPreflight(
            after: .other,
            awaitingPlatformResync: false))
        XCTAssertTrue(PlatformShieldAmountPolicy.awaitingPlatformResync(
            current: true,
            after: .other))
        XCTAssertFalse(PlatformShieldAmountPolicy.awaitingPlatformResync(
            current: true,
            after: .balancePublished))
        XCTAssertTrue(PlatformShieldAmountPolicy.shouldStartManualResync(
            awaitingPlatformResync: true,
            retryInFlight: false))
        XCTAssertFalse(PlatformShieldAmountPolicy.shouldStartManualResync(
            awaitingPlatformResync: true,
            retryInFlight: true))
        XCTAssertFalse(PlatformShieldAmountPolicy.shouldStartManualResync(
            awaitingPlatformResync: false,
            retryInFlight: false))
    }

    func testPlatformShieldCapacityChangeUpdatesOnlyMaxDerivedAmount() {
        XCTAssertEqual(
            PlatformShieldAmountPolicy.amountAfterCapacityChange(
                currentDuffs: 2_921_114,
                wasMaxDerived: true,
                maxShieldableCredits: 2_623_849_220),
            2_623_849)
        XCTAssertEqual(
            PlatformShieldAmountPolicy.amountAfterCapacityChange(
                currentDuffs: 2_700_000,
                wasMaxDerived: false,
                maxShieldableCredits: 2_623_849_220),
            2_700_000)
        // A typed insufficient-balance failure followed by a failed preflight
        // must not invent a zero Max or silently alter the confirmed value.
        XCTAssertEqual(
            PlatformShieldAmountPolicy.amountAfterCapacityChange(
                currentDuffs: 2_921_114,
                wasMaxDerived: true,
                maxShieldableCredits: nil),
            2_921_114)
    }

    func testShieldedInsufficientBalanceMessageUsesSpendableAmount() {
        let message = TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: "Shielded",
            requestedCredits: 8_000_000_001,
            balanceCredits: 10_000_000_000,
            feeReserveCredits: 2_000_000_000)

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Shielded") == true)
        XCTAssertTrue(
            message?.contains("0.08 DASH") == true
                || message?.contains("0,08 DASH") == true)
        XCTAssertNil(
            TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: "Shielded",
                requestedCredits: 8_000_000_000,
                balanceCredits: 10_000_000_000,
                feeReserveCredits: 2_000_000_000))
    }

    func testDuffDenominatedInsufficientBalanceMessageNamesTheBalance() {
        let message = TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: "Transparent",
            requestedDuffs: 50_000_000,
            spendableDuffs: 40_000_000)

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Transparent") == true)
        XCTAssertTrue(
            message?.contains("0.4 DASH") == true
                || message?.contains("0,4 DASH") == true)
        XCTAssertNil(
            TransferSpendAmountPolicy.insufficientBalanceMessage(
                balanceName: "Transparent",
                requestedDuffs: 40_000_000,
                spendableDuffs: 40_000_000))
    }

    func testUniqueWithdrawalAddressMatchesDespiteRestoreTimeAndAmountSkew() {
        let activityDate = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CoreWithdrawalReceiptMatchPolicy.selectedIndex(
                expectedAmountDuffs: 2_000,
                activityDate: activityDate,
                candidates: [
                    CoreWithdrawalReceiptCandidate(
                        amountDuffs: 1_950,
                        date: activityDate.addingTimeInterval(-172_800)),
                ]),
            0)
    }

    func testReusedWithdrawalAddressUsesUniqueAmountAndTimeMatch() {
        let activityDate = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            CoreWithdrawalReceiptMatchPolicy.selectedIndex(
                expectedAmountDuffs: 2_000,
                activityDate: activityDate,
                candidates: [
                    CoreWithdrawalReceiptCandidate(
                        amountDuffs: 2_000,
                        date: activityDate.addingTimeInterval(-172_800)),
                    CoreWithdrawalReceiptCandidate(
                        amountDuffs: 2_000,
                        date: activityDate.addingTimeInterval(60)),
                ]),
            1)
    }

    func testAmbiguousReusedWithdrawalAddressRemainsPending() {
        let activityDate = Date(timeIntervalSince1970: 1_000_000)
        let candidates = [
            CoreWithdrawalReceiptCandidate(
                amountDuffs: 2_000,
                date: activityDate.addingTimeInterval(60)),
            CoreWithdrawalReceiptCandidate(
                amountDuffs: 2_000,
                date: activityDate.addingTimeInterval(120)),
        ]

        XCTAssertNil(
            CoreWithdrawalReceiptMatchPolicy.selectedIndex(
                expectedAmountDuffs: 2_000,
                activityDate: activityDate,
                candidates: candidates))
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

final class JoinDashPayBannerPolicyTests: XCTestCase {
    func testDismissalHidesBannerBeforeIdentityExists() {
        XCTAssertFalse(
            JoinDashPayBannerPolicy.shouldShow(
                contextReady: true,
                syncDone: true,
                dismissed: true,
                hasRegisteredUsername: false,
                hasRegistrationInProgress: false))
    }

    func testEligibleUndismissedWalletShowsBanner() {
        XCTAssertTrue(
            JoinDashPayBannerPolicy.shouldShow(
                contextReady: true,
                syncDone: true,
                dismissed: false,
                hasRegisteredUsername: false,
                hasRegistrationInProgress: false))
    }

    func testDismissalStorageIsScopedByNetworkAndWallet() {
        let testnetWalletA = JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.NetworkKind.testnet.rawValue,
            walletIdHex: "wallet-a")
        let mainnetWalletA = JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.NetworkKind.mainnet.rawValue,
            walletIdHex: "wallet-a")
        let testnetWalletB = JoinDashPayDismissalScope.storageKey(
            networkRawValue: WalletEnvironment.NetworkKind.testnet.rawValue,
            walletIdHex: "wallet-b")

        XCTAssertNotEqual(testnetWalletA, mainnetWalletA)
        XCTAssertNotEqual(testnetWalletA, testnetWalletB)
        XCTAssertEqual(
            testnetWalletA,
            JoinDashPayDismissalScope.storageKey(
                networkRawValue: WalletEnvironment.NetworkKind.testnet.rawValue,
                walletIdHex: "wallet-a"))
    }
}

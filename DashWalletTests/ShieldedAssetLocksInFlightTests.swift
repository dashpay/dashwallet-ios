//
//  ShieldedAssetLocksInFlightTests.swift
//  DashWalletTests
//
//  Ownership of the asset locks a running transfer is consuming (#1042 /
//  PR #1212). A fresh transfer's lock is claimed by the SDK's built-lock
//  callback on the FFI worker thread; the coordinator takes that claim over
//  when the call returns, and leaving the in-flight phases releases it. A
//  lock that is still claimed must refuse a second attempt.
//

import Combine
import XCTest
import SwiftDashSDK
@testable import dashpay

final class ShieldedAssetLocksInFlightTests: XCTestCase {

    private typealias OutPoint = ShieldedAssetLocksInFlight.OutPoint

    private let lockA = OutPoint(txidWire: Data(repeating: 0xA1, count: 32), vout: 0)
    private let lockB = OutPoint(txidWire: Data(repeating: 0xB2, count: 32), vout: 0)

    /// The tests run inside the app, which reads `shared`. Drop whatever a
    /// failed assertion left claimed there so it can't leak into the app or
    /// the next test.
    override func tearDown() {
        let shared = ShieldedAssetLocksInFlight.shared
        let locks = [lockA, lockB, resumedLock]
        MainActor.assumeIsolated {
            for lock in locks {
                while shared.contains(lock, drainOperation: nil) { shared.release(lock) }
            }
        }
        super.tearDown()
    }

    // MARK: - Core Sync's pending list

    /// The Core Sync screen keeps its pending list in state and re-reads it
    /// on these emissions, so a lock whose running attempt fails while the
    /// screen is up comes back on it, and one probed already spent leaves.
    @MainActor
    func testThePendingListIsAnnouncedWhenARunningAttemptReleasesItsLock() {
        let registry = ShieldedAssetLocksInFlight()
        let lookup = ShieldedTxLookup()
        let probes = AssetLockProbeStore.shared
        let probeWallet = "pendingRecoveriesChangesTest"
        // A run killed before its cleanup leaves the probe filed, and a
        // repeat record posts nothing.
        probes.clearForWallet(walletIdHex: probeWallet)
        defer { probes.clearForWallet(walletIdHex: probeWallet) }
        var emissions = 0
        let subscription = AssetLockRecoveryService
            .pendingRecoveriesChanges(lookup: lookup, registry: registry, probes: probes)
            .sink { emissions += 1 }
        /// Runs the main queue until `count` emissions, then a little longer
        /// so a further one has a chance to land.
        func drain(until count: Int) {
            let deadline = Date().addingTimeInterval(10)
            while emissions < count, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        registry.claim(lockA)
        drain(until: 1)
        XCTAssertEqual(emissions, 1, "the attempt claimed its lock")

        registry.release(lockA)
        drain(until: 2)
        XCTAssertEqual(emissions, 2, "the attempt failed and released it")

        lookup.markConsumed(txidWire: lockB.txidWire)
        drain(until: 3)
        XCTAssertEqual(emissions, 3, "the lookup changed")

        probes.record(txid: lockA.txidWire, vout: lockA.vout, walletIdHex: probeWallet)
        drain(until: 4)
        XCTAssertEqual(emissions, 4, "the lock was probed already spent")

        probes.clearForWallet(walletIdHex: probeWallet)
        drain(until: 5)
        XCTAssertEqual(emissions, 5, "the probes were cleared")
        subscription.cancel()
    }

    // MARK: - Registry

    @MainActor
    func testClaimsAreCountedPerLock() {
        let registry = ShieldedAssetLocksInFlight()
        registry.claim(lockA)
        registry.claim(lockA)

        registry.release(lockA)
        XCTAssertTrue(registry.contains(lockA, drainOperation: nil), "one claim is still held")

        registry.release(lockA)
        XCTAssertFalse(registry.contains(lockA, drainOperation: nil))
        XCTAssertFalse(registry.hasActivity)
    }

    @MainActor
    func testLocksAreIndependent() {
        let registry = ShieldedAssetLocksInFlight()
        registry.claim(lockA)

        XCTAssertFalse(registry.contains(lockB, drainOperation: nil))
        XCTAssertTrue(registry.containsTransaction(txidWire: lockA.txidWire, drainOperation: nil))
        XCTAssertFalse(registry.containsTransaction(txidWire: lockB.txidWire, drainOperation: nil))

        registry.release(lockB)
        XCTAssertTrue(registry.contains(lockA, drainOperation: nil), "releasing another lock leaves this claim")
    }

    @MainActor
    func testBuiltLockClaimIsVisibleBeforeItsPublication() {
        let registry = ShieldedAssetLocksInFlight()
        let published = expectation(description: "objectWillChange on the main queue")
        let subscription = registry.objectWillChange.sink {
            XCTAssertTrue(Thread.isMainThread, "SwiftUI observers must hear the change on main")
            published.fulfill()
        }

        let claimedOnWorker = expectation(description: "claim on a worker thread")
        DispatchQueue.global().async {
            registry.claimBuiltLock(self.lockA)
            // The SDK persists the lock's row right after the callback
            // returns, so the claim must already be readable here.
            XCTAssertTrue(registry.contains(self.lockA, drainOperation: nil))
            claimedOnWorker.fulfill()
        }

        wait(for: [claimedOnWorker, published], timeout: 2)
        subscription.cancel()
        registry.release(lockA)
        XCTAssertFalse(registry.contains(lockA, drainOperation: nil))
    }

    @MainActor
    func testFundingCallsCountAsActivityBeforeAnyLockExists() {
        let registry = ShieldedAssetLocksInFlight()
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertTrue(registry.hasActivity)

        registry.endFundingCall()
        XCTAssertTrue(registry.hasActivity, "the second call is still running")
        registry.endFundingCall()
        XCTAssertFalse(registry.hasActivity)

        // An extra end must not go below zero: the next call still counts.
        registry.endFundingCall()
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertTrue(registry.hasActivity)
        registry.endFundingCall()
        XCTAssertFalse(registry.hasActivity)
    }

    @MainActor
    func testARemovalIsAdmittedOnlyWithoutActivityAndHoldsOffTransfers() {
        let registry = ShieldedAssetLocksInFlight()
        registry.claim(lockA)
        XCTAssertEqual(registry.beginRemoval(), .transferActive, "a lock is being consumed")
        registry.release(lockA)
        XCTAssertTrue(registry.beginFundingCall())
        XCTAssertEqual(registry.beginRemoval(), .transferActive, "a fresh transfer is running")
        registry.endFundingCall()

        // Screens offering a removal or a retry rebuild when the hold starts
        // and when it ends.
        var published = 0
        let subscription = registry.objectWillChange.sink { published += 1 }
        defer { subscription.cancel() }

        XCTAssertEqual(registry.beginRemoval(), .admitted)
        XCTAssertEqual(published, 1)
        XCTAssertTrue(registry.isRemovalInProgress)
        XCTAssertEqual(registry.beginRemoval(), .removalHeld, "one removal at a time")
        XCTAssertFalse(registry.beginFundingCall(), "no transfer starts during the reload")
        XCTAssertFalse(registry.hasActivity, "a refused funding call is not counted")
        XCTAssertEqual(registry.admitResume(lockA, drainOperation: nil), .walletReloading)
        XCTAssertFalse(registry.contains(lockA, drainOperation: nil), "a refused resume claims nothing")

        registry.endRemoval()
        XCTAssertEqual(published, 2)
        XCTAssertFalse(registry.isRemovalInProgress)
        XCTAssertTrue(registry.beginFundingCall())
        registry.endFundingCall()
    }

    @MainActor
    func testAResumeClaimsALockOnlyWhileNoOtherAttemptHasIt() {
        let registry = ShieldedAssetLocksInFlight()
        XCTAssertEqual(registry.admitResume(lockA, drainOperation: nil), .admitted)
        XCTAssertTrue(registry.contains(lockA, drainOperation: nil))
        XCTAssertEqual(registry.admitResume(lockA, drainOperation: nil), .claimedElsewhere)
        XCTAssertEqual(registry.admitResume(lockB, drainOperation: nil), .admitted, "another lock is independent")

        registry.release(lockA)
        registry.release(lockB)
        XCTAssertFalse(registry.hasActivity, "the refused resume added no claim")
    }

    // MARK: - Max drain

    /// A drain reports its lock's outpoint only when its call returns, so it
    /// is claimed by operation id; a lock whose row carries that id is in
    /// flight on every reader, and no other lock is.
    @MainActor
    func testARunningDrainPutsTheLocksItBuiltInFlight() {
        let registry = ShieldedAssetLocksInFlight()
        let drain = UUID()
        let otherDrain = UUID()
        // As `performWalletDrain`: the funding call keeps removals out, the
        // drain claim marks its locks.
        XCTAssertTrue(registry.beginFundingCall())
        registry.claimDrain(drain)

        XCTAssertTrue(registry.contains(lockA, drainOperation: drain))
        XCTAssertTrue(registry.containsTransaction(txidWire: lockA.txidWire, drainOperation: drain))
        XCTAssertTrue(registry.isDrainClaimed(drain))
        XCTAssertFalse(registry.contains(lockA, drainOperation: nil), "a lock no drain built is not in flight")
        XCTAssertFalse(registry.contains(lockA, drainOperation: otherDrain), "another drain's lock is not in flight")
        XCTAssertTrue(registry.hasActivity)
        XCTAssertEqual(registry.removalAdmission, .transferActive)
        XCTAssertEqual(registry.admitResume(lockA, drainOperation: drain), .claimedElsewhere)
        XCTAssertFalse(registry.contains(lockA, drainOperation: nil), "the refused resume claimed nothing")

        registry.releaseDrain(drain)
        registry.endFundingCall()
        XCTAssertFalse(registry.contains(lockA, drainOperation: drain))
        XCTAssertFalse(registry.hasActivity)
        XCTAssertEqual(registry.admitResume(lockA, drainOperation: drain), .admitted, "after the drain ends the lock can be finished")
        registry.release(lockA)
    }

    /// Home and the tx detail rows rebuild on these emissions: once when a
    /// drain's first claim lands, once when its last one goes.
    @MainActor
    func testDrainClaimsPublishOnlyOnFirstClaimAndLastRelease() {
        let registry = ShieldedAssetLocksInFlight()
        let drain = UUID()
        var emissions = 0
        let subscription = registry.objectWillChange.sink { emissions += 1 }
        defer { subscription.cancel() }

        registry.claimDrain(drain)
        XCTAssertEqual(emissions, 1)
        registry.claimDrain(drain)
        registry.releaseDrain(drain)
        XCTAssertEqual(emissions, 1, "an inner claim and release change nothing readers see")
        registry.releaseDrain(drain)
        XCTAssertEqual(emissions, 2)
        registry.releaseDrain(drain)
        XCTAssertEqual(emissions, 2, "an extra release publishes nothing")
    }

    /// A completed drain keeps its claim after its funding call ends, while
    /// its lock row catches up; a removal must stay out until it ends.
    @MainActor
    func testADrainClaimAloneKeepsARemovalOut() {
        let registry = ShieldedAssetLocksInFlight()
        let drain = UUID()
        registry.claimDrain(drain)
        XCTAssertTrue(registry.hasActivity)
        XCTAssertEqual(registry.beginRemoval(), .transferActive)
        registry.releaseDrain(drain)
        XCTAssertEqual(registry.beginRemoval(), .admitted)
        registry.endRemoval()
    }

    @MainActor
    func testDrainClaimsAreCounted() {
        let registry = ShieldedAssetLocksInFlight()
        let drain = UUID()
        registry.claimDrain(drain)
        registry.claimDrain(drain)
        registry.releaseDrain(drain)
        XCTAssertTrue(registry.isDrainClaimed(drain), "one release leaves the other call's claim")
        registry.releaseDrain(drain)
        XCTAssertFalse(registry.isDrainClaimed(drain))
        registry.releaseDrain(drain)
        XCTAssertFalse(registry.isDrainClaimed(drain), "an extra release is a no-op")
    }

    // MARK: - A completed drain's claim

    private let drainTxidHex = String(repeating: "ab", count: 32)

    private func lockInfo(status: Int, drain: UUID?) -> ShieldedTxLookup.ShieldedLockInfo {
        .init(amountDuffs: 1_000, statusRaw: status, vout: 0, fundingTypeRaw: 5,
              walletId: Data(repeating: 1, count: 32), drainOperation: drain)
    }

    /// Runs the main queue until `condition` holds or `seconds` pass.
    @MainActor
    private func spin(seconds: TimeInterval, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// The claim stays while the row is pending, RecoveredFromChain or
    /// missing from the snapshot, and goes once a snapshot shows the row
    /// finished — consumed, or recorded as a completed drain.
    @MainActor
    func testACompletedDrainKeepsItsClaimUntilItsRowIsFinished() {
        for settled in [AssetLockStatus.consumed.rawValue, AssetLockStatus.drainCompleted.rawValue] {
            let registry = ShieldedAssetLocksInFlight()
            let lookup = ShieldedTxLookup()
            let drain = UUID()
            registry.claimDrain(drain)
            DrainClaimSettler(operation: drain, timeout: 60,
                              lookup: lookup, registry: registry).start()

            spin(seconds: 0.1) { false }
            XCTAssertTrue(registry.isDrainClaimed(drain), "a row missing from the snapshot keeps the claim")
            lookup.store([String(repeating: "cd", count: 32): lockInfo(status: settled, drain: UUID())])
            spin(seconds: 0.1) { false }
            XCTAssertTrue(registry.isDrainClaimed(drain), "another drain's finished row keeps the claim")
            lookup.store([drainTxidHex: lockInfo(status: 3, drain: drain)])
            spin(seconds: 0.1) { false }
            XCTAssertTrue(registry.isDrainClaimed(drain), "a pending row keeps the claim")
            lookup.store([drainTxidHex: lockInfo(status: AssetLockStatus.recoveredFromChain.rawValue, drain: drain)])
            spin(seconds: 0.1) { false }
            XCTAssertTrue(registry.isDrainClaimed(drain), "RecoveredFromChain is not final for a drain")

            lookup.store([drainTxidHex: lockInfo(status: settled, drain: drain)])
            spin(seconds: 2) { !registry.isDrainClaimed(drain) }
            XCTAssertFalse(registry.isDrainClaimed(drain), "status \(settled) releases the claim")
        }
    }

    @MainActor
    func testACompletedDrainsClaimIsReleasedWhenItsRowAlreadySettled() {
        let registry = ShieldedAssetLocksInFlight()
        let lookup = ShieldedTxLookup()
        let drain = UUID()
        lookup.store([drainTxidHex: lockInfo(status: AssetLockRecoveryService.consumedStatus, drain: drain)])
        registry.claimDrain(drain)
        DrainClaimSettler(operation: drain, timeout: 60,
                          lookup: lookup, registry: registry).start()
        XCTAssertFalse(registry.isDrainClaimed(drain))
    }

    @MainActor
    func testACompletedDrainsClaimEndsAtTheTimeoutWhateverTheRowSays() {
        let registry = ShieldedAssetLocksInFlight()
        let lookup = ShieldedTxLookup()
        let drain = UUID()
        lookup.store([drainTxidHex: lockInfo(status: 2, drain: drain)])
        registry.claimDrain(drain)
        DrainClaimSettler(operation: drain, timeout: 0.2,
                          lookup: lookup, registry: registry).start()
        XCTAssertTrue(registry.isDrainClaimed(drain))
        spin(seconds: 3) { !registry.isDrainClaimed(drain) }
        XCTAssertFalse(registry.isDrainClaimed(drain), "a row that never updates does not keep the claim")
    }

    @MainActor
    func testASettlerIsFreedOnceItReleases() {
        let registry = ShieldedAssetLocksInFlight()
        let lookup = ShieldedTxLookup()
        let drain = UUID()
        registry.claimDrain(drain)
        weak var weakSettler: DrainClaimSettler?
        do {
            let settler = DrainClaimSettler(operation: drain, timeout: 60, lookup: lookup, registry: registry)
            weakSettler = settler
            settler.start()
        }
        XCTAssertNotNil(weakSettler, "a holding settler keeps itself alive")
        lookup.store([drainTxidHex: lockInfo(status: AssetLockStatus.drainCompleted.rawValue, drain: drain)])
        spin(seconds: 2) { weakSettler == nil }
        XCTAssertFalse(registry.isDrainClaimed(drain))
        XCTAssertNil(weakSettler, "a released settler is freed with its subscription")
    }

    // MARK: - Coordinator

    @MainActor
    func testResumeOfAClaimedLockIsRefused() async throws {
        ShieldedAssetLocksInFlight.shared.claim(lockA)
        defer { ShieldedAssetLocksInFlight.shared.release(lockA) }
        let coordinator = ShieldedTransferCoordinator()
        let lock = lockA

        // Not awaited: an admitted resume would go on to the PIN prompt and
        // never return, so the test waits for the refusal with a deadline.
        Task { await coordinator.resumeAssetLock(outPointTxidWire: lock.txidWire, outPointVout: lock.vout) }
        let deadline = Date().addingTimeInterval(2)
        while coordinator.phase == .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case .failed = coordinator.phase else {
            return XCTFail("expected a refusal, got \(coordinator.phase)")
        }
        guard case .assetLockInFlight? = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError else {
            return XCTFail("expected assetLockInFlight, got \(String(describing: coordinator.lastFailure))")
        }
        XCTAssertTrue(ShieldedAssetLocksInFlight.shared.contains(lockA, drainOperation: nil), "the refusal must not release the running claim")
        XCTAssertEqual(coordinator.lastAssetLockOutPoint, lockA, "a refused resume keeps its lock, so Try again finishes it")
    }

    @MainActor
    func testResumeIsRefusedWhileARemovalReloadsTheWallet() async throws {
        let registry = ShieldedAssetLocksInFlight.shared
        guard registry.beginRemoval() == .admitted else {
            return XCTFail("the shared registry has activity left over")
        }
        defer { registry.endRemoval() }
        let coordinator = ShieldedTransferCoordinator()
        let lock = lockA

        // Not awaited: an admitted resume would go on to the PIN prompt and
        // never return, so the test waits for the refusal with a deadline.
        Task { await coordinator.resumeAssetLock(outPointTxidWire: lock.txidWire, outPointVout: lock.vout) }
        let deadline = Date().addingTimeInterval(2)
        while coordinator.phase == .idle, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case .walletReloading? = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError else {
            return XCTFail("expected walletReloading, got \(String(describing: coordinator.lastFailure))")
        }
        XCTAssertFalse(registry.contains(lockA, drainOperation: nil), "a refused resume claims nothing")
        XCTAssertEqual(coordinator.lastAssetLockOutPoint, lockA, "a refused resume keeps its lock, so Try again finishes it")
    }

    /// The Internal Transfer sheet counts a Core-funded transfer as a
    /// funding call before its PIN prompt; other routes build no asset lock.
    func testOnlyCoreFundedRoutesCountAsAFundingCall() {
        let counted: [InternalTransferRoute] = [.coreToShielded, .coreToPlatform]
        for route in [InternalTransferRoute.coreToShielded, .coreToPlatform, .platformToShielded,
                      .shieldedToCore, .shieldedToPlatform, .platformToCore] {
            XCTAssertEqual(InternalTransferRunner.countsAsFundingCall(.route(route)), counted.contains(route), "\(route)")
        }
    }

    /// While a removal reloads the wallet, a transfer from the Dash Wallet
    /// balance is refused before the PIN prompt, and leaves nothing counted.
    @MainActor
    func testACoreFundedTransferIsRefusedBeforeThePINWhileAWalletReloads() async throws {
        let registry = ShieldedAssetLocksInFlight.shared
        guard registry.beginRemoval() == .admitted else {
            return XCTFail("the shared registry has activity left over")
        }
        let runner = InternalTransferRunner.shared
        let request = InternalTransferRequest(
            kind: .route(.coreToShielded), amountDuffsUnsigned: 100_000, creditsAmount: 0,
            coreToPlatformLockDuffs: nil, withdrawalFeeCredits: nil, isFullPlatformWithdrawal: false,
            isFullShieldedSweep: false, platformShieldAmountWasMax: false)

        // Not awaited: a transfer let through would stop at the PIN prompt and
        // never return, so the test waits for the refusal with a deadline.
        var outcome: InternalTransferRunner.StartOutcome?
        Task { outcome = await runner.start(request) }
        let deadline = Date().addingTimeInterval(2)
        while outcome == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        registry.endRemoval()

        XCTAssertEqual(outcome, .walletReloading, "refused before the PIN prompt")
        XCTAssertEqual(runner.notice, .failed(ShieldedAssetLocksInFlight.walletReloadingMessage))
        runner.notice = nil
        XCTAssertFalse(registry.hasActivity, "a refused transfer leaves no funding call counted")
    }

    @MainActor
    func testFinishTakesOverTheBuiltLockClaimWithoutASecondOne() {
        let registry = ShieldedAssetLocksInFlight.shared
        let coordinator = ShieldedTransferCoordinator()
        let capture = NewAssetLockCapture(initialState: nil)
        registry.claimBuiltLock(lockB)
        capture.withLock { $0 = lockB }

        coordinator.finishNewAssetLock(capture)
        XCTAssertTrue(registry.contains(lockB, drainOperation: nil))
        XCTAssertNil(coordinator.lastAssetLockOutPoint, "success does not arm Try again")

        // Leaving the in-flight phases releases it, and one release frees it:
        // the coordinator took over the callback's claim without adding one.
        coordinator.reset()
        XCTAssertFalse(registry.contains(lockB, drainOperation: nil))
    }

    @MainActor
    func testFailureArmsTryAgainUnlessTheBroadcastWasRejected() {
        let registry = ShieldedAssetLocksInFlight.shared

        for (failure, armed) in [
            (PlatformWalletError.transactionBroadcastUnconfirmed("timeout") as Error, true),
            (PlatformWalletError.walletOperation("proof wait failed") as Error, true),
            (PlatformWalletError.transactionBroadcastRejected("bad-txns") as Error, false),
        ] {
            let coordinator = ShieldedTransferCoordinator()
            let capture = NewAssetLockCapture(initialState: nil)
            registry.claimBuiltLock(lockA)
            capture.withLock { $0 = lockA }

            coordinator.finishNewAssetLock(capture, armingRetryAfter: failure)

            XCTAssertEqual(ShieldedTransferCoordinator.keepsLockForRetry(after: failure), armed, "\(failure)")
            XCTAssertEqual(coordinator.lastAssetLockOutPoint, armed ? lockA : nil, "\(failure)")
            coordinator.reset()
            XCTAssertFalse(registry.contains(lockA, drainOperation: nil), "\(failure)")
        }
    }

    // MARK: - A finished resume

    /// The lock a resume consumes, keyed like `drainTxidHex` in the lookup.
    private let resumedLock = OutPoint(txidWire: Data(repeating: 0xAB, count: 32), vout: 0)

    /// A coordinator holding `resumedLock` as its in-flight lock, as a
    /// resume admitted by the registry does, and a lookup that has its row.
    @MainActor
    private func resumeHoldingTheLock(drain: UUID?) -> (ShieldedTransferCoordinator, ShieldedTxLookup) {
        let coordinator = ShieldedTransferCoordinator()
        let capture = NewAssetLockCapture(initialState: nil)
        ShieldedAssetLocksInFlight.shared.claimBuiltLock(resumedLock)
        capture.withLock { $0 = resumedLock }
        coordinator.finishNewAssetLock(capture)
        let lookup = ShieldedTxLookup()
        lookup.store([drainTxidHex: lockInfo(status: AssetLockStatus.instantSendLocked.rawValue, drain: drain)])
        return (coordinator, lookup)
    }

    /// A Max lock's resume can succeed on an unauthenticated "already
    /// consumed" report and its row ends at DrainCompleted, which never
    /// retires a consumed mark. So it is not marked, and its operation claim
    /// settles as a new Max's does.
    @MainActor
    func testASucceededResumeOfAMaxLockSettlesItsClaimWithoutAConsumedMark() {
        let registry = ShieldedAssetLocksInFlight.shared
        let drain = UUID()
        defer { while registry.isDrainClaimed(drain) { registry.releaseDrain(drain) } }
        let (coordinator, lookup) = resumeHoldingTheLock(drain: drain)
        registry.claimDrain(drain)

        coordinator.finishResumedAssetLock(.success, drainOperation: drain, lookup: lookup)

        XCTAssertEqual(coordinator.phase, .success)
        XCTAssertEqual(lookup.info(forTxidHex: drainTxidHex)?.statusRaw, AssetLockStatus.instantSendLocked.rawValue,
                       "a Max lock is never marked consumed")
        XCTAssertTrue(registry.isDrainClaimed(drain), "the claim settles until the row reads finished")
        XCTAssertFalse(registry.contains(resumedLock, drainOperation: nil), "the lock's own claim is released")

        // The settler reads the lookup the resume was given: a new pending
        // row keeps the claim, the row recorded as a completed drain ends it.
        lookup.store([drainTxidHex: lockInfo(status: AssetLockStatus.chainLocked.rawValue, drain: drain)])
        spin(seconds: 0.1) { false }
        XCTAssertTrue(registry.isDrainClaimed(drain), "a pending row keeps the claim")
        lookup.store([drainTxidHex: lockInfo(status: AssetLockStatus.drainCompleted.rawValue, drain: drain)])
        spin(seconds: 2) { !registry.isDrainClaimed(drain) }
        XCTAssertFalse(registry.isDrainClaimed(drain), "the drain's completed row releases the claim")
    }

    @MainActor
    func testASucceededResumeOfAnyOtherLockIsMarkedConsumed() {
        let (coordinator, lookup) = resumeHoldingTheLock(drain: nil)

        coordinator.finishResumedAssetLock(.success, drainOperation: nil, lookup: lookup)

        XCTAssertEqual(coordinator.phase, .success)
        XCTAssertEqual(lookup.info(forTxidHex: drainTxidHex)?.statusRaw, AssetLockRecoveryService.consumedStatus)
        XCTAssertFalse(ShieldedAssetLocksInFlight.shared.contains(resumedLock, drainOperation: nil))
    }

    /// A Max resume that ends without a verified success (an already-consumed
    /// report) releases its operation claim at once, so the lock offers
    /// Finish now again.
    @MainActor
    func testAnUnconfirmedResumeOfAMaxLockReleasesItsClaimAtOnce() {
        let registry = ShieldedAssetLocksInFlight.shared
        let drain = UUID()
        defer { while registry.isDrainClaimed(drain) { registry.releaseDrain(drain) } }
        let (coordinator, lookup) = resumeHoldingTheLock(drain: drain)
        registry.claimDrain(drain)

        coordinator.finishResumedAssetLock(.submittedUnconfirmed, drainOperation: drain, lookup: lookup)

        XCTAssertEqual(coordinator.phase, .submittedUnconfirmed)
        XCTAssertFalse(registry.isDrainClaimed(drain))
        XCTAssertEqual(lookup.info(forTxidHex: drainTxidHex)?.statusRaw, AssetLockStatus.instantSendLocked.rawValue)
    }
}

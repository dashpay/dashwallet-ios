//
//  AssetLockRecoveryPassTests.swift
//  DashWalletTests
//
//  The Core Sync recovery pass against a running transfer (#1042 /
//  PR #1212, spec AC-05, AC-09, AC-10).
//

import XCTest
@testable import dashpay

/// The Core Sync pending list and its recovery pass leave alone a funding
/// lock that a running attempt is crediting: the list leaves it out, the pass
/// skips it and counts it as still in progress, never as a failure, and a
/// pass started while a removal reloads the wallet attempts nothing.
final class AssetLockRecoveryPassTests: XCTestCase {

    private typealias Service = AssetLockRecoveryService
    private typealias CoordinatorError = ShieldedTransferCoordinator.CoordinatorError

    private let walletId = Data(repeating: 1, count: 32)

    /// A lock whose txid is `byte` repeated, so its display hex (the lookup
    /// key, the reversed txid) is the same bytes.
    private func txid(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }
    private func key(_ byte: UInt8) -> String { String(repeating: String(format: "%02x", byte), count: 32) }

    private func row(drain: UUID? = nil, wallet: Data? = nil) -> ShieldedTxLookup.ShieldedLockInfo {
        .init(amountDuffs: 1_000, statusRaw: AssetLockStatus.instantSendLocked.rawValue, vout: 0,
              fundingTypeRaw: Service.bulkFundingTypeRaw, walletId: wallet ?? walletId, drainOperation: drain)
    }

    private func pending(_ byte: UInt8, drain: UUID? = nil) -> Service.PendingRecovery {
        .init(txidWire: txid(byte), vout: 0, fundingTypeRaw: Service.bulkFundingTypeRaw,
              statusRaw: AssetLockStatus.instantSendLocked.rawValue, drainOperation: drain)
    }

    /// Waits on the main actor until `condition` holds or 2 s pass.
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Pending list

    @MainActor
    func testThePendingListLeavesOutLocksAnAttemptIsCrediting() {
        let registry = ShieldedAssetLocksInFlight()
        let lookup = ShieldedTxLookup()
        let drain = UUID()
        lookup.store([
            key(0xD1): row(),
            key(0xD2): row(),
            key(0xD3): row(drain: drain),
            key(0xD4): row(wallet: Data(repeating: 9, count: 32)),
        ])
        registry.claim(.init(txidWire: txid(0xD2), vout: 0))
        registry.claimDrain(drain)

        let listed = Service.pendingRecoveries(activeWalletId: walletId, lookup: lookup, registry: registry)

        XCTAssertEqual(listed.map(\.txidWire), [txid(0xD1)],
                       "a claimed lock and the lock of a claimed Max operation are not stuck; another wallet's is not listed")
    }

    // MARK: - The pass

    @MainActor
    func testAPassStartedDuringARemovalsReloadIsDeferredBeforeThePIN() async {
        let registry = ShieldedAssetLocksInFlight()
        XCTAssertEqual(registry.beginRemoval(), .admitted)

        // Not awaited: an admitted pass would stop at the PIN prompt and never
        // return, so the test waits for the deferral with a deadline.
        let pass = pending(0xC1)
        var result: Service.BulkOutcome?
        Task { result = await Service().recoverAll([pass], registry: registry) }
        await waitUntil { result != nil }
        guard let outcome = result else {
            registry.endRemoval()
            return XCTFail("the pass did not return: it was let through to the PIN prompt")
        }

        XCTAssertTrue(outcome.deferredForReload)
        XCTAssertEqual(outcome.attempted, 0)
        XCTAssertEqual(outcome.inProgress, 0)
        XCTAssertFalse(outcome.cancelled)
        XCTAssertNil(outcome.authFailureMessage)
        registry.endRemoval()
        XCTAssertEqual(registry.beginRemoval(), .admitted, "the deferred pass left no funding call counted")
        registry.endRemoval()
    }

    @MainActor
    func testALockClaimedSinceTheListWasReadIsSkippedAsInProgress() async {
        let registry = ShieldedAssetLocksInFlight()
        let drain = UUID()
        let claimed = pending(0xC2)
        let drained = pending(0xC3, drain: drain)
        registry.claim(.init(txidWire: claimed.txidWire, vout: 0))
        registry.claimDrain(drain)
        var reported: [Int] = []

        // Every lock is claimed, so no resume is called. Not awaited: a lock
        // let through would stop at the PIN prompt and never return.
        var result: Service.BulkOutcome?
        Task {
            result = await Service().runRecoveries([claimed, drained], into: .init(), registry: registry) { done, _ in
                reported.append(done)
            }
        }
        await waitUntil { result != nil }
        guard let outcome = result else {
            return XCTFail("the pass did not return: a claimed lock was resumed")
        }

        XCTAssertEqual(outcome.inProgress, 2)
        XCTAssertEqual(outcome.failed, 0, "a running transfer is not a failure")
        XCTAssertEqual(outcome.attempted, 0)
        XCTAssertNil(outcome.firstFailureMessage)
        XCTAssertFalse(outcome.stoppedAfterRepeatedFailures)
        XCTAssertEqual(reported, [1, 2])
    }

    // MARK: - A resume refused mid-pass

    /// A lock claimed between the pass's check and its resume is refused by
    /// the coordinator; the pass counts it as still in progress and leaves
    /// the failure run as it was, so it can never stop the pass.
    @MainActor
    func testARefusalMidPassCountsAsInProgressAndLeavesTheFailureRun() {
        XCTAssertEqual(Service.bulkStep(for: Service.RecoveryError.inProgress("busy")), .inProgress)
        XCTAssertEqual(Service.bulkStep(for: Service.RecoveryError.failed("offline")), .failed("offline"))

        var outcome = Service.BulkOutcome()
        var run = 2
        let stop = Service.apply(.inProgress, to: &outcome, consecutiveFailures: &run)

        XCTAssertFalse(stop)
        XCTAssertEqual(outcome.inProgress, 1)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(run, 2, "an in-progress lock neither extends nor resets the failure run")
    }

    @MainActor
    func testAnInFlightOrReloadRefusalIsInProgressNotAFailure() {
        for failure in [CoordinatorError.assetLockInFlight, .walletReloading] {
            let error = Service.terminalError(phase: .failed("refused"), lastFailure: failure)
            guard case .inProgress? = error as? Service.RecoveryError else {
                return XCTFail("\(failure) maps to \(String(describing: error))")
            }
        }
        guard case .cancelled? = Service.terminalError(
            phase: .failed("cancelled"), lastFailure: CoordinatorError.authCancelled) as? DWIdentityAuthorizer.AuthError else {
            return XCTFail("a PIN cancel stays a cancel")
        }
        guard case .failed? = Service.terminalError(
            phase: .failed("offline"), lastFailure: CoordinatorError.noNetwork) as? Service.RecoveryError else {
            return XCTFail("any other refusal is a failure")
        }
        XCTAssertNil(Service.terminalError(phase: .success, lastFailure: nil))
    }
}

//
//  StuckAssetLockRetryTests.swift
//  DashWalletTests
//
//  Which asset-lock statuses still deserve a retry action, and what that
//  action claims. Ticket 32104: a shield interrupted before the app was
//  reinstalled comes back as RecoveredFromChain (5), and excluding that
//  status from the retry route stranded the locked value with no way to
//  ask Platform whether the transfer had in fact landed.
//

import Foundation
import XCTest
@testable import dashwallet

final class StuckAssetLockRetryTests: XCTestCase {

    // MARK: statusAllowsRetry

    func testNonTerminalStatusesAllowRetry() {
        // 0/1 built or broadcast, 2/3 IS/CL-locked awaiting the Platform side.
        for statusRaw in 0...3 {
            XCTAssertTrue(
                TxDetailModel.statusAllowsRetry(statusRaw),
                "status \(statusRaw) is not finished and must keep a retry action")
        }
    }

    func testRecoveredFromChainAllowsRetry() {
        XCTAssertEqual(TxDetailModel.recoveredFromChainStatus, 5)
        // "Completion unknown" is not "completed": the lock keeps its outpoint
        // and its chain proof, which is all `resume_asset_lock` needs, and
        // Platform answers an already-spent outpoint with a typed error.
        XCTAssertTrue(TxDetailModel.statusAllowsRetry(TxDetailModel.recoveredFromChainStatus))
    }

    func testConsumedStatusNeverAllowsRetry() {
        // 4 is the one terminal success — nothing left to resume.
        XCTAssertFalse(TxDetailModel.statusAllowsRetry(4))
    }

    func testUnknownStatusDoesNotAllowRetry() {
        XCTAssertFalse(TxDetailModel.statusAllowsRetry(6))
        XCTAssertFalse(TxDetailModel.statusAllowsRetry(-1))
        XCTAssertFalse(TxDetailModel.statusAllowsRetry(Int.max))
    }

    // MARK: what the action says and offers

    private func retry(statusRaw: Int) -> TxDetailModel.StuckAssetLockRetry {
        // Funding type 5 = Core → Shielded, the route ticket 32104 is about.
        TxDetailModel.StuckAssetLockRetry(fundingTypeRaw: 5, statusRaw: statusRaw, vout: 0)
    }

    func testUnlockedTransactionOffersRebroadcast() {
        XCTAssertEqual(retry(statusRaw: 0).actionTitle, "Rebroadcast")
        XCTAssertEqual(retry(statusRaw: 1).actionTitle, "Rebroadcast")
    }

    func testLockedAndRestoredTransactionsOfferCompleteTransfer() {
        // Nothing to re-broadcast in either case — the transaction is final on
        // Core, only the Platform side is open (or unknown).
        XCTAssertEqual(retry(statusRaw: 2).actionTitle, "Complete Transfer")
        XCTAssertEqual(retry(statusRaw: 3).actionTitle, "Complete Transfer")
        XCTAssertEqual(retry(statusRaw: 5).actionTitle, "Complete Transfer")
    }

    func testRemovalIsOfferedOnlyBeforeTheNetworkAcceptedAnything() {
        XCTAssertTrue(retry(statusRaw: 0).supportsRemoval)
        XCTAssertTrue(retry(statusRaw: 1).supportsRemoval)
        XCTAssertFalse(retry(statusRaw: 2).supportsRemoval)
        XCTAssertFalse(retry(statusRaw: 3).supportsRemoval)
        // A restored lock only ever enters that status alongside a chain
        // proof, so deleting it locally could only corrupt state.
        XCTAssertFalse(retry(statusRaw: 5).supportsRemoval)
    }

    // MARK: routes

    func testShieldedAndPlatformFundingRoutesAreRetryable() {
        XCTAssertTrue(AssetLockRecoveryService.supportsRetry(fundingTypeRaw: 5))
        XCTAssertTrue(AssetLockRecoveryService.supportsRetry(fundingTypeRaw: 4))
        XCTAssertTrue(AssetLockRecoveryService.supportsRetry(fundingTypeRaw: 1))
        XCTAssertTrue(AssetLockRecoveryService.supportsRetry(fundingTypeRaw: 2))
    }

    func testRegistrationAndInvitationRoutesStayOutOfThisSurface() {
        // Those recover through the Join DashPay flow, which owns key
        // preparation and its own phase UI.
        XCTAssertFalse(AssetLockRecoveryService.supportsRetry(fundingTypeRaw: 0))
        XCTAssertFalse(AssetLockRecoveryService.supportsRetry(fundingTypeRaw: 3))
    }

    // MARK: what the bulk pass admits

    // The per-row action is deliberately wider than the bulk pass. These pin
    // the difference, which is the whole of the reviewer's "restored top-ups
    // can stop the pass before a shielded lock is reached" concern.

    func testBulkPassRunsOnlyTheShieldedFundingRoute() {
        XCTAssertEqual(AssetLockRecoveryService.bulkFundingTypeRaw, 5)
        // 1/2 (identity top-up) and 4 (Core → Platform funding) keep their
        // per-row retry, but neither route classifies an already-consumed lock,
        // so in a batch they would fail forever and never earn a probe.
        for fundingTypeRaw in [1, 2, 4] {
            XCTAssertTrue(
                AssetLockRecoveryService.supportsRetry(fundingTypeRaw: fundingTypeRaw),
                "type \(fundingTypeRaw) must keep its per-row action")
            XCTAssertNotEqual(AssetLockRecoveryService.bulkFundingTypeRaw, fundingTypeRaw)
        }
    }

    func testBulkPassSkipsStatusesThatWouldBlockOnTheNetwork() {
        // 0/1 re-broadcast and then wait for IS/CL. One transaction evicted
        // from every mempool would hold the batch with nothing to skip it.
        XCTAssertFalse(AssetLockRecoveryService.bulkStatusAllowsRecovery(0))
        XCTAssertFalse(AssetLockRecoveryService.bulkStatusAllowsRecovery(1))
        // Chain-final on Core, Platform side still open — the resumable set.
        XCTAssertTrue(AssetLockRecoveryService.bulkStatusAllowsRecovery(2))
        XCTAssertTrue(AssetLockRecoveryService.bulkStatusAllowsRecovery(3))
        XCTAssertTrue(AssetLockRecoveryService.bulkStatusAllowsRecovery(5))
        // 4 is consumed; 6 is not a status this build knows.
        XCTAssertFalse(AssetLockRecoveryService.bulkStatusAllowsRecovery(4))
        XCTAssertFalse(AssetLockRecoveryService.bulkStatusAllowsRecovery(6))
    }

    func testEveryBulkStatusIsAlsoRetryablePerRow() {
        // The bulk set must stay a subset: a lock the batch would act on but
        // the row would not offer is a contradiction between the two surfaces.
        for statusRaw in 0...6 where AssetLockRecoveryService.bulkStatusAllowsRecovery(statusRaw) {
            XCTAssertTrue(AssetLockRecoveryService.statusAllowsRetry(statusRaw),
                          "status \(statusRaw) is in the bulk set but not the per-row set")
        }
    }

    // MARK: bulk tally and the stop rule

    private func fold(_ steps: [AssetLockRecoveryService.BulkStep])
        -> (outcome: AssetLockRecoveryService.BulkOutcome, stoppedAt: Int?) {
        var outcome = AssetLockRecoveryService.BulkOutcome()
        var consecutive = 0
        for (index, step) in steps.enumerated() {
            if AssetLockRecoveryService.apply(step, to: &outcome, consecutiveFailures: &consecutive) {
                return (outcome, index)
            }
        }
        return (outcome, nil)
    }

    func testCompletionsAndAlreadySpentAreCountedApart() {
        let (outcome, stoppedAt) = fold([.completed, .alreadySpent, .completed])
        XCTAssertNil(stoppedAt)
        XCTAssertEqual(outcome.completed, 2)
        XCTAssertEqual(outcome.alreadySpent, 1)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertEqual(outcome.attempted, 3)
        XCTAssertNil(outcome.firstFailureMessage)
    }

    func testThreeConsecutiveFailuresStopThePass() {
        let (outcome, stoppedAt) = fold([.failed("a"), .failed("b"), .failed("c"), .completed])
        XCTAssertEqual(stoppedAt, 2, "the pass must stop ON the third failure, not after a fourth item")
        XCTAssertTrue(outcome.stoppedAfterRepeatedFailures)
        XCTAssertEqual(outcome.failed, 3)
        XCTAssertEqual(outcome.completed, 0, "the item after the stop must never run")
    }

    func testASuccessResetsTheFailureRun() {
        // Two failures, a success, two more failures: five items, no stop.
        // Without the reset this would stop at the fourth.
        let (outcome, stoppedAt) = fold([.failed("a"), .failed("b"), .completed, .failed("c"), .failed("d")])
        XCTAssertNil(stoppedAt)
        XCTAssertFalse(outcome.stoppedAfterRepeatedFailures)
        XCTAssertEqual(outcome.failed, 4)
    }

    func testAlreadySpentAlsoResetsTheFailureRun() {
        // An already-spent answer is not a failure: the pass asked and was
        // told there is nothing to do. Treating it as one would let a wallet
        // full of finished locks trip the stop rule.
        let (outcome, stoppedAt) = fold([.failed("a"), .failed("b"), .alreadySpent, .failed("c"), .failed("d")])
        XCTAssertNil(stoppedAt)
        XCTAssertEqual(outcome.alreadySpent, 1)
        XCTAssertEqual(outcome.failed, 4)
    }

    func testFirstFailureMessageIsKeptNotOverwritten() {
        let (outcome, _) = fold([.failed("network unreachable"), .failed("something else")])
        XCTAssertEqual(outcome.firstFailureMessage, "network unreachable")
    }

    func testCancelStopsImmediatelyAndIsNotCountedAsAFailure() {
        let (outcome, stoppedAt) = fold([.completed, .cancelled, .completed])
        XCTAssertEqual(stoppedAt, 1)
        XCTAssertTrue(outcome.cancelled)
        XCTAssertEqual(outcome.failed, 0)
        XCTAssertFalse(outcome.stoppedAfterRepeatedFailures)
        XCTAssertEqual(outcome.completed, 1)
    }

    // MARK: display hex to wire order

    // A slip here makes every bulk resume fail with "not tracked by this
    // wallet" and the pass reports a network problem it never had.

    func testDisplayHexIsReversedIntoWireOrder() {
        let displayHex = "00112233445566778899aabbccddeeff" + "00112233445566778899aabbccddeeff"
        let wire = AssetLockRecoveryService.txidWire(fromDisplayHex: displayHex)
        XCTAssertEqual(wire?.count, 32)
        // Display order is the reverse of wire order, so the last display byte
        // is the first wire byte.
        XCTAssertEqual(wire?.first, 0xff)
        XCTAssertEqual(wire?.last, 0x00)
        XCTAssertEqual(wire.map { Data($0.reversed()) }, Data(displayHexBytes: displayHex))
    }

    func testMalformedDisplayHexIsRejectedRatherThanTruncated() {
        // Short, long, and non-hex all have to fail closed: a partial txid
        // would resume some other outpoint.
        XCTAssertNil(AssetLockRecoveryService.txidWire(fromDisplayHex: ""))
        XCTAssertNil(AssetLockRecoveryService.txidWire(fromDisplayHex: String(repeating: "a", count: 63)))
        XCTAssertNil(AssetLockRecoveryService.txidWire(fromDisplayHex: String(repeating: "a", count: 65)))
        XCTAssertNil(AssetLockRecoveryService.txidWire(fromDisplayHex: String(repeating: "z", count: 64)))
    }
}

private extension Data {
    /// Straight hex decode, no reversal — the reference the conversion under
    /// test is compared against.
    init?(displayHexBytes hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self = bytes
    }

}

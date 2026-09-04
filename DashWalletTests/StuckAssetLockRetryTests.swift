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
}

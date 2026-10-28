//
//  CoreShieldedDrainRecipientTests.swift
//  DashWalletTests
//
//  A Core → Shielded Max drain's recipient lives only in the app's durable
//  marker: the SDK pays whatever address a resume passes. These cover the
//  decisions that keep an external-recipient drain from ever being resumed to
//  the wallet's own address, the verdict every drain surface switches on, and
//  the Send screen's estimate wiring.
//

import Foundation
import SwiftDashSDK
import XCTest
@testable import dashpay

final class CoreShieldedDrainRecipientTests: XCTestCase {

    private typealias Target = CoreShieldedDrainResumeTarget

    private let context = CoreShieldedDrainContext(walletId: Data(repeating: 7, count: 32), networkScope: "testnet")
    private let raw43 = Data((0..<43).map { UInt8($0) })

    // MARK: - Resume target: whichever surface resumes a lock

    func testLockNoDrainBuiltResumesToOwnAddressWhateverTheMarker() {
        let marker = CoreShieldedDrainOperation(id: UUID(), context: context, recipient: .external(raw43: raw43))
        XCTAssertEqual(Target.resolve(row: .none, marker: .loaded(marker)), .ownWallet)
        XCTAssertEqual(Target.resolve(row: .none, marker: .loaded(nil)), .ownWallet)
        XCTAssertEqual(Target.resolve(row: .none, marker: .unavailable), .ownWallet)
        XCTAssertEqual(Target.resolve(row: .none, marker: .corrupt), .ownWallet)
    }

    func testDrainLockResumesToItsMarkersRecipient() {
        let id = UUID()
        let own = CoreShieldedDrainOperation(id: id, context: context)
        let external = CoreShieldedDrainOperation(id: id, context: context, recipient: .external(raw43: raw43))
        XCTAssertEqual(Target.resolve(row: .operation(id), marker: .loaded(own)), .ownWallet)
        XCTAssertEqual(Target.resolve(row: .operation(id), marker: .loaded(external)), .external(raw43))
    }

    func testDrainLockWithoutItsMarkerIsRefusedNotDefaultedToOwn() {
        let id = UUID()
        let other = CoreShieldedDrainOperation(id: UUID(), context: context, recipient: .external(raw43: raw43))
        XCTAssertEqual(Target.resolve(row: .operation(id), marker: .loaded(nil)), .refuse)
        XCTAssertEqual(Target.resolve(row: .operation(id), marker: .loaded(other)), .refuse)
        XCTAssertEqual(Target.resolve(row: .operation(id), marker: .corrupt), .refuse)
    }

    func testUnreadableMarkerAsksForARetryInsteadOfRefusing() {
        XCTAssertEqual(Target.resolve(row: .operation(UUID()), marker: .unavailable), .retryLater)
    }

    func testMalformedDrainRowIsRefusedEvenWithAMarker() {
        let marker = CoreShieldedDrainOperation(id: UUID(), context: context)
        XCTAssertEqual(Target.resolve(row: .malformed, marker: .loaded(marker)), .refuse)
        XCTAssertEqual(Target.resolve(row: .malformed, marker: .unavailable), .refuse)
    }

    func testRowIdentityFromStoredOperationIdBytes() {
        let id = UUID()
        let bytes = withUnsafeBytes(of: id.uuid) { Data($0) }
        XCTAssertEqual(CoreShieldedDrainRowIdentity(operationIdBytes: bytes), .operation(id))
        XCTAssertEqual(CoreShieldedDrainRowIdentity(operationIdBytes: nil), .none)
        XCTAssertEqual(CoreShieldedDrainRowIdentity(operationIdBytes: Data()), .none)
        XCTAssertEqual(CoreShieldedDrainRowIdentity(operationIdBytes: bytes.dropLast()), .malformed)
    }

    func testOperationIdBytesMapToTheMarkerUUID() {
        let id = UUID()
        let bytes = withUnsafeBytes(of: id.uuid) { Data($0) }
        XCTAssertEqual(UUID(drainOperationIdBytes: bytes), id)
        XCTAssertNil(UUID(drainOperationIdBytes: bytes.dropLast()))
        XCTAssertNil(UUID(drainOperationIdBytes: Data()))
    }

    // MARK: - Who a new drain pays

    func testDrainPaysTheMarkersRecipient() {
        let own = Data(repeating: 0xEE, count: 43)
        XCTAssertEqual(ShieldedTransferCoordinator.drainRecipientRaw43(.external(raw43: raw43), ownAddress: own), raw43)
        XCTAssertEqual(ShieldedTransferCoordinator.drainRecipientRaw43(.ownWallet, ownAddress: own), own)
    }

    func testExternalDrainFailsClosedWhenTheBalanceGrewAfterReview() {
        let confirmed = CoreShieldedDrainConfirmation(
            context: context, candidateBalanceDuffs: 1_000_000, estimatedRecipientCredits: 990_000_000,
            estimatedL1FeeDuffs: 500, poolFeeCredits: 9_000_000)
        func preview(_ balance: UInt64, _ status: WalletDrainPreview.Status = .ready) -> WalletDrainPreview {
            WalletDrainPreview(candidateInputCount: 2, candidateBalanceDuffs: balance, poolFeeCredits: 9_000_000,
                               estimatedL1FeeDuffs: 500, estimatedRecipientCredits: nil, status: status)
        }
        XCTAssertTrue(ShieldedTransferCoordinator.drainStillMatches(preview(1_000_000), confirmed))
        XCTAssertTrue(ShieldedTransferCoordinator.drainStillMatches(preview(900_000), confirmed))
        XCTAssertFalse(ShieldedTransferCoordinator.drainStillMatches(preview(1_000_001), confirmed))
        XCTAssertFalse(ShieldedTransferCoordinator.drainStillMatches(preview(0, .insufficientFunds), confirmed))
    }

    // MARK: - Recipient payload

    func testExternalRecipientExposesItsPayloadAndOwnDoesNot() {
        XCTAssertEqual(CoreShieldedDrainRecipient.external(raw43: raw43).externalRaw43, raw43)
        XCTAssertTrue(CoreShieldedDrainRecipient.external(raw43: raw43).isExternal)
        XCTAssertNil(CoreShieldedDrainRecipient.ownWallet.externalRaw43)
        XCTAssertFalse(CoreShieldedDrainRecipient.ownWallet.isExternal)
    }

    // MARK: - Verdict

    func testDrainVerdictFollowsTheSDKOutcome() {
        let outpoint = WalletDrainOutpoint(txidWire: Data(repeating: 1, count: 32), vout: 0)
        XCTAssertEqual(WalletDrainOutcome(state: .notSent, outpoint: nil).drainVerdict, .notSent)
        XCTAssertEqual(WalletDrainOutcome(state: .pending, outpoint: nil).drainVerdict, .pending(hasOutpoint: false))
        XCTAssertEqual(WalletDrainOutcome(state: .pending, outpoint: outpoint).drainVerdict, .pending(hasOutpoint: true))
        XCTAssertEqual(WalletDrainOutcome(state: .completed, outpoint: outpoint).drainVerdict, .completed)
    }

    // MARK: - Confirmation figures

    @MainActor
    func testFeeBreakdownNamesBothFeesAndFailsClosedOnOverflow() {
        let known = CoreShieldedDrainConfirmation(
            context: context, candidateBalanceDuffs: 5_000_000, estimatedRecipientCredits: 4_990_000_000,
            estimatedL1FeeDuffs: 1_000, poolFeeCredits: 9_000_000)
        XCTAssertEqual(known.totalFeeCredits, 1_000 * 1_000 + 9_000_000)
        XCTAssertTrue(known.feeBreakdownText.contains("\n"))
        XCTAssertFalse(known.feeBreakdownText.contains("—"))

        let unknownL1 = CoreShieldedDrainConfirmation(
            context: context, candidateBalanceDuffs: 5_000_000, estimatedRecipientCredits: nil,
            estimatedL1FeeDuffs: nil, poolFeeCredits: 9_000_000)
        XCTAssertNil(unknownL1.totalFeeCredits)
        XCTAssertTrue(unknownL1.feeBreakdownText.contains("—"))

        let overflowing = CoreShieldedDrainConfirmation(
            context: context, candidateBalanceDuffs: 1, estimatedRecipientCredits: nil,
            estimatedL1FeeDuffs: UInt64.max / 2, poolFeeCredits: 0)
        XCTAssertNil(overflowing.totalFeeCredits)
    }

    // MARK: - Send screen estimate wiring

    private func preview(_ status: WalletDrainPreview.Status, credits: UInt64?) -> WalletDrainPreview {
        WalletDrainPreview(
            candidateInputCount: 3, candidateBalanceDuffs: 1_000_000, poolFeeCredits: 9_000_000,
            estimatedL1FeeDuffs: 500, estimatedRecipientCredits: credits, status: status)
    }

    func testReadyPreviewFillsTheWholeDuffEstimate() {
        let estimate = CoreShieldedDrainMaxController.estimate(
            from: preview(.ready, credits: 990_500_999), insufficientFundsMessage: { "none" })
        XCTAssertTrue(estimate.isConfirmable)
        XCTAssertEqual(estimate.amountDuffs, 990_500)
        XCTAssertNotEqual(estimate.notice, "none")
    }

    func testInsufficientFundsCarriesNothingToConfirm() {
        let estimate = CoreShieldedDrainMaxController.estimate(
            from: preview(.insufficientFunds, credits: nil), insufficientFundsMessage: { "none" })
        XCTAssertFalse(estimate.isConfirmable)
        XCTAssertNil(estimate.amountDuffs)
        XCTAssertEqual(estimate.notice, "none")
    }

    func testInputLimitPreviewConfirmsOnlyWithAnAmount() {
        // The preview is carried so Continue can read its (absent) figures and
        // stay disabled; a sub-duff or missing estimate clears the field.
        let withoutAmount = CoreShieldedDrainMaxController.estimate(
            from: preview(.inputLimitMayBeExceeded, credits: nil), insufficientFundsMessage: { "none" })
        XCTAssertTrue(withoutAmount.isConfirmable)
        XCTAssertNil(withoutAmount.amountDuffs)
        let subDuff = CoreShieldedDrainMaxController.estimate(
            from: preview(.ready, credits: 999), insufficientFundsMessage: { "none" })
        XCTAssertNil(subDuff.amountDuffs)
    }

    @MainActor
    func testAmountDisplayMarksEstimatesAndIntent() {
        XCTAssertEqual(CoreShieldedDrainDisplay.dashAmount(estimatedRecipientCredits: nil), "Max")
        XCTAssertEqual(CoreShieldedDrainDisplay.dashAmount(estimatedRecipientCredits: 999), "<0.00000001")
        XCTAssertTrue(CoreShieldedDrainDisplay.dashAmount(estimatedRecipientCredits: 1_000_000).hasPrefix("≈ "))
        XCTAssertEqual(
            CoreShieldedDrainDisplay.fiatAmount(estimatedRecipientCredits: nil, dashAmount: 1, currency: "USD"), "—")
    }
}

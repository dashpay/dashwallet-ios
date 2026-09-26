//
//  InvitationValidationPolicyTests.swift
//  DashWalletTests
//

import SwiftDashSDK
import XCTest
@testable import dashpay

final class InvitationValidationPolicyTests: XCTestCase {

    private let inviter = InvitationInviter(username: "alice", displayName: "Alice", avatarURL: nil)
    private let minimum: UInt64 = 300_000
    private let contested: UInt64 = 25_000_000

    private func status(
        amount: UInt64, claimed: Bool = false, isInstant: Bool = true, isChainLocked: Bool = true
    ) -> ManagedPlatformWallet.InvitationClaimStatus {
        ManagedPlatformWallet.InvitationClaimStatus(
            prospectiveIdentityId: Data(repeating: 1, count: 32),
            amountDuffs: amount,
            isInstant: isInstant,
            isChainLocked: isChainLocked,
            alreadyClaimed: claimed)
    }

    private func verdict(_ status: ManagedPlatformWallet.InvitationClaimStatus) -> InvitationValidation {
        InvitationValidationPolicy.verdict(
            status: status, inviter: inviter, minimumDuffs: minimum, contestedDuffs: contested)
    }

    // MARK: - Tier from the funded amount

    func testContestedAmountFundsAnyName() {
        XCTAssertEqual(verdict(status(amount: 25_000_000)).tier, .contested)
        XCTAssertEqual(verdict(status(amount: 26_000_000)).tier, .contested)
    }

    func testBelowContestedAmountFundsNonContestedOnly() {
        XCTAssertEqual(verdict(status(amount: 3_000_000)).tier, .nonContested)
        XCTAssertEqual(verdict(status(amount: 24_999_999)).tier, .nonContested)
    }

    func testBelowMinimumIsInvalid() {
        XCTAssertEqual(verdict(status(amount: 299_999)), .invalid(.belowMinimum, inviter: inviter))
        XCTAssertEqual(verdict(status(amount: 300_000)).tier, .nonContested)
    }

    func testClaimedWinsOverAmount() {
        XCTAssertEqual(verdict(status(amount: 25_000_000, claimed: true)), .alreadyClaimed(inviter: inviter))
    }

    /// A ChainLock-only link before its ChainLock cannot be claimed yet —
    /// kept and re-checked, not offered for Create and not forgotten.
    func testChainLockOnlyInvitationWaitsForItsChainLock() {
        let waiting = verdict(status(amount: 3_000_000, isInstant: false, isChainLocked: false))
        XCTAssertEqual(waiting, .awaitingChainLock)
        XCTAssertFalse(waiting.isDefinitive)
        XCTAssertNil(waiting.tier)
        XCTAssertEqual(verdict(status(amount: 3_000_000, isInstant: false, isChainLocked: true)).tier, .nonContested)
    }

    // MARK: - Errors: definitive vs undetermined

    func testMalformedAndWrongNetworkAreDefinitive() {
        let malformed = InvitationValidationPolicy.verdict(
            error: PlatformWalletError.invalidParameter("bad"), inviter: inviter)
        let wrongNetwork = InvitationValidationPolicy.verdict(
            error: PlatformWalletError.invalidNetwork("testnet"), inviter: inviter)
        XCTAssertEqual(malformed, .invalid(.malformed, inviter: inviter))
        XCTAssertEqual(wrongNetwork, .invalid(.wrongNetwork, inviter: inviter))
        XCTAssertTrue(malformed.isDefinitive)
        XCTAssertTrue(wrongNetwork.isDefinitive)
    }

    /// A flaky connection must not cost the user the invitation (Android
    /// deletes it on any exception; iOS keeps it and retries).
    func testTransientErrorKeepsTheInvitation() {
        let verdict = InvitationValidationPolicy.verdict(
            error: PlatformWalletError.walletOperation("funding transaction not found"), inviter: inviter)
        XCTAssertEqual(verdict, .undetermined)
        XCTAssertFalse(verdict.isDefinitive)
    }

    // MARK: - Local checks come first

    func testLocalChecksOrder() {
        XCTAssertEqual(
            InvitationValidationPolicy.localVerdict(hasRegisteredUsername: true, hasPendingUsernameRequest: true, preview: nil),
            .alreadyHasIdentity)
        XCTAssertEqual(
            InvitationValidationPolicy.localVerdict(hasRegisteredUsername: false, hasPendingUsernameRequest: true, preview: nil),
            .alreadyRequestedUsername)
        XCTAssertEqual(
            InvitationValidationPolicy.localVerdict(hasRegisteredUsername: false, hasPendingUsernameRequest: false, preview: nil),
            .invalid(.malformed, inviter: .unknown))
    }

    // MARK: - An identity without a username

    /// A claim that landed but reported failure leaves this wallet with the
    /// invitation's own identity and no name. That is a registration to
    /// finish, not "already claimed" and not "already has a username".
    func testOwnUnnamedIdentityResumesInsteadOfRefusing() {
        let status = status(amount: 3_000_000, claimed: true)
        let verdict = InvitationValidationPolicy.verdict(
            status: status, inviter: inviter, minimumDuffs: minimum, contestedDuffs: contested,
            localIdentityId: status.prospectiveIdentityId)
        XCTAssertEqual(verdict.tier, .nonContested)
    }

    func testSomeOtherIdentityStillRefuses() {
        let verdict = InvitationValidationPolicy.verdict(
            status: status(amount: 3_000_000), inviter: inviter, minimumDuffs: minimum, contestedDuffs: contested,
            localIdentityId: Data(repeating: 9, count: 32))
        XCTAssertEqual(verdict, .alreadyHasIdentity)
    }

    // MARK: - Claim failures arrive wrapped by the coordinator

    private func wrapped(_ error: Error) -> Error {
        DWIdentityRegistrationCoordinator.CoordinatorError.identityRegistration(error)
    }

    func testWrappedDefinitiveClaimFailuresAreRecognized() {
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.invalidNetwork("testnet"))), .invalid)
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.invalidParameter("bad link"))), .invalid)
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.assetLockAlreadyConsumed("outpoint"))), .alreadyUsed)
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.walletOperation(
                "IdentityAssetLockTransactionOutPointAlreadyConsumedError: asset lock outpoint already consumed"))),
            .alreadyUsed)
    }

    func testStillConfirmingKeepsTheInvitation() {
        let failure = InvitationClaimFailure.classify(wrapped(PlatformWalletError.walletOperation(
            "invitation islock proof was rejected … the funding transaction is not yet chain-locked")))
        XCTAssertEqual(failure, .stillConfirming)
        XCTAssertEqual(failure?.endsInvitation, false)
    }

    func testUnrelatedFailureIsNotAnInvitationVerdict() {
        XCTAssertNil(InvitationClaimFailure.classify(wrapped(PlatformWalletError.walletOperation("Timeout expired"))))
        XCTAssertNil(InvitationClaimFailure.classify(DWIdentityRegistrationCoordinator.CoordinatorError.authCancelled))
    }

    // MARK: - Which copies a verdict removes

    /// Facts about the voucher hold in every wallet; facts about the checked
    /// wallet must not delete another wallet's copy.
    func testOnlyVoucherFactsClearEveryCopy() {
        XCTAssertTrue(InvitationValidation.alreadyClaimed(inviter: inviter).clearsEverywhere)
        XCTAssertTrue(InvitationValidation.invalid(.malformed, inviter: inviter).clearsEverywhere)
        XCTAssertTrue(InvitationValidation.invalid(.belowMinimum, inviter: inviter).clearsEverywhere)

        XCTAssertFalse(InvitationValidation.invalid(.wrongNetwork, inviter: inviter).clearsEverywhere)
        XCTAssertFalse(InvitationValidation.alreadyHasIdentity.clearsEverywhere)
        XCTAssertFalse(InvitationValidation.alreadyRequestedUsername.clearsEverywhere)

        XCTAssertTrue(InvitationClaimFailure.alreadyUsed.clearsEverywhere)
        XCTAssertFalse(InvitationClaimFailure.invalid.clearsEverywhere, "may be this wallet's network only")
        XCTAssertFalse(InvitationClaimFailure.stillConfirming.clearsEverywhere)
    }

    // MARK: - Inviter name

    func testInviterBestNamePrefersDisplayName() {
        XCTAssertEqual(inviter.bestName, "Alice")
        XCTAssertEqual(InvitationInviter(username: "bob", displayName: "  ", avatarURL: nil).bestName, "bob")
        XCTAssertNil(InvitationInviter.unknown.bestName)
        XCTAssertEqual(InvitationOutcomeDialogs.senderName(.unknown), "DashPay")
    }
}

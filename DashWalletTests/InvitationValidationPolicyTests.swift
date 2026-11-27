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

    private func status(
        amount: UInt64, claimed: Bool = false, isInstant: Bool = true, isChainLocked: Bool = true,
        ours: Bool? = nil
    ) -> ManagedPlatformWallet.InvitationClaimStatus {
        ManagedPlatformWallet.InvitationClaimStatus(
            prospectiveIdentityId: Data(repeating: 1, count: 32),
            amountDuffs: amount,
            isInstant: isInstant,
            isChainLocked: isChainLocked,
            alreadyClaimed: claimed,
            claimedByThisWallet: claimed ? ours : false)
    }

    private func verdict(_ status: ManagedPlatformWallet.InvitationClaimStatus) -> InvitationValidation {
        InvitationValidationPolicy.verdict(
            status: status, inviter: inviter, minimumDuffs: minimum)
    }

    // MARK: - Tier from the funded amount

    func testValidVerdictCarriesTheFundedAmount() {
        XCTAssertEqual(verdict(status(amount: 25_000_000)), .valid(amountDuffs: 25_000_000, inviter: inviter))
        XCTAssertEqual(verdict(status(amount: 3_000_000)).amountDuffs, 3_000_000)
    }

    func testContestedAmountFundsAnyName() {
        let legacy = ContestedUsernameFee.Amounts.legacy.fundingDuffs
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 25_000_000, contestedDuffs: legacy), .contested)
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 26_000_000, contestedDuffs: legacy), .contested)
    }

    func testBelowContestedAmountFundsNonContestedOnly() {
        let legacy = ContestedUsernameFee.Amounts.legacy.fundingDuffs
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 3_000_000, contestedDuffs: legacy), .nonContested)
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 24_999_999, contestedDuffs: legacy), .nonContested)
    }

    /// The contested cost follows the protocol version: on 14 a 0.15 DASH
    /// voucher pays for a contested name, on 13 it does not.
    func testTierFollowsTheProtocolsContestedCost() {
        let reduced = ContestedUsernameFee.Amounts.reduced.fundingDuffs
        let legacy = ContestedUsernameFee.Amounts.legacy.fundingDuffs
        XCTAssertEqual(reduced, 15_000_000)
        XCTAssertEqual(legacy, 25_000_000)
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 15_000_000, contestedDuffs: reduced), .contested)
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 14_999_999, contestedDuffs: reduced), .nonContested)
        XCTAssertEqual(InvitationValidationPolicy.tier(amountDuffs: 15_000_000, contestedDuffs: legacy), .nonContested)
    }

    func testBelowMinimumIsInvalid() {
        XCTAssertEqual(verdict(status(amount: 299_999)), .invalid(.belowMinimum, inviter: inviter))
        XCTAssertEqual(verdict(status(amount: 300_000)).amountDuffs, 300_000)
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
        XCTAssertNil(waiting.amountDuffs)
        XCTAssertEqual(verdict(status(amount: 3_000_000, isInstant: false, isChainLocked: true)).amountDuffs, 3_000_000)
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
        let status = status(amount: 3_000_000, claimed: true, ours: true)
        let verdict = InvitationValidationPolicy.verdict(
            status: status, inviter: inviter, minimumDuffs: minimum,
            claim: .resumeOwnClaim(status.prospectiveIdentityId))
        XCTAssertEqual(verdict.amountDuffs, 3_000_000)
    }

    func testSomeOtherIdentityStillRefuses() {
        let verdict = InvitationValidationPolicy.verdict(
            status: status(amount: 3_000_000), inviter: inviter, minimumDuffs: minimum,
            claim: .otherIdentity)
        XCTAssertEqual(verdict, .alreadyHasOtherIdentity)
        XCTAssertTrue(verdict.isDefinitive)
        XCTAssertFalse(verdict.clearsEverywhere)
    }

    func testUnknownLocalAnswerIsUndetermined() {
        let verdict = InvitationValidationPolicy.verdict(
            status: status(amount: 3_000_000), inviter: inviter, minimumDuffs: minimum, claim: .undetermined)
        XCTAssertEqual(verdict, .undetermined)
    }

    // MARK: - A paid registration with no identity

    /// The paid registration is finished first, and only offered where the
    /// ordinary recovery would finish it.
    func testPaidRegistrationKeepsTheInvitationWhileItIsFinished() {
        let pending = InvitationValidationPolicy.verdict(
            status: status(amount: 3_000_000), inviter: inviter, minimumDuffs: minimum,
            claim: .registrationPending, paidRegistrationRecovers: true)
        XCTAssertEqual(pending, .pendingPaidRegistration)
        XCTAssertFalse(pending.isDefinitive)
        XCTAssertFalse(pending.clearsEverywhere)
        XCTAssertNil(pending.amountDuffs, "Create stays off")
        XCTAssertEqual(
            InvitationValidationPolicy.verdict(
                status: status(amount: 3_000_000), inviter: inviter, minimumDuffs: minimum,
                claim: .registrationPending, paidRegistrationRecovers: false),
            .undetermined)
    }

    /// A spent voucher is reported as spent even while a paid registration
    /// waits: Finish registration is only for a claimable invitation.
    func testAPendingRegistrationDoesNotHideASpentVoucher() {
        for recovers in [true, false] {
            XCTAssertEqual(
                InvitationValidationPolicy.verdict(
                    status: status(amount: 3_000_000, claimed: true, ours: true), inviter: inviter,
                    minimumDuffs: minimum, claim: .registrationPending, paidRegistrationRecovers: recovers),
                .ownClaimNotLoaded)
            XCTAssertEqual(
                InvitationValidationPolicy.verdict(
                    status: status(amount: 3_000_000, claimed: true), inviter: inviter,
                    minimumDuffs: minimum, claim: .registrationPending, paidRegistrationRecovers: recovers),
                .alreadyClaimed(inviter: inviter))
        }
    }

    /// Finish registration only for a voucher that could be claimed now: one
    /// below the minimum or not yet locked says so first.
    func testAPendingRegistrationDoesNotHideAnUnusableVoucher() {
        for recovers in [true, false] {
            XCTAssertEqual(
                InvitationValidationPolicy.verdict(
                    status: status(amount: minimum - 1), inviter: inviter, minimumDuffs: minimum,
                    claim: .registrationPending, paidRegistrationRecovers: recovers),
                .invalid(.belowMinimum, inviter: inviter))
            XCTAssertEqual(
                InvitationValidationPolicy.verdict(
                    status: status(amount: 3_000_000, isInstant: false, isChainLocked: false), inviter: inviter,
                    minimumDuffs: minimum, claim: .registrationPending, paidRegistrationRecovers: recovers),
                .awaitingChainLock)
        }
    }

    // MARK: - Whose claim it was

    func testClaimedByThisWalletButNotLoadedPointsAtFindIdentities() {
        let verdict = verdict(status(amount: 3_000_000, claimed: true, ours: true))
        XCTAssertEqual(verdict, .ownClaimNotLoaded)
        XCTAssertFalse(verdict.isDefinitive, "kept until Find identities loads the identity")
    }

    /// Spent, whoever spent it: final, and every copy goes. The dialog says
    /// how to restore the identity if it was this wallet's lost claim.
    func testClaimedByAnUnknownOwnerIsFinalEverywhere() {
        let verdict = verdict(status(amount: 3_000_000, claimed: true, ours: nil))
        XCTAssertEqual(verdict, .alreadyClaimed(inviter: inviter))
        XCTAssertTrue(verdict.isDefinitive)
        XCTAssertTrue(verdict.clearsEverywhere)
    }

    func testUnclaimedIsValid() {
        XCTAssertEqual(verdict(status(amount: 3_000_000, claimed: false)).amountDuffs, 3_000_000)
    }

    // MARK: - Claim failures arrive wrapped by the coordinator

    private func wrapped(_ error: Error) -> Error {
        DWIdentityRegistrationCoordinator.CoordinatorError.identityRegistration(error)
    }

    func testWrappedClaimFailuresAreRecognized() {
        // The claim reports an invalid parameter for its identity keys as well
        // as for the link: the card's link-only status query decides.
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.invalidNetwork("testnet"))), .refused)
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.invalidParameter("identityPubkeys is empty"))),
            .refused)
        // The wallet's typed error can concern another asset lock of the
        // same registration (a recovered Core lock): only reported.
        let typed = InvitationClaimFailure.classify(wrapped(PlatformWalletError.assetLockAlreadyConsumed("other outpoint")))
        XCTAssertEqual(typed, .refused)
        // The shape the SDK produces for a node's consensus rejection. It is
        // not proof-verified, so it is only reported: nothing is deleted
        // until the card's status query confirms it.
        let reported = InvitationClaimFailure.classify(wrapped(PlatformWalletError.consensusRejection(
            PlatformConsensusError(code: 10504, kind: .basic), "reworded by Platform")))
        XCTAssertEqual(reported, .refused)
        // The same code on the SDK's own error type, and beside text that
        // names another outcome: the code decides.
        XCTAssertEqual(
            InvitationClaimFailure.classify(wrapped(SDKError.consensusRejection(
                PlatformConsensusError(code: 10504, kind: .basic), "reworded by Platform"))),
            .refused)
        XCTAssertNil(
            InvitationClaimFailure.classify(wrapped(SDKError.consensusRejection(
                PlatformConsensusError(code: 40722, kind: .state), "already completely used"))))
        XCTAssertNil(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.consensusRejection(
                PlatformConsensusError(code: 40722, kind: .state), "some other rejection"))))
        // No consensus code and not the consensus error's own wording: the
        // text says nothing the claim can act on.
        XCTAssertNil(
            InvitationClaimFailure.classify(wrapped(PlatformWalletError.walletOperation(
                "IdentityAssetLockTransactionOutPointAlreadyConsumedError: asset lock outpoint already consumed"))))
    }

    /// A repeated claim is refused with one of two errors; both send the
    /// coordinator to look for the invitation's own identity at the pinned
    /// slot.
    func testARepeatedClaimIsRecognizedByItsTwoErrors() {
        XCTAssertTrue(InvitationClaimFailure.isRepeatedClaim(
            PlatformWalletError.invitationClaimedByThisWallet(identityId: "id")))
        XCTAssertTrue(InvitationClaimFailure.isRepeatedClaim(
            PlatformWalletError.assetLockAlreadyConsumed("voucher outpoint")))
        XCTAssertFalse(InvitationClaimFailure.isRepeatedClaim(PlatformWalletError.invalidNetwork("testnet")))
        XCTAssertFalse(InvitationClaimFailure.isRepeatedClaim(PlatformWalletError.walletOperation("timeout")))
        XCTAssertFalse(InvitationClaimFailure.isRepeatedClaim(PlatformWalletError.consensusRejection(
            PlatformConsensusError(code: 10504, kind: .basic), "consumed")))
    }

    func testAnUnconfirmedResultIsNotASpentReportWhateverItsText() {
        let unconfirmed: [Error] = [
            PlatformWalletError.transactionBroadcastUnconfirmed("asset lock already completely used"),
            PlatformWalletError.shieldedBroadcastUnconfirmed("asset lock already completely used")
        ]
        for error in unconfirmed {
            XCTAssertNil(InvitationClaimFailure.classify(wrapped(error)), "\(error)")
        }
    }

    func testUntypedSpentTextNeverDeletesTheInvitation() {
        let failure = InvitationClaimFailure.classify(wrapped(PlatformWalletError.walletOperation(
            "asset lock outpoint already completely used")))
        XCTAssertEqual(failure, .refused)
    }

    func testFailedNameRefreshNotificationsStayWithinTheRetryBudget() {
        // A fresh or answered invitation re-checks on a status change.
        XCTAssertTrue(InvitationNotReadyPolicy.revalidatesOnStatusChange(afterAttempts: 0))
        // Each not-ready check re-arms the name read; its failure posts the
        // status notification. That must not start another check, or the
        // budget below never runs out.
        for attempts in 1...InvitationNotReadyPolicy.attemptsBeforeRetry + 2 {
            XCTAssertFalse(InvitationNotReadyPolicy.revalidatesOnStatusChange(afterAttempts: attempts))
        }
    }

    func testStillConfirmingKeepsTheInvitation() {
        let failure = InvitationClaimFailure.classify(wrapped(PlatformWalletError.assetLockNotChainLocked(
            "the funding transaction is not yet chain-locked")))
        XCTAssertEqual(failure, .stillConfirming)
        // The SDK reports it typed (code 66); its text alone no longer decides.
        XCTAssertNil(InvitationClaimFailure.classify(wrapped(PlatformWalletError.walletOperation(
            "the funding transaction is not yet chain-locked"))))
    }

    // MARK: - The claim's typed refusals become the coordinator's own

    /// Before and after the PIN, a decision that stops the claim gives the
    /// same typed error.
    func testEachStoppingDecisionHasItsOwnError() {
        typealias C = DWIdentityRegistrationCoordinator
        let id = Data(repeating: 0x11, count: 32)
        XCTAssertNil(C.invitationRefusal(.claim))
        XCTAssertNil(C.invitationRefusal(.resumeOwnClaim(id)))
        XCTAssertEqual("\(String(describing: C.invitationRefusal(.otherIdentity)))",
                       "\(String(describing: C.CoordinatorError.invitationOtherIdentity as C.CoordinatorError?))")
        XCTAssertEqual("\(String(describing: C.invitationRefusal(.registrationPending)))",
                       "\(String(describing: C.CoordinatorError.invitationRegistrationPending as C.CoordinatorError?))")
        XCTAssertEqual("\(String(describing: C.invitationRefusal(.undetermined)))",
                       "\(String(describing: C.CoordinatorError.invitationUndetermined as C.CoordinatorError?))")
    }

    /// After the PIN, both invitation paths (the resume and the refused
    /// repeated claim) name the invitation's identity only when Platform,
    /// read in that check, shows it unnamed. A name that landed after an
    /// earlier empty read stops it; so does a read that fails.
    @MainActor
    func testAnInvitationsNameGoesOnOnlyAfterAFreshPlatformReadShowsNone() async {
        typealias C = DWIdentityRegistrationCoordinator
        let own = Data(repeating: 0x11, count: 32)
        let other = Data(repeating: 0x22, count: 32)
        func facts(needsUsername: Bool) -> InvitationClaimFacts {
            InvitationClaimFacts(
                identities: [.init(identityId: own, identityIndex: C.pinnedIdentityIndex)],
                hasPaidRegistrationLock: false, snapshotIdentityId: own, snapshotNeedsUsername: needsUsername)
        }
        struct ReadFailed: Error {}

        var stillUnnamed = await C.invitationIdentityStillUnnamed(
            own, readNamesFromPlatform: {}, localFacts: { facts(needsUsername: true) })
        XCTAssertTrue(stillUnnamed)

        // The local cache said "no name"; Platform, read now, holds one.
        var nameOnPlatform = false
        var read = false
        stillUnnamed = await C.invitationIdentityStillUnnamed(
            own,
            readNamesFromPlatform: { read = true; nameOnPlatform = true },
            localFacts: { facts(needsUsername: !nameOnPlatform) })
        XCTAssertTrue(read)
        XCTAssertFalse(stillUnnamed, "a name another device registered since the earlier read")

        stillUnnamed = await C.invitationIdentityStillUnnamed(
            own, readNamesFromPlatform: { throw ReadFailed() }, localFacts: { facts(needsUsername: true) })
        XCTAssertFalse(stillUnnamed, "the names could not be read")

        stillUnnamed = await C.invitationIdentityStillUnnamed(
            own, readNamesFromPlatform: {}, localFacts: { nil })
        XCTAssertFalse(stillUnnamed, "the wallet could not be read, or the names are still loading")

        stillUnnamed = await C.invitationIdentityStillUnnamed(
            other, readNamesFromPlatform: {}, localFacts: { facts(needsUsername: true) })
        XCTAssertFalse(stillUnnamed, "not the invitation's identity")
    }

    func testTypedClaimRefusalsAreMapped() {
        typealias C = DWIdentityRegistrationCoordinator
        XCTAssertEqual(
            "\(C.invitationClaimFailure(PlatformWalletError.invitationKeysAlreadyRegistered(identityId: nil, consensus: nil)))",
            "\(C.CoordinatorError.invitationKeysTaken)")
        // Platform refused the broadcast: not proof-verified, so the SDK
        // error stays and nothing ends the invitation.
        let broadcastRefusal = C.invitationClaimFailure(PlatformWalletError.invitationKeysAlreadyRegistered(
            identityId: nil, consensus: PlatformConsensusError(code: 40207, kind: .state)))
        XCTAssertFalse(broadcastRefusal is C.CoordinatorError)
        XCTAssertNil(InvitationClaimFailure.classify(broadcastRefusal))
        XCTAssertEqual(
            "\(C.invitationClaimFailure(PlatformWalletError.invitationClaimedByThisWallet(identityId: "x")))",
            "\(C.CoordinatorError.invitationOwnClaimRecorded)")
        XCTAssertEqual(
            "\(C.invitationClaimFailure(PlatformWalletError.invitationNotReady("quorum")))",
            "\(C.CoordinatorError.invitationNotSynced)")
        // A spent voucher and one not chain-locked keep their SDK errors for
        // `classify`, which the card's re-check then settles.
        XCTAssertEqual(
            InvitationClaimFailure.classify(C.invitationClaimFailure(PlatformWalletError.assetLockAlreadyConsumed("x"))),
            .refused)
        XCTAssertEqual(
            InvitationClaimFailure.classify(C.invitationClaimFailure(PlatformWalletError.assetLockNotChainLocked("x"))),
            .stillConfirming)
    }

    func testTheFormEndsOnlyThisWalletsCopyForAnotherIdentity() {
        typealias C = DWIdentityRegistrationCoordinator.CoordinatorError
        XCTAssertEqual(CreateUsernameViewModel.invitationOutcome(of: .invitationOtherIdentity), .endsThisWalletsCopy)
        XCTAssertEqual(CreateUsernameViewModel.invitationOutcome(of: .invitationKeysTaken), .endsThisWalletsCopy)
        for kept: C in [.invitationRegistrationPending, .invitationUndetermined, .invitationNotSynced,
                        .invitationOwnClaimRecorded] {
            XCTAssertEqual(CreateUsernameViewModel.invitationOutcome(of: kept), .recheck, "\(kept)")
        }
        XCTAssertNil(CreateUsernameViewModel.invitationOutcome(of: .authFailed))
    }

    // MARK: - The wallet's state is read again after the status query

    private func state(loading: Bool = false) -> InvitationWalletState {
        InvitationWalletState(isLoading: loading, hasRegisteredUsername: false, hasPendingUsernameRequest: false)
    }

    private let noIdentity = InvitationClaimFacts(
        identities: [], hasPaidRegistrationLock: false, snapshotIdentityId: nil, snapshotNeedsUsername: false)

    @MainActor
    private func decide(
        state: @escaping @MainActor () -> InvitationWalletState,
        facts: @escaping @MainActor () -> InvitationClaimFacts?,
        recovers: Bool = false,
        query: @escaping @MainActor (String) async throws -> ManagedPlatformWallet.InvitationClaimStatus
    ) async -> InvitationValidation? {
        await InvitationValidationPolicy.decide(
            uri: "dashpay://invite?x",
            previewIsValid: true,
            inviter: inviter,
            walletState: state,
            claimFacts: facts,
            paidRegistrationRecovers: { recovers },
            queryStatus: query)
    }

    @MainActor
    func testOwnIdentityLearnedDuringTheQueryIsNotAlreadyClaimed() async {
        let claimed = status(amount: 3_000_000, claimed: true, ours: true)
        var facts = noIdentity
        let verdict = await decide(state: { self.state() }, facts: { facts }, query: { _ in
            // The wallet finishes loading its own earlier claim while the
            // query is in flight.
            facts = InvitationClaimFacts(
                identities: [.init(identityId: claimed.prospectiveIdentityId, identityIndex: 0)],
                hasPaidRegistrationLock: false,
                snapshotIdentityId: claimed.prospectiveIdentityId,
                snapshotNeedsUsername: true)
            return claimed
        })
        XCTAssertEqual(verdict?.amountDuffs, 3_000_000, "our own claim resumes; it is not \"already claimed\"")
    }

    @MainActor
    func testAnUnreadableStoreIsUndetermined() async {
        let verdict = await decide(state: { self.state() }, facts: { nil }, query: { _ in
            self.status(amount: 3_000_000)
        })
        XCTAssertEqual(verdict, .undetermined)
    }

    @MainActor
    func testAPaidRegistrationTheRecoveryFinishesIsPending() async {
        let paid = InvitationClaimFacts(
            identities: [], hasPaidRegistrationLock: true, snapshotIdentityId: nil, snapshotNeedsUsername: false)
        let verdict = await decide(state: { self.state() }, facts: { paid }, recovers: true, query: { _ in
            self.status(amount: 3_000_000)
        })
        XCTAssertEqual(verdict, .pendingPaidRegistration)
    }

    /// Not a verdict: the card's bounded not-ready re-checks take over.
    @MainActor
    func testUnverifiedPlatformAnswersAreNotAVerdict() async {
        let verdict = await decide(state: { self.state() }, facts: { self.noIdentity }, query: { _ in
            throw PlatformWalletError.invitationNotReady("quorum not verified")
        })
        XCTAssertNil(verdict)
    }

    @MainActor
    func testUsernameRegisteredDuringTheQueryWins() async {
        var current = state()
        let verdict = await decide(state: { current }, facts: { self.noIdentity }, query: { _ in
            current.hasRegisteredUsername = true
            return self.status(amount: 3_000_000)
        })
        XCTAssertEqual(verdict, .alreadyHasIdentity)
    }

    @MainActor
    func testSnapshotReloadingDuringTheQueryIsNotAVerdict() async {
        var current = state()
        let verdict = await decide(state: { current }, facts: { self.noIdentity }, query: { _ in
            current.isLoading = true
            return self.status(amount: 3_000_000, claimed: true)
        })
        XCTAssertNil(verdict)
    }

    func testNonContestedInvitationPaysOnlyForNonContestedNames() {
        let contested: (String) -> Bool = { $0 == "alice" }
        XCTAssertFalse(CreateUsernameViewModel.invitationPays(for: "alice", tier: .nonContested, isContested: contested))
        XCTAssertTrue(CreateUsernameViewModel.invitationPays(for: "alice2", tier: .nonContested, isContested: contested))
        XCTAssertTrue(CreateUsernameViewModel.invitationPays(for: "alice", tier: .contested, isContested: contested))
        XCTAssertTrue(CreateUsernameViewModel.invitationPays(for: "alice", tier: nil, isContested: contested))
    }

    func testClaimFailureWordingClaimsNoVerdict() {
        // Not proven spent or invalid, so it says neither.
        XCTAssertFalse(InvitationClaimFailure.refused.message.contains("claimed"))
        XCTAssertFalse(InvitationClaimFailure.refused.message.contains("not valid"))
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

    }

    // MARK: - Waiting for the wallet

    /// A failed identity-name read keeps the check unanswered; the card
    /// waits a few rounds (re-arming the read each time) and then offers
    /// Retry instead of Verifying forever.
    func testNotReadyChecksEndInRetryNotEndlessVerifying() {
        XCTAssertEqual(InvitationNotReadyPolicy.next(afterAttempts: 1), .waitAndRecheck)
        XCTAssertEqual(InvitationNotReadyPolicy.next(afterAttempts: 2), .waitAndRecheck)
        XCTAssertEqual(InvitationNotReadyPolicy.next(afterAttempts: 3), .offerRetry)
        XCTAssertEqual(InvitationNotReadyPolicy.next(afterAttempts: 10), .offerRetry)
    }

    // MARK: - Explanations for a link taken while locked

    /// Locked, into a wallet that already has a username: nothing is stored,
    /// so the explanation is held for after unlock.
    func testLockedReceiptIntoARegisteredWalletHoldsItsExplanation() {
        var notice = InvitationReceiptNotice()
        notice.hold(.alreadyHasIdentity)
        XCTAssertEqual(notice.take(), .alreadyHasIdentity)
        XCTAssertNil(notice.take(), "shown once")
    }

    func testFailedWriteWhileLockedHoldsItsExplanation() {
        var notice = InvitationReceiptNotice()
        notice.hold(.storageFailed)
        XCTAssertEqual(notice.outcome, .storageFailed)
    }

    func testStoredOrSuspendedNeedsNoExplanationAndAWipeDiscardsOne() {
        var notice = InvitationReceiptNotice()
        notice.hold(.busy)
        notice.hold(.stored)
        XCTAssertNil(notice.outcome, "a later stored invitation makes the refusal moot")
        notice.hold(.suspended)
        XCTAssertNil(notice.outcome)
        notice.hold(.storageFailed)
        notice.discard()
        XCTAssertNil(notice.take(), "nothing received before a wipe is explained after it")
    }

    // MARK: - Inviter name

    func testInviterBestNamePrefersDisplayName() {
        XCTAssertEqual(inviter.bestName, "Alice")
        XCTAssertEqual(InvitationInviter(username: "bob", displayName: "  ", avatarURL: nil).bestName, "bob")
        XCTAssertNil(InvitationInviter.unknown.bestName)
        XCTAssertEqual(InvitationOutcomeDialogs.senderName(.unknown), "DashPay")
    }
}

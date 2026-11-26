//
//  InvitationClaimEligibilityTests.swift
//  DashWalletTests
//
//  Which identity an invitation's username may land on, decided from local
//  data only (dashwallet-ios#1224).
//

import Foundation
import SwiftData
import SwiftDashSDK
import XCTest
@testable import dashpay

@MainActor
final class InvitationClaimEligibilityTests: XCTestCase {

    private let pinned: UInt32 = 0
    private let invitationIdentity = Data(repeating: 0x11, count: 32)
    private let otherIdentity = Data(repeating: 0x22, count: 32)
    private let walletId = Data(repeating: 0xA1, count: 32)

    private func facts(
        _ identities: [(Data, UInt32)] = [],
        paidLock: Bool = false,
        snapshotIdentity: Data? = nil,
        needsUsername: Bool = false
    ) -> InvitationClaimFacts {
        InvitationClaimFacts(
            identities: identities.map { .init(identityId: $0.0, identityIndex: $0.1) },
            hasPaidRegistrationLock: paidLock,
            snapshotIdentityId: snapshotIdentity,
            snapshotNeedsUsername: needsUsername)
    }

    private func decide(_ facts: InvitationClaimFacts, prospective: Data?) -> InvitationClaimDecision {
        InvitationClaimEligibility.decide(facts, prospectiveIdentityId: prospective, pinnedIndex: pinned)
    }

    // MARK: - The five rows

    func testRow1TheInvitationsOwnUnnamedIdentityResumes() {
        let own = facts([(invitationIdentity, pinned)], snapshotIdentity: invitationIdentity, needsUsername: true)
        XCTAssertEqual(decide(own, prospective: invitationIdentity), .resumeOwnClaim(invitationIdentity))
    }

    func testRow2AnyOtherIdentityRefuses() {
        let other = facts([(otherIdentity, pinned)], snapshotIdentity: otherIdentity, needsUsername: true)
        XCTAssertEqual(decide(other, prospective: invitationIdentity), .otherIdentity)
    }

    func testRow2TheInvitationsIdentityAtAnotherIndexRefuses() {
        let elsewhere = facts([(invitationIdentity, 1)], snapshotIdentity: invitationIdentity, needsUsername: true)
        XCTAssertEqual(decide(elsewhere, prospective: invitationIdentity), .otherIdentity)
    }

    func testRow2TwoIdentitiesRefuseEvenWhenOneIsTheInvitations() {
        let two = facts(
            [(invitationIdentity, pinned), (otherIdentity, 1)],
            snapshotIdentity: invitationIdentity, needsUsername: true)
        XCTAssertEqual(decide(two, prospective: invitationIdentity), .otherIdentity)
    }

    func testRow3AnIdentityWithTheInvitationsIdentityUnknownIsUndetermined() {
        let unknown = facts([(otherIdentity, pinned)], snapshotIdentity: otherIdentity, needsUsername: true)
        XCTAssertEqual(decide(unknown, prospective: nil), .undetermined)
    }

    func testRow4APaidRegistrationWithNoIdentityIsPending() {
        XCTAssertEqual(decide(facts(paidLock: true), prospective: nil), .registrationPending)
        XCTAssertEqual(decide(facts(paidLock: true), prospective: invitationIdentity), .registrationPending)
    }

    func testRow5AnEmptyWalletClaims() {
        XCTAssertEqual(decide(facts(), prospective: nil), .claim)
        XCTAssertEqual(decide(facts(), prospective: invitationIdentity), .claim)
    }

    // MARK: - The snapshot must agree

    /// The snapshot shows an identity the wallet row does not hold (the
    /// row is an orphan, or the reads raced): never claim over it.
    func testAnIdentityOnlyTheSnapshotKnowsIsUndetermined() {
        XCTAssertEqual(decide(facts(snapshotIdentity: otherIdentity), prospective: nil), .undetermined)
    }

    /// The invitation's identity already has a name, or its names are not
    /// loaded yet: not a resume.
    func testTheOwnIdentityWithoutAConfirmedMissingNameIsUndetermined() {
        let named = facts([(invitationIdentity, pinned)], snapshotIdentity: invitationIdentity, needsUsername: false)
        XCTAssertEqual(decide(named, prospective: invitationIdentity), .undetermined)
        let mismatched = facts([(invitationIdentity, pinned)], snapshotIdentity: otherIdentity, needsUsername: true)
        XCTAssertEqual(decide(mismatched, prospective: invitationIdentity), .undetermined)
    }

    // MARK: - Paid registration locks

    func testOnlyConsumedAndDrainCompletedLocksAreFinished() {
        XCTAssertTrue(IdentityRegistrationLocks.isUnfinished(statusRaw: 0), "Built: re-broadcast at launch")
        XCTAssertTrue(IdentityRegistrationLocks.isUnfinished(statusRaw: 1))
        XCTAssertTrue(IdentityRegistrationLocks.isUnfinished(statusRaw: 2))
        XCTAssertTrue(IdentityRegistrationLocks.isUnfinished(statusRaw: 3))
        XCTAssertFalse(IdentityRegistrationLocks.isUnfinished(statusRaw: 4))
        XCTAssertTrue(IdentityRegistrationLocks.isUnfinished(statusRaw: 5), "RecoveredFromChain: restored")
        XCTAssertFalse(IdentityRegistrationLocks.isUnfinished(statusRaw: 6))
        XCTAssertTrue(IdentityRegistrationLocks.isUnfinished(statusRaw: 99), "an unknown status is not assumed spent")
    }

    // MARK: - Reading the store

    private func makeContainer() throws -> ModelContainer {
        try DashModelContainer.inMemoryWithoutCloudKit()
    }

    private func insertWallet(_ container: ModelContainer, identities: [(Data, UInt32)] = []) throws {
        let wallet = PersistentWallet(walletId: walletId, network: .testnet)
        container.mainContext.insert(wallet)
        for (id, index) in identities {
            let identity = PersistentIdentity(identityId: id, network: .testnet, identityIndex: index)
            container.mainContext.insert(identity)
            identity.wallet = wallet
        }
        try container.mainContext.save()
    }

    private func insertLock(
        _ container: ModelContainer, status: Int, fundingType: Int = 0, index: Int32 = 0, wallet: Data? = nil
    ) throws {
        container.mainContext.insert(PersistentAssetLock(
            outPointHex: "\(UUID().uuidString):0",
            walletId: wallet ?? walletId,
            transactionBytes: Data(),
            fundingTypeRaw: fundingType,
            identityIndexRaw: index,
            amountDuffs: 3_000_000,
            statusRaw: status))
        try container.mainContext.save()
    }

    private func readFacts(_ container: ModelContainer) throws -> InvitationClaimFacts {
        try InvitationClaimEligibility.localFacts(
            walletId: walletId, pinnedIndex: pinned, modelContainer: container, snapshot: .empty)
    }

    func testAMissingWalletRowThrows() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(try readFacts(container))
    }

    func testFactsListEveryIdentityOfTheWalletOnAnyIndex() throws {
        let container = try makeContainer()
        try insertWallet(container, identities: [(invitationIdentity, 1), (otherIdentity, 0)])
        let read = try readFacts(container)
        XCTAssertEqual(Set(read.identities.map(\.identityId)), [invitationIdentity, otherIdentity])
        XCTAssertEqual(read.identities.first { $0.identityId == invitationIdentity }?.identityIndex, 1)
    }

    func testPaidLockStatusesDecideRow4() throws {
        for (status, paid) in [(0, true), (4, false), (5, true), (6, false)] {
            let container = try makeContainer()
            try insertWallet(container)
            try insertLock(container, status: status)
            XCTAssertEqual(try readFacts(container).hasPaidRegistrationLock, paid, "status \(status)")
        }
    }

    func testOnlyThisWalletsRegistrationLockAtThePinnedIndexCounts() throws {
        let container = try makeContainer()
        try insertWallet(container)
        try insertLock(container, status: 2, fundingType: 1) // a top-up
        try insertLock(container, status: 2, index: 1) // another slot
        try insertLock(container, status: 2, wallet: Data(repeating: 0xB2, count: 32)) // another wallet
        XCTAssertFalse(try readFacts(container).hasPaidRegistrationLock)
    }
}

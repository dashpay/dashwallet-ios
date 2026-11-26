//
//  InvitationClaimEligibility.swift
//  DashWallet
//
//  Whether this wallet may claim an invitation, finish its own earlier claim,
//  or must stop — decided from local data only. The Home card and the
//  registration coordinator ask the same function, so the two never disagree
//  about which identity an invitation's username lands on.
//

import Foundation
import SwiftData
import SwiftDashSDK

/// What the wallet holds locally when an invitation is about to be claimed.
struct InvitationClaimFacts: Equatable {
    struct LocalIdentity: Equatable {
        let identityId: Data
        let identityIndex: UInt32
    }

    /// Every identity the wallet row records, on any index.
    let identities: [LocalIdentity]
    /// A Core payment for an identity registration at the pinned index that
    /// has not reached Platform yet (`IdentityRegistrationLocks`).
    let hasPaidRegistrationLock: Bool
    /// The identity the current-user snapshot shows, read after every await.
    let snapshotIdentityId: Data?
    /// That identity has no username and no name request yet.
    let snapshotNeedsUsername: Bool
}

enum InvitationClaimDecision: Equatable {
    /// The only identity is the one this invitation created, at the pinned
    /// index, still without a username: finish it, no new claim.
    case resumeOwnClaim(Data)
    /// The wallet has an identity this invitation did not create.
    case otherIdentity
    /// The local data cannot tell; nothing is claimed or resumed.
    case undetermined
    /// No identity, but a paid Core registration is waiting to reach Platform.
    case registrationPending
    /// No identity and no paid registration: the invitation may be claimed.
    case claim

    /// For the log: the case, and a short identity id (public data).
    var logLabel: String {
        switch self {
        case .resumeOwnClaim(let identityId):
            return "resumeOwnClaim(\(identityId.prefix(4).map { String(format: "%02x", $0) }.joined())…)"
        case .otherIdentity: return "otherIdentity"
        case .undetermined: return "undetermined"
        case .registrationPending: return "registrationPending"
        case .claim: return "claim"
        }
    }
}

enum InvitationClaimEligibility {

    /// - Parameter prospectiveIdentityId: the identity the invitation creates;
    ///   nil when it is not known (only asked for when an identity exists).
    static func decide(
        _ facts: InvitationClaimFacts,
        prospectiveIdentityId: Data?,
        pinnedIndex: UInt32
    ) -> InvitationClaimDecision {
        guard !facts.identities.isEmpty else {
            // The snapshot knows an identity the wallet row does not: the two
            // reads disagree, so neither a claim nor a resume is safe.
            guard facts.snapshotIdentityId == nil else { return .undetermined }
            return facts.hasPaidRegistrationLock ? .registrationPending : .claim
        }
        guard let prospectiveIdentityId else { return .undetermined }
        if facts.identities == [.init(identityId: prospectiveIdentityId, identityIndex: pinnedIndex)] {
            return facts.snapshotIdentityId == prospectiveIdentityId && facts.snapshotNeedsUsername
                ? .resumeOwnClaim(prospectiveIdentityId)
                : .undetermined
        }
        return .otherIdentity
    }

    /// Reads the facts; throws when the store cannot answer (a failed fetch,
    /// no wallet row), which the callers treat as undetermined.
    @MainActor
    static func localFacts(
        walletId: Data,
        pinnedIndex: UInt32,
        modelContainer: ModelContainer,
        snapshot: DWCurrentUserIdentityInfo.Snapshot
    ) throws -> InvitationClaimFacts {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<PersistentWallet>(predicate: PersistentWallet.predicate(walletId: walletId))
        descriptor.fetchLimit = 1
        guard let wallet = try context.fetch(descriptor).first else {
            throw EligibilityError.noWalletRow
        }
        return InvitationClaimFacts(
            identities: wallet.identities.map {
                .init(identityId: $0.identityId, identityIndex: $0.identityIndex)
            },
            hasPaidRegistrationLock: try IdentityRegistrationLocks.unfinished(
                walletId: walletId, identityIndex: pinnedIndex, in: context) != nil,
            snapshotIdentityId: snapshot.identityId,
            snapshotNeedsUsername: snapshot.needsUsername)
    }

    enum EligibilityError: Error {
        case noWalletRow
    }
}

/// The Core payments for an identity registration that may still reach
/// Platform. Shared by the invitation check and the coordinator's recovery,
/// so both count the same locks as paid.
enum IdentityRegistrationLocks {
    /// The asset-lock funding type of an identity registration.
    static let registrationFundingType = 0

    /// Paid, not finished: every status but Consumed (4) and DrainCompleted
    /// (6). Built (0) counts: the launch catch-up re-broadcasts it, and its
    /// row is written before any peer accepted the transaction.
    /// RecoveredFromChain (5) counts: a restore rebuilds every old lock at 5,
    /// and one with no identity is a registration that never finished.
    static func isUnfinished(statusRaw: Int) -> Bool {
        guard let status = AssetLockStatus(rawValue: statusRaw) else {
            // A status this build does not know is not assumed spent.
            return true
        }
        switch status {
        case .consumed, .drainCompleted:
            return false
        case .built, .broadcast, .instantSendLocked, .chainLocked, .recoveredFromChain:
            return true
        }
    }

    /// The oldest unfinished registration lock for `identityIndex`. The
    /// original payment is chosen on purpose: a wallet hit by a double
    /// registration may hold two, and resuming the newer one would strand
    /// the first payment again.
    @MainActor
    static func unfinished(walletId: Data, identityIndex: UInt32, in context: ModelContext) throws -> PersistentAssetLock? {
        let index = Int32(bitPattern: identityIndex)
        let fundingType = registrationFundingType
        let descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate { row in
                row.walletId == walletId
                    && row.identityIndexRaw == index
                    && row.fundingTypeRaw == fundingType
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return try context.fetch(descriptor).first { isUnfinished(statusRaw: $0.statusRaw) }
    }
}

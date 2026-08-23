//
//  DWIdentityKeyUpgrader.swift
//  DashWallet
//
//  Adds missing DashPay ENCRYPTION / DECRYPTION keys to the current
//  identity via an IdentityUpdate transition (migration Row #18).
//
//  New registrations include both keys in IdentityCreate. This
//  upgrader remains as a lazy fallback for identities created before
//  that policy or whose Platform key set is otherwise incomplete.
//
//  Key derivation/persistence is shared with the registration flow
//  through `DWDashPayIdentityKeys`.
//
//  dashpay target only.
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
enum DWIdentityKeyUpgrader {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-key-upgrader")

    typealias UpgradeError = DWDashPayIdentityKeys.KeyError

    /// Ensure the identity has enabled ECDSA_SECP256K1 keys with
    /// purposes ENCRYPTION and DECRYPTION, broadcasting one
    /// IdentityUpdate that adds whichever are missing. No-op when
    /// both already exist. Caller must have passed the spend/PIN
    /// gate already — the update transition itself is signed by the
    /// `KeychainSigner` with the identity's existing MASTER key.
    ///
    /// - Returns: true when an update transition was broadcast.
    @discardableResult
    static func ensureDashPayKeys(
        wallet: ManagedPlatformWallet,
        ownerId: Data,
        modelContainer: ModelContainer,
        sdk: SDK,
        network: Network
    ) async throws -> Bool {
        // Authoritative current key set from Platform (local SwiftData
        // rows can lag — e.g. keys added from another device).
        let keysById = try await sdk.identityGetKeys(identityId: ownerId.toBase58String())
        let keys = keysById.values.compactMap { $0 as? [String: Any] }
        let missingPurposes = Self.missingDashPayPurposes(inPlatformKeysById: keysById)
        guard !missingPurposes.isEmpty else { return false }

        Self.logger.info("🪪 KEY-UPGRADE :: identity missing \(missingPurposes.count, privacy: .public) DashPay key(s) — deriving + broadcasting IdentityUpdate")

        guard let identityRow = fetchIdentityRow(ownerId: ownerId, modelContainer: modelContainer) else {
            throw UpgradeError.noIdentityRow
        }

        // Next free hardened key slot: extend past every key Platform
        // knows about (response keys are keyed by id and carry an
        // `id` field), falling back to the local rows.
        let networkMaxId = keys.compactMap { $0["id"] as? Int }.max().map(UInt32.init)
        let localMaxId = identityRow.identityPublicKeys.map(\.id).max()
        var nextKeyId = (max(networkMaxId ?? 0, localMaxId ?? 0)) + 1

        var specifications: [DWDashPayIdentityKeys.KeySpecification] = []
        for purpose in missingPurposes {
            let chosenKeyId = nextKeyId
            nextKeyId += 1
            specifications.append(.init(keyId: chosenKeyId, purpose: purpose))
        }

        let rows = try DWDashPayIdentityKeys.deriveAndPersist(
            wallet: wallet,
            identityIdString: identityRow.identityIdString,
            identityIndex: identityRow.identityIndex,
            specifications: specifications,
            network: network)

        let signer = KeychainSigner(modelContainer: modelContainer)
        try await wallet.updateIdentity(
            identityId: ownerId,
            addPublicKeys: rows,
            signer: signer)

        Self.logger.info("🪪 KEY-UPGRADE :: IdentityUpdate broadcast — added \(rows.count, privacy: .public) key(s) at ids \(rows.map(\.keyId).map(String.init).joined(separator: ","), privacy: .public)")
        return true
    }

    /// The DIP-15 purposes (ENCRYPTION / DECRYPTION) that lack an enabled
    /// ECDSA_SECP256K1 key in a Platform `identityGetKeys` response. Shared
    /// by the upgrade broadcast above and the Contacts tab's authoritative
    /// "is Enable DashPay really needed?" re-check.
    nonisolated static func missingDashPayPurposes(
        inPlatformKeysById keysById: [String: Any]
    ) -> [KeyPurpose] {
        let keys = keysById.values.compactMap { $0 as? [String: Any] }
        func hasEnabledECDSAKey(purpose: Int) -> Bool {
            keys.contains { key in
                (key["purpose"] as? Int) == purpose
                    && (key["type"] as? Int) == 0  // ECDSA_SECP256K1
                    && (key["disabledAt"] == nil || key["disabledAt"] is NSNull)
            }
        }
        var missing: [KeyPurpose] = []
        if !hasEnabledECDSAKey(purpose: 1) { missing.append(.encryption) }
        if !hasEnabledECDSAKey(purpose: 2) { missing.append(.decryption) }
        return missing
    }

    private static func fetchIdentityRow(
        ownerId: Data,
        modelContainer: ModelContainer
    ) -> PersistentIdentity? {
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.identityId == ownerId })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

/// Re-fetches an identity from Platform through the Rust load pipeline
/// (`loadIdentity(atIndex:)`), folding the authoritative state — public
/// keys included — back into the wallet and, via the persistence event
/// channel, the local SwiftData rows. Backs the Storage Explorer's
/// pull-to-refresh so keys added from another device become visible.
///
/// dashpay target only (same as the upgrader above).
@MainActor
enum DWIdentityReloader {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.identity-reloader")

    /// Reload the identity persisted at `identityIndex`. Errors are logged,
    /// not thrown — pull-to-refresh has no failure UI, and the stale local
    /// rows remain an honest fallback.
    static func reload(identityIndex: UInt32) async {
        guard let wallet = SwiftDashSDKHost.shared.wallet else { return }
        do {
            let id = try await wallet.loadIdentity(atIndex: identityIndex)
            Self.logger.info("🪪 RELOAD :: identity at index \(identityIndex, privacy: .public) reloaded (found=\(id != nil, privacy: .public))")
        } catch {
            Self.logger.error("🪪 RELOAD :: identity reload failed at index \(identityIndex, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Reload the current user's main identity, resolving its identity
    /// index from the persisted row. No-op when no identity is registered.
    static func reloadCurrentUserIdentity() async {
        guard let modelContainer = SwiftDashSDKHost.shared.modelContainer,
              let ownerId = DWCurrentUserIdentityInfo.shared.identityId else { return }
        var descriptor = FetchDescriptor<PersistentIdentity>(
            predicate: #Predicate { $0.identityId == ownerId })
        descriptor.fetchLimit = 1
        guard let row = (try? modelContainer.mainContext.fetch(descriptor))?.first else { return }
        await reload(identityIndex: row.identityIndex)
    }
}

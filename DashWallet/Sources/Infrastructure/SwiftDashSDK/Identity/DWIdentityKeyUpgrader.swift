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

        func hasEnabledECDSAKey(purpose: Int) -> Bool {
            keys.contains { key in
                (key["purpose"] as? Int) == purpose
                    && (key["type"] as? Int) == 0  // ECDSA_SECP256K1
                    && (key["disabledAt"] == nil || key["disabledAt"] is NSNull)
            }
        }

        var missingPurposes: [KeyPurpose] = []
        if !hasEnabledECDSAKey(purpose: 1) { missingPurposes.append(.encryption) }
        if !hasEnabledECDSAKey(purpose: 2) { missingPurposes.append(.decryption) }
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

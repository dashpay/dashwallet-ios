//
//  DWIdentityKeyUpgrader.swift
//  DashWallet
//
//  Adds missing DashPay ENCRYPTION / DECRYPTION keys to the current
//  identity via an IdentityUpdate transition (migration Row #18).
//
//  Why this exists: dashwallet's registration flow
//  (`prePersistIdentityKeysForRegistration`) derives AUTHENTICATION
//  keys only — the Rust ladder is pinned to
//  `(ECDSA_SECP256K1, AUTHENTICATION, MASTER|HIGH)` — so identities
//  registered here can't send contact requests: the SDK's
//  `select_own_encryption_key` fails with "Identity has no enabled
//  ECDSA_SECP256K1 encryption key". This upgrader runs lazily before
//  the first contact action and brings the identity up to the DashPay
//  key set (ENCRYPTION + DECRYPTION, MEDIUM security, ECDSA — the
//  same shape SwiftExampleApp's add-key flow produces, verified
//  working on testnet).
//
//  The derive → validate → persist → updateIdentity sequence is a
//  port of SwiftExampleApp's `IdentityKeyAddition.prepareKeys`
//  (packages/swift-sdk/SwiftExampleApp/Views/IdentityKeyAddition.swift),
//  narrowed to the two ECDSA DashPay purposes.
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

    /// DashPay system contract id — `dashpay_contract::ID_BYTES` in
    /// the platform repo (base58 `Bwr4WHCPz5rFVAD87RqTs3izo4zpzwsEdKPWUT1NS1C7`).
    private static let dashPayContractId = Data([
        162, 161, 180, 172, 111, 239, 34, 234,
        42, 26, 104, 232, 18, 54, 68, 179,
        87, 135, 95, 107, 65, 44, 24, 16,
        146, 129, 193, 70, 231, 178, 113, 188,
    ])

    enum UpgradeError: LocalizedError {
        case noIdentityRow
        case derivationMismatch
        case keychainWriteFailed

        var errorDescription: String? {
            switch self {
            case .noIdentityRow:
                return NSLocalizedString("No DashPay identity is registered", comment: "DashPay")
            case .derivationMismatch:
                return "Derived key didn't match its public key — refusing to broadcast."
            case .keychainWriteFailed:
                return "Could not persist new key to the iOS Keychain — aborted before broadcast."
            }
        }
    }

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

        var rows: [ManagedPlatformWallet.IdentityPubkey] = []
        for purpose in missingPurposes {
            let chosenKeyId = nextKeyId
            nextKeyId += 1

            // 1. Derive the keypair at the slot (path build + secp256k1
            //    derive happen Rust-side; mnemonic stays behind the
            //    resolver trampoline).
            let preview = try wallet.deriveIdentityAuthKeyAtSlot(
                identityIndex: identityRow.identityIndex,
                keyId: chosenKeyId,
                network: network)

            // 2. Defence against derivation drift before anything is
            //    persisted or broadcast.
            guard KeyValidation.validatePrivateKeyForPublicKey(
                privateKeyHex: preview.privateKeyData.toHexString(),
                publicKeyHex: preview.publicKeyHex,
                keyType: .ecdsaSecp256k1,
                network: network)
            else {
                throw UpgradeError.derivationMismatch
            }

            // 3. Persist the private scalar so the KeychainSigner
            //    trampoline can use the key later (and sign the
            //    update transition's proof-of-possession if required).
            let pubKeyHashHex = SwiftDashSDK.KeychainManager.computePublicKeyHashHex(preview.publicKeyData)
            let metadata = IdentityPrivateKeyMetadata(
                identityId: identityRow.identityIdString,
                keyId: chosenKeyId,
                walletId: wallet.walletId.toHexString(),
                identityIndex: identityRow.identityIndex,
                keyIndex: chosenKeyId,
                derivationPath: preview.derivationPath,
                publicKey: preview.publicKeyHex,
                publicKeyHash: pubKeyHashHex,
                keyType: KeyType.ecdsaSecp256k1.rawValue,
                purpose: purpose.rawValue,
                securityLevel: SecurityLevel.medium.rawValue)
            guard KeychainManager.shared.storeIdentityPrivateKey(
                preview.privateKeyData,
                derivationPath: preview.derivationPath,
                metadata: metadata) != nil
            else {
                throw UpgradeError.keychainWriteFailed
            }

            // 4. The on-chain key row. MEDIUM security. Drive REQUIRES
            //    contract bounds on Encryption/Decryption keys added
            //    via IdentityUpdate, and DashPay's contract config only
            //    declares the bounds requirement at the DOCUMENT-TYPE
            //    level — `SingleContract` (kind 1) is rejected, it must
            //    be `SingleContractDocumentType(DashPay, "contactRequest")`
            //    (kind 2). See rs-drive-abci
            //    `validate_identity_public_key_contract_bounds/v0/mod.rs`
            //    and SwiftExampleApp's AddIdentityKeyView, whose added
            //    keys (this exact shape) verifiably work on testnet.
            //    The send path's own-key selector checks purpose/type/
            //    enabled only, so the bound doesn't affect selection.
            rows.append(ManagedPlatformWallet.IdentityPubkey(
                keyId: chosenKeyId,
                keyType: .ecdsaSecp256k1,
                purpose: purpose,
                securityLevel: .medium,
                pubkeyBytes: preview.publicKeyData,
                contractBounds: .singleContractDocumentType(
                    id: Self.dashPayContractId,
                    documentTypeName: "contactRequest")))
        }

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

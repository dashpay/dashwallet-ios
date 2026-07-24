//
//  DWDashPayIdentityKeys.swift
//  DashWallet
//
//  Shared DashPay identity-key policy for registration-time creation
//  and the lazy IdentityUpdate fallback.
//

import Foundation
import SwiftDashSDK

enum DWDashPayIdentityKeys {

    /// DashPay system contract id — `dashpay_contract::ID_BYTES` in
    /// the platform repo (base58
    /// `Bwr4WHCPz5rFVAD87RqTs3izo4zpzwsEdKPWUT1NS1C7`).
    static let dashPayContractId = Data([
        162, 161, 180, 172, 111, 239, 34, 234,
        42, 26, 104, 232, 18, 54, 68, 179,
        87, 135, 95, 107, 65, 44, 24, 16,
        146, 129, 193, 70, 231, 178, 113, 188,
    ])

    static let contactRequestDocumentType = "contactRequest"

    struct KeySpecification: Equatable, Sendable {
        let keyId: UInt32
        let purpose: KeyPurpose
        let keyType: KeyType = .ecdsaSecp256k1
        let securityLevel: SecurityLevel = .medium

        var contractBounds: ManagedPlatformWallet.ContractBounds {
            .singleContractDocumentType(
                id: DWDashPayIdentityKeys.dashPayContractId,
                documentTypeName: DWDashPayIdentityKeys.contactRequestDocumentType)
        }
    }

    enum KeyError: LocalizedError {
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

    /// The registration-time pair appended after the SDK's four base
    /// keys (AUTHENTICATION/MASTER, AUTHENTICATION/CRITICAL,
    /// AUTHENTICATION/HIGH, TRANSFER/CRITICAL).
    static func registrationSpecifications(firstKeyId: UInt32) -> [KeySpecification] {
        [
            KeySpecification(keyId: firstKeyId, purpose: .encryption),
            KeySpecification(keyId: firstKeyId + 1, purpose: .decryption),
        ]
    }

    /// Match Platform's recipient-key selector: prefer DECRYPTION,
    /// but accept ENCRYPTION for the established mobile cohort.
    ///
    /// `nil` means the key query was unavailable and callers must
    /// leave the identity actionable so the send path can surface the
    /// authoritative error.
    static func recipientEligibility(from keys: [[String: Any]]?) -> Bool? {
        guard let keys else { return nil }
        return keys.contains { key in
            guard (key["type"] as? Int) == Int(KeyType.ecdsaSecp256k1.rawValue) else {
                return false
            }
            guard key["disabledAt"] == nil || key["disabledAt"] is NSNull else {
                return false
            }
            guard let purpose = key["purpose"] as? Int else { return false }
            return purpose == Int(KeyPurpose.decryption.rawValue)
                || purpose == Int(KeyPurpose.encryption.rawValue)
        }
    }

    /// Derive, validate, and Keychain-persist the requested DashPay
    /// keys, then return the public rows for IdentityCreate or
    /// IdentityUpdate.
    ///
    /// `identityIdString` is empty before IdentityCreate. The SDK
    /// persister replaces that placeholder once the identity lands;
    /// update flows pass the existing identity's base58 id.
    @MainActor
    static func deriveAndPersist(
        wallet: ManagedPlatformWallet,
        identityIdString: String,
        identityIndex: UInt32,
        specifications: [KeySpecification],
        network: Network
    ) throws -> [ManagedPlatformWallet.IdentityPubkey] {
        var rows: [ManagedPlatformWallet.IdentityPubkey] = []
        rows.reserveCapacity(specifications.count)

        for specification in specifications {
            let preview = try wallet.deriveIdentityAuthKeyAtSlot(
                identityIndex: identityIndex,
                keyId: specification.keyId,
                network: network)

            guard KeyValidation.validatePrivateKeyForPublicKey(
                privateKeyHex: preview.privateKeyData.toHexString(),
                publicKeyHex: preview.publicKeyHex,
                keyType: specification.keyType,
                network: network)
            else {
                throw KeyError.derivationMismatch
            }

            let pubKeyHashHex = SwiftDashSDK.KeychainManager.computePublicKeyHashHex(
                preview.publicKeyData)
            let metadata = IdentityPrivateKeyMetadata(
                identityId: identityIdString,
                keyId: specification.keyId,
                walletId: wallet.walletId.toHexString(),
                identityIndex: identityIndex,
                keyIndex: specification.keyId,
                derivationPath: preview.derivationPath,
                publicKey: preview.publicKeyHex,
                publicKeyHash: pubKeyHashHex,
                keyType: specification.keyType.rawValue,
                purpose: specification.purpose.rawValue,
                securityLevel: specification.securityLevel.rawValue)
            guard KeychainManager.shared.storeIdentityPrivateKey(
                preview.privateKeyData,
                derivationPath: preview.derivationPath,
                metadata: metadata) != nil
            else {
                throw KeyError.keychainWriteFailed
            }

            rows.append(ManagedPlatformWallet.IdentityPubkey(
                keyId: specification.keyId,
                keyType: specification.keyType,
                purpose: specification.purpose,
                securityLevel: specification.securityLevel,
                pubkeyBytes: preview.publicKeyData,
                contractBounds: specification.contractBounds))
        }

        return rows
    }
}

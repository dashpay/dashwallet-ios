import CryptoKit
import Foundation

enum LoginKeyDerivation {
    static let defaultKeyIndex = 0

    private enum DerivationError: LocalizedError {
        case invalidChainKeyLength
        case invalidIdentityIdLength
        case invalidAppContractIdLength

        var errorDescription: String? {
            switch self {
            case .invalidChainKeyLength:
                "The identity auth-chain private key must be exactly 32 bytes."
            case .invalidIdentityIdLength:
                "DashConnect identity IDs must be exactly 32 bytes."
            case .invalidAppContractIdLength:
                "DashConnect app contract IDs must be exactly 32 bytes."
            }
        }
    }

    private static let loginKeyInfoPrefix = Data("dash:login-key:v1".utf8)
    private static let keyLength = 32

    /// The returned Data is owned by the caller to clear.
    static func deriveLoginKey(chainKeyPrivateBytes: Data,
                               identityId: Data,
                               appContractId: Data) throws -> Data {
        guard chainKeyPrivateBytes.count == keyLength else {
            throw DerivationError.invalidChainKeyLength
        }
        guard identityId.count == keyLength else {
            throw DerivationError.invalidIdentityIdLength
        }
        guard appContractId.count == keyLength else {
            throw DerivationError.invalidAppContractIdLength
        }

        var info = loginKeyInfoPrefix
        info.append(appContractId)
        // The HKDF info is protocol metadata (`dash:login-key:v1` + contract ID), not a
        // secret. The returned login key remains caller-owned to clear.
        return try deriveHKDFKey(
            inputKeyMaterial: chainKeyPrivateBytes,
            salt: identityId,
            info: info,
            outputByteCount: keyLength
        )
    }

    private static func deriveHKDFKey(inputKeyMaterial: Data,
                                      salt: Data,
                                      info: Data,
                                      outputByteCount: Int) throws -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: salt,
            info: info,
            outputByteCount: outputByteCount
        )

        return key.withUnsafeBytes { bytes in
            Data(bytes)
        }
    }
}

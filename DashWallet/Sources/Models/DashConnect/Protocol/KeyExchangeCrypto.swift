import CryptoKit
import Foundation
import Security
import SwiftDashSDK

enum KeyExchangeCrypto {
    private enum CryptoError: LocalizedError {
        case invalidSharedXLength
        case invalidLoginKeyLength
        case invalidIdentityIdLength
        case invalidNonceLength
        case invalidPayloadLength
        case randomNonceGenerationFailed(OSStatus)
        case invalidEncryptedPayload
        case hash160Failed

        var errorDescription: String? {
            switch self {
            case .invalidSharedXLength:
                "The ECDH shared X coordinate must be exactly 32 bytes."
            case .invalidLoginKeyLength:
                "DashConnect login keys must be exactly 32 bytes."
            case .invalidIdentityIdLength:
                "DashConnect identity IDs must be exactly 32 bytes."
            case .invalidNonceLength:
                "DashConnect AES-GCM nonces must be exactly 12 bytes."
            case .invalidPayloadLength:
                "DashConnect encrypted login-key payloads must be exactly 60 bytes."
            case .randomNonceGenerationFailed(let status):
                "Failed to generate a random AES-GCM nonce (\(status))."
            case .invalidEncryptedPayload:
                "Failed to assemble the AES-GCM encrypted login-key payload."
            case .hash160Failed:
                "Failed to compute hash160 via platform_wallet_hash160."
            }
        }
    }

    private static let hash160Length = 20
    private static let aesKeyLength = 32
    private static let loginKeyLength = 32
    private static let nonceLength = 12
    private static let encryptedPayloadLength = 60
    private static let keyExchangeSalt = Data("dash:key-exchange:v1".utf8)
    private static let authInfo = Data("auth".utf8)
    private static let encryptionInfo = Data("encryption".utf8)

    /// RIPEMD160(SHA256(data)) using the shared Rust FFI helper.
    ///
    /// This deliberately duplicates the direct `platform_wallet_hash160` call pattern from
    /// `KeychainManager.computePublicKeyHashHex` so we reuse the same primitive without
    /// adding a Swift-side RIPEMD-160 implementation. Empty input or FFI failure returns
    /// an empty Data sentinel, mirroring the existing KeychainManager helper.
    static func hash160(_ data: Data) -> Data {
        guard !data.isEmpty else {
            return Data()
        }

        var out = [UInt8](repeating: 0, count: hash160Length)
        let rc: Int32 = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return -1
            }

            return out.withUnsafeMutableBufferPointer { buffer -> Int32 in
                guard let outBase = buffer.baseAddress else {
                    return -1
                }

                return platform_wallet_hash160(base, UInt(data.count), outBase)
            }
        }

        guard rc == 0 else {
            zero(&out)
            return Data()
        }

        let result = Data(out)
        zero(&out)
        return result
    }

    /// The returned Data is owned by the caller to clear.
    static func deriveAesKey(sharedX: Data) throws -> Data {
        try requireLength(sharedX, expected: aesKeyLength, error: CryptoError.invalidSharedXLength)
        return try deriveHKDFKey(
            inputKeyMaterial: sharedX,
            salt: keyExchangeSalt,
            info: Data(),
            outputByteCount: aesKeyLength
        )
    }

    /// The returned Data is owned by the caller to clear.
    static func encryptLoginKey(_ loginKey: Data,
                                walletEphemeralPriv: Data,
                                appEphemeralPub: Data) throws -> Data {
        var nonceBytes = [UInt8](repeating: 0, count: nonceLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
        guard status == errSecSuccess else {
            zero(&nonceBytes)
            throw CryptoError.randomNonceGenerationFailed(status)
        }

        let nonce = Data(nonceBytes)
        zero(&nonceBytes)
        return try encryptLoginKey(
            loginKey,
            walletEphemeralPriv: walletEphemeralPriv,
            appEphemeralPub: appEphemeralPub,
            nonce: nonce
        )
    }

    /// Fixed-nonce variant. Tests only — never call from the login flow.
    ///
    /// The returned Data is owned by the caller to clear.
    static func encryptLoginKey(_ loginKey: Data,
                                walletEphemeralPriv: Data,
                                appEphemeralPub: Data,
                                nonce: Data) throws -> Data {
        try requireLength(loginKey, expected: loginKeyLength, error: CryptoError.invalidLoginKeyLength)
        try requireLength(nonce, expected: nonceLength, error: CryptoError.invalidNonceLength)

        let sharedX = try Secp256k1.ecdhSharedX(privateKey: walletEphemeralPriv, publicKey: appEphemeralPub)
        let aesKey = try deriveAesKey(sharedX: sharedX)
        let symmetricKey = SymmetricKey(data: aesKey)
        let sealedBox = try AES.GCM.seal(
            loginKey,
            using: symmetricKey,
            nonce: try AES.GCM.Nonce(data: nonce)
        )

        guard let combined = sealedBox.combined else {
            throw CryptoError.invalidEncryptedPayload
        }
        assert(combined.count == encryptedPayloadLength)
        guard combined.count == encryptedPayloadLength else {
            throw CryptoError.invalidPayloadLength
        }

        return combined
    }

    /// Tests only — this exists to verify the key-exchange round trip and is not used by
    /// the login flow. The returned Data is owned by the caller to clear.
    static func decryptLoginKey(_ payload: Data,
                                walletEphemeralPriv: Data,
                                appEphemeralPub: Data) throws -> Data {
        try requireLength(payload, expected: encryptedPayloadLength, error: CryptoError.invalidPayloadLength)

        let sharedX = try Secp256k1.ecdhSharedX(privateKey: walletEphemeralPriv, publicKey: appEphemeralPub)
        let aesKey = try deriveAesKey(sharedX: sharedX)
        let symmetricKey = SymmetricKey(data: aesKey)
        let sealedBox = try AES.GCM.SealedBox(combined: payload)
        let loginKey = try AES.GCM.open(sealedBox, using: symmetricKey)

        try requireLength(loginKey, expected: loginKeyLength, error: CryptoError.invalidLoginKeyLength)
        return loginKey
    }

    /// The returned Data is owned by the caller to clear.
    static func deriveAuthPrivateKey(loginKey: Data, identityId: Data) throws -> Data {
        try requireLength(loginKey, expected: loginKeyLength, error: CryptoError.invalidLoginKeyLength)
        try requireLength(identityId, expected: loginKeyLength, error: CryptoError.invalidIdentityIdLength)

        return try deriveHKDFKey(
            inputKeyMaterial: loginKey,
            salt: identityId,
            info: authInfo,
            outputByteCount: loginKeyLength
        )
    }

    /// The returned Data is owned by the caller to clear.
    static func deriveEncryptionPrivateKey(loginKey: Data, identityId: Data) throws -> Data {
        try requireLength(loginKey, expected: loginKeyLength, error: CryptoError.invalidLoginKeyLength)
        try requireLength(identityId, expected: loginKeyLength, error: CryptoError.invalidIdentityIdLength)

        return try deriveHKDFKey(
            inputKeyMaterial: loginKey,
            salt: identityId,
            info: encryptionInfo,
            outputByteCount: loginKeyLength
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

    private static func requireLength(_ data: Data,
                                      expected: Int,
                                      error: Error) throws {
        guard data.count == expected else {
            throw error
        }
    }

    private static func zero(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            baseAddress.initializeMemory(as: UInt8.self, repeating: 0, count: buffer.count)
        }
    }
}

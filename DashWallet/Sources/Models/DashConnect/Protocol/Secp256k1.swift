import Foundation
import SwiftDashSDK

/// The secp256k1 operations DashConnect's key exchange needs. Deliberately minimal —
/// this is not a general-purpose curve wrapper.
enum Secp256k1 {
    private enum BackendError: Int, LocalizedError {
        case invalidPrivateKeyLength = 1
        case invalidPrivateKey
        case invalidPublicKeyLength
        case invalidPublicKey
        case pointAtInfinity
        case backendUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidPrivateKeyLength:
                "secp256k1 private keys must be exactly 32 bytes."
            case .invalidPrivateKey:
                "The provided private key is not a valid secp256k1 scalar."
            case .invalidPublicKeyLength:
                "Compressed secp256k1 public keys must be exactly 33 bytes."
            case .invalidPublicKey:
                "The provided compressed point is not a valid secp256k1 public key."
            case .pointAtInfinity:
                "ECDH produced the point at infinity."
            case .backendUnavailable:
                "Failed to initialize the secp256k1 backend."
            }
        }
    }

    /// True when `pubKey` is a well-formed 33-byte compressed point that lies on the
    /// curve. The QR is untrusted input, so this gates every ECDH call.
    static func isValidCompressedPoint(_ pubKey: Data) -> Bool {
        do {
            let publicKeyBytes = try validatedCompressedPublicKeyBytes(pubKey)
            return Secp256k1Primitives.isValidCompressedPoint(Data(publicKeyBytes))
        } catch {
            return false
        }
    }

    /// The 33-byte compressed public key for a 32-byte private key.
    static func compressedPublicKey(privateKey: Data) throws -> Data {
        var privateKeyBytes = try validatedPrivateKeyBytes(privateKey)
        defer { zero(&privateKeyBytes) }
        do {
            return try Secp256k1Primitives.compressedPublicKey(privateKey: Data(privateKeyBytes))
        } catch let error as PlatformWalletError {
            switch error {
            case .invalidParameter:
                throw BackendError.invalidPrivateKey
            default:
                throw BackendError.backendUnavailable
            }
        } catch {
            throw BackendError.backendUnavailable
        }
    }

    /// The 32-byte big-endian X coordinate of `privateKey * publicKey`, left-padded.
    ///
    /// This is the ECDH shared secret the protocol feeds to HKDF. It is the raw affine X
    /// of the product point — NOT hashed, and NOT the default hashed ECDH output that
    /// applies SHA256 to the compressed point. Using the hashed variant would silently
    /// produce a shared secret the DApp cannot reproduce.
    static func ecdhSharedX(privateKey: Data, publicKey: Data) throws -> Data {
        var privateKeyBytes = try validatedPrivateKeyBytes(privateKey)
        defer { zero(&privateKeyBytes) }

        let publicKeyBytes = try validatedCompressedPublicKeyBytes(publicKey)
        guard Secp256k1Primitives.isValidCompressedPoint(Data(publicKeyBytes)) else {
            throw BackendError.invalidPublicKey
        }

        do {
            return try Secp256k1Primitives.ecdhSharedX(
                privateKey: Data(privateKeyBytes),
                publicKey: Data(publicKeyBytes)
            )
        } catch let error as PlatformWalletError {
            switch error {
            case .invalidParameter:
                throw BackendError.invalidPrivateKey
            case .walletOperation:
                throw BackendError.pointAtInfinity
            default:
                throw BackendError.backendUnavailable
            }
        } catch {
            throw BackendError.backendUnavailable
        }
    }

    private static func validatedPrivateKeyBytes(_ privateKey: Data) throws -> [UInt8] {
        guard privateKey.count == 32 else {
            throw BackendError.invalidPrivateKeyLength
        }

        return [UInt8](privateKey)
    }

    private static func validatedCompressedPublicKeyBytes(_ publicKey: Data) throws -> [UInt8] {
        guard publicKey.count == 33 else {
            throw BackendError.invalidPublicKeyLength
        }

        let bytes = [UInt8](publicKey)
        guard bytes[0] == 0x02 || bytes[0] == 0x03 else {
            throw BackendError.invalidPublicKey
        }

        return bytes
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

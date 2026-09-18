//
//  BrowserLoginBleProtocol.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreBluetooth
import Foundation

/// The Bluetooth LE framing of a DashConnect login: the same `dash-key:`
/// request and the same encrypted login-key envelope as the QR flow, carried
/// over a GATT service instead of a QR code and a `loginKeyResponse` document.
///
/// The browser is the GATT central, the wallet the peripheral. The wallet
/// advertises `serviceUUID` with three characteristics:
///
///   - `requestCharacteristicUUID` (write): the browser writes one request.
///   - `statusCharacteristicUUID` (read + notify): one `Status` byte.
///   - `responseCharacteristicUUID` (read): the `Response` once the status is
///     `ready`, empty before that.
///
/// The cryptography is `KeyExchangeCrypto`'s, untouched. What differs from the
/// QR flow is the key the wallet registers: instead of the deterministic
/// per-app login key, it draws a random one and registers its authentication
/// key with a spend budget and an expiry (protocol 14 key limits), so the
/// browser's key is bounded and a re-share mints a fresh key.
enum BrowserLoginBleProtocol {
    static let version: UInt8 = 1

    static let serviceUUIDString = "8f9a3e10-5c2b-4d6e-9f1a-2b3c4d5e6f01"
    static let requestCharacteristicUUIDString = "8f9a3e10-5c2b-4d6e-9f1a-2b3c4d5e6f02"
    static let statusCharacteristicUUIDString = "8f9a3e10-5c2b-4d6e-9f1a-2b3c4d5e6f03"
    static let responseCharacteristicUUIDString = "8f9a3e10-5c2b-4d6e-9f1a-2b3c4d5e6f04"

    // `CBUUID` is not Sendable, so the constants above are the strings and
    // these build a fresh value per use.
    static var serviceUUID: CBUUID { CBUUID(string: serviceUUIDString) }
    static var requestCharacteristicUUID: CBUUID { CBUUID(string: requestCharacteristicUUIDString) }
    static var statusCharacteristicUUID: CBUUID { CBUUID(string: statusCharacteristicUUIDString) }
    static var responseCharacteristicUUID: CBUUID { CBUUID(string: responseCharacteristicUUIDString) }

    /// Longest app label the request may carry, in UTF-8 bytes. Matches the
    /// `dash-key:` URI limit.
    static let maxLabelLength = 64

    /// Value of the status characteristic.
    enum Status: UInt8 {
        /// Advertising, no request received yet.
        case idle = 0
        /// A request arrived and the user is being asked to confirm it.
        case awaitingConfirmation = 1
        /// The user confirmed; the key is being registered on Platform.
        case registering = 2
        /// The response characteristic holds the encrypted login key.
        case ready = 3
        /// The user declined the request.
        case rejected = 4
        /// The request was malformed, for another network, or the
        /// registration failed.
        case failed = 5
    }

    enum ProtocolError: LocalizedError, Equatable {
        case truncatedRequest
        case unsupportedVersion(UInt8)
        case unknownNetwork(UInt8)
        case invalidEphemeralPublicKey
        case labelNotUTF8
        case labelTooLong(Int)
        case invalidFieldLength(String)

        var errorDescription: String? {
            switch self {
            case .truncatedRequest:
                return "The browser's request was shorter than the protocol requires."
            case .unsupportedVersion(let version):
                return "The browser spoke protocol version \(version); this wallet only speaks version \(BrowserLoginBleProtocol.version)."
            case .unknownNetwork(let tag):
                return "The browser asked for an unknown network (tag \(tag))."
            case .invalidEphemeralPublicKey:
                return "The browser's ephemeral public key is not a valid secp256k1 point."
            case .labelNotUTF8:
                return "The app label is not valid UTF-8."
            case .labelTooLong(let length):
                return "The app label is \(length) bytes; at most \(BrowserLoginBleProtocol.maxLabelLength) are allowed."
            case .invalidFieldLength(let field):
                return "The \(field) field has the wrong length."
            }
        }
    }

    // MARK: - Request

    /// Decode what the browser writes to the request characteristic:
    ///
    ///     version(1) || network(1) || appEphemeralPubKey(33) || contractId(32) || labelLen(1) || label(labelLen)
    ///
    /// That is the `dash-key:` request body with the URI's `n=` network letter
    /// spliced in after the version, so the wallet can refuse a request for
    /// another chain before showing anything.
    static func parseRequest(_ bytes: Data) throws -> DashKeyRequest {
        let minimumLength = 1 + 1 + 33 + 32 + 1
        guard bytes.count >= minimumLength else {
            throw ProtocolError.truncatedRequest
        }
        var cursor = bytes.startIndex
        let version = bytes[cursor]
        cursor += 1
        guard version == Self.version else {
            throw ProtocolError.unsupportedVersion(version)
        }
        let networkLetter = String(Character(Unicode.Scalar(bytes[cursor])))
        guard let network = DashConnectNetwork(rawValue: networkLetter) else {
            throw ProtocolError.unknownNetwork(bytes[cursor])
        }
        cursor += 1
        let appEphemeralPubKey = Data(bytes[cursor ..< cursor + 33])
        cursor += 33
        guard Secp256k1.isValidCompressedPoint(appEphemeralPubKey) else {
            throw ProtocolError.invalidEphemeralPublicKey
        }
        let contractId = Data(bytes[cursor ..< cursor + 32])
        cursor += 32
        let labelLength = Int(bytes[cursor])
        cursor += 1
        guard labelLength <= maxLabelLength else {
            throw ProtocolError.labelTooLong(labelLength)
        }
        guard bytes.endIndex - cursor >= labelLength else {
            throw ProtocolError.truncatedRequest
        }
        guard let label = String(data: bytes[cursor ..< cursor + labelLength], encoding: .utf8) else {
            throw ProtocolError.labelNotUTF8
        }
        return DashKeyRequest(
            appEphemeralPubKey: appEphemeralPubKey,
            contractId: contractId,
            label: label,
            network: network
        )
    }

    /// The inverse of `parseRequest`, for tests and previews.
    static func serializeRequest(_ request: DashKeyRequest) throws -> Data {
        let labelBytes = Data(request.label.utf8)
        guard labelBytes.count <= maxLabelLength else {
            throw ProtocolError.labelTooLong(labelBytes.count)
        }
        guard request.appEphemeralPubKey.count == 33 else {
            throw ProtocolError.invalidFieldLength("appEphemeralPubKey")
        }
        guard request.contractId.count == 32 else {
            throw ProtocolError.invalidFieldLength("contractId")
        }
        var out = Data()
        out.append(version)
        out.append(contentsOf: request.network.rawValue.utf8)
        out.append(request.appEphemeralPubKey)
        out.append(request.contractId)
        out.append(UInt8(labelBytes.count))
        out.append(labelBytes)
        return out
    }

    /// Six decimal digits both sides derive from the browser's ephemeral
    /// public key. The browser shows them, the user checks the wallet shows
    /// the same ones before confirming, which rules out a third radio in
    /// range answering the browser's request.
    static func pairingCode(for appEphemeralPubKey: Data) throws -> String {
        let digest = try KeyExchangeCrypto.hash160(appEphemeralPubKey)
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06d", value % 1_000_000)
    }

    // MARK: - Response

    /// What the wallet exposes on the response characteristic:
    ///
    ///     version(1) || identityId(32) || walletEphemeralPubKey(33) || encryptedPayload(60)
    ///     || keyId(4, big endian) || expiresAt(8, big endian, 0 = none) || totalBudget(8, big endian, 0 = none)
    struct Response: Equatable {
        static let length = 1 + 32 + 33 + 60 + 4 + 8 + 8

        let identityId: Data
        let walletEphemeralPublicKey: Data
        /// nonce(12) || ciphertext(32) || tag(16), from `KeyExchangeCrypto.encryptLoginKey`.
        let encryptedPayload: Data
        /// Id of the key the wallet registered on the identity.
        let keyId: UInt32
        /// Block time in milliseconds from which the key can no longer sign.
        let expiresAt: UInt64?
        /// Lifetime spend cap of the key in credits.
        let totalBudget: UInt64?

        func serialized() throws -> Data {
            guard identityId.count == 32 else { throw ProtocolError.invalidFieldLength("identityId") }
            guard walletEphemeralPublicKey.count == 33 else { throw ProtocolError.invalidFieldLength("walletEphemeralPublicKey") }
            guard encryptedPayload.count == 60 else { throw ProtocolError.invalidFieldLength("encryptedPayload") }
            var out = Data(capacity: Self.length)
            out.append(BrowserLoginBleProtocol.version)
            out.append(identityId)
            out.append(walletEphemeralPublicKey)
            out.append(encryptedPayload)
            out.append(bigEndian: keyId)
            out.append(bigEndian: expiresAt ?? 0)
            out.append(bigEndian: totalBudget ?? 0)
            return out
        }

        static func parse(_ bytes: Data) throws -> Response {
            guard bytes.count == length else { throw ProtocolError.truncatedRequest }
            var cursor = bytes.startIndex
            guard bytes[cursor] == BrowserLoginBleProtocol.version else {
                throw ProtocolError.unsupportedVersion(bytes[cursor])
            }
            cursor += 1
            let identityId = Data(bytes[cursor ..< cursor + 32])
            cursor += 32
            let walletEphemeralPublicKey = Data(bytes[cursor ..< cursor + 33])
            cursor += 33
            let encryptedPayload = Data(bytes[cursor ..< cursor + 60])
            cursor += 60
            let keyId = bytes[cursor ..< cursor + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            cursor += 4
            let expiresAt = bytes[cursor ..< cursor + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            cursor += 8
            let totalBudget = bytes[cursor ..< cursor + 8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return Response(
                identityId: identityId,
                walletEphemeralPublicKey: walletEphemeralPublicKey,
                encryptedPayload: encryptedPayload,
                keyId: keyId,
                expiresAt: expiresAt == 0 ? nil : expiresAt,
                totalBudget: totalBudget == 0 ? nil : totalBudget
            )
        }
    }
}

/// The limits the user chose for the browser's key.
struct BrowserLoginKeyLimits: Equatable {
    /// Lifetime spend cap in credits. Platform refuses a zero budget, so the
    /// UI only offers positive values.
    let totalBudget: UInt64
    /// How long the key stays valid from the moment it is registered.
    let lifetime: TimeInterval

    /// The expiry as Platform expects it: block time in milliseconds.
    func expiresAt(from now: Date) -> UInt64 {
        UInt64((now.timeIntervalSince1970 + lifetime) * 1000)
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func append(bigEndian value: UInt64) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
}

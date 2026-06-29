//
//  ScriptAddressCodec.swift
//  DashWallet
//
//  BIP70 payment-protocol — script ↔ address codec (Layer 4).
//
//  The SwiftDashSDK send primitive is address-only (`recipients: [(address, amount)]`), but
//  BIP70 `PaymentDetails.outputs` carry raw scriptPubKey bytes. This layer translates standard
//  output scripts → Dash addresses (so the SDK can build the tx) and runs in reverse for
//  `refund_to` (the wallet's own receive address → a P2PKH scriptPubKey).
//
//  Ports DashSync's `+[NSString bitcoinAddressWithScriptPubKey:forChain:]` and its
//  `base58check` helpers (none reachable from Swift without importing DashSync; SwiftDashSDK
//  exposes no general script↔address conversion). Only standard P2PKH/P2SH are supported —
//  anything else (OP_RETURN, multisig, bare P2PK, …) is rejected as `.nonStandardScript`.
//
//  Pure leaf: Foundation + CryptoKit (double-SHA256 for the Base58Check checksum) only. No
//  networking, no chain detection — the active network is decided at the L5/L6 boundary and
//  handed in as a `PaymentNetwork` token.
//

import Foundation
import CryptoKit

/// Foundation-only network token for the protocol core. Maps to the address version bytes.
/// (`DWEnvironment...currentChain.isMainnet()` is resolved into this at the L5/L6 boundary.)
enum PaymentNetwork {
    case mainnet
    case testnet
}

extension PaymentNetwork {
    /// P2PKH / pubkey-hash address version byte (`DASH_PUBKEY_ADDRESS{,_TEST}`).
    var pubkeyHashVersion: UInt8 { self == .mainnet ? 76 : 140 }
    /// P2SH / script-hash address version byte (`DASH_SCRIPT_ADDRESS{,_TEST}`).
    var scriptHashVersion: UInt8 { self == .mainnet ? 16 : 19 }
}

enum ScriptAddressCodec {

    // MARK: - Script → address

    /// scriptPubKey → Base58Check address. Returns `nil` for any non-P2PKH/P2SH script.
    static func address(forScript script: Data, network: PaymentNetwork) -> String? {
        let b = [UInt8](script)

        // P2PKH: OP_DUP OP_HASH160 PUSH20 <20> OP_EQUALVERIFY OP_CHECKSIG
        if b.count == 25, b[0] == 0x76, b[1] == 0xa9, b[2] == 0x14, b[23] == 0x88, b[24] == 0xac {
            return base58CheckEncode(version: network.pubkeyHashVersion, hash160: b[3 ..< 23])
        }
        // P2SH: OP_HASH160 PUSH20 <20> OP_EQUAL
        if b.count == 23, b[0] == 0xa9, b[1] == 0x14, b[22] == 0x87 {
            return base58CheckEncode(version: network.scriptHashVersion, hash160: b[2 ..< 22])
        }
        return nil
    }

    // MARK: - Address → script (refund_to)

    /// Base58Check address → P2PKH or P2SH scriptPubKey, chosen by the decoded version byte.
    /// Returns `nil` if the address can't be decoded or its version doesn't belong to `network`.
    static func scriptPubKey(forAddress address: String, network: PaymentNetwork) -> Data? {
        guard let decoded = base58CheckDecode(address), decoded.count == 21 else { return nil }
        let version = decoded[decoded.startIndex]
        let hash160 = Array(decoded[decoded.index(after: decoded.startIndex)...]) // 20 bytes

        if version == network.pubkeyHashVersion {
            return Data([0x76, 0xa9, 0x14] + hash160 + [0x88, 0xac])
        }
        if version == network.scriptHashVersion {
            return Data([0xa9, 0x14] + hash160 + [0x87])
        }
        return nil
    }

    // MARK: - Output resolution

    /// Map merchant outputs to ready-to-send SDK recipients, preserving order. Throws
    /// `.nonStandardScript` on the first non-P2PKH/P2SH script and `.malformedRequest` on an
    /// output with no concrete amount. The first bad output aborts the whole resolve — we
    /// never partially send.
    static func resolveOutputs(_ outputs: [PaymentOutput], network: PaymentNetwork) throws
        -> [(address: String, amount: UInt64)] {
        try outputs.map { output in
            guard let address = address(forScript: output.script, network: network) else {
                throw BIP70Error.nonStandardScript
            }
            guard let amount = output.amount else {
                throw BIP70Error.malformedRequest
            }
            return (address: address, amount: amount)
        }
    }

    // MARK: - Base58Check

    private static let base58Alphabet =
        Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    /// ASCII → base58 digit (or -1). Built once.
    private static let base58Reverse: [Int8] = {
        var map = [Int8](repeating: -1, count: 128)
        for (index, char) in base58Alphabet.enumerated() { map[Int(char)] = Int8(index) }
        return map
    }()

    private static func doubleSHA256(_ data: Data) -> Data {
        Data(SHA256.hash(data: Data(SHA256.hash(data: data))))
    }

    private static func base58CheckEncode<S: Sequence>(version: UInt8, hash160: S) -> String
        where S.Element == UInt8 {
        var payload = Data([version])
        payload.append(contentsOf: hash160)
        payload.append(doubleSHA256(payload).prefix(4))
        return base58Encode(payload)
    }

    private static func base58CheckDecode(_ string: String) -> Data? {
        guard let raw = base58Decode(string), raw.count >= 4 else { return nil }
        let payload = Data(raw.prefix(raw.count - 4))
        let checksum = Data(raw.suffix(4))
        guard doubleSHA256(payload).prefix(4) == checksum else { return nil }
        return payload
    }

    /// Big-integer base conversion 256 → 58 (mirrors `NSString+Bitcoin.m base58WithData:`).
    private static func base58Encode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var leadingZeros = 0
        while leadingZeros < bytes.count, bytes[leadingZeros] == 0 { leadingZeros += 1 }

        let size = (bytes.count - leadingZeros) * 138 / 100 + 1 // log(256)/log(58), rounded up
        var buffer = [UInt8](repeating: 0, count: size)
        for i in leadingZeros ..< bytes.count {
            var carry = Int(bytes[i])
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 256 * Int(buffer[j])
                buffer[j] = UInt8(carry % 58)
                carry /= 58
            }
        }

        var start = 0
        while start < size, buffer[start] == 0 { start += 1 }

        var result = [UInt8]()
        result.reserveCapacity(leadingZeros + size - start)
        result.append(contentsOf: repeatElement(base58Alphabet[0], count: leadingZeros))
        for i in start ..< size { result.append(base58Alphabet[Int(buffer[i])]) }
        return String(decoding: result, as: UTF8.self)
    }

    /// Inverse of `base58Encode`; returns `nil` on any non-alphabet character.
    private static func base58Decode(_ string: String) -> Data? {
        let input = Array(string.utf8)
        var leadingZeros = 0
        while leadingZeros < input.count, input[leadingZeros] == base58Alphabet[0] { leadingZeros += 1 }

        let size = input.count * 733 / 1000 + 1 // log(58)/log(256), rounded up
        var buffer = [UInt8](repeating: 0, count: size)
        for i in leadingZeros ..< input.count {
            let char = input[i]
            guard char < 128 else { return nil }
            let digit = base58Reverse[Int(char)]
            guard digit >= 0 else { return nil }
            var carry = Int(digit)
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 58 * Int(buffer[j])
                buffer[j] = UInt8(carry & 0xff)
                carry >>= 8
            }
        }

        var start = 0
        while start < size, buffer[start] == 0 { start += 1 }

        var result = [UInt8](repeating: 0, count: leadingZeros)
        result.append(contentsOf: buffer[start...])
        return Data(result)
    }
}

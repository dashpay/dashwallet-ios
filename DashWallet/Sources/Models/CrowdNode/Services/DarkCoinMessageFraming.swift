//
//  DarkCoinMessageFraming.swift
//  DashWallet
//
//  Dash "signed message" framing — the byte prefix Dash Core's
//  `signmessage`/`verifymessage` (and the CrowdNode API) hash before
//  signing:
//
//      compactSize(len(magic)) ‖ magic ‖ compactSize(len(msg)) ‖ msg
//
//  with magic = "DarkCoin Signed Message:\n" (25 bytes, so the frame
//  always opens with 0x19). Ports DashSync's `-[NSString magicDigest]`
//  minus the double-SHA256 — SwiftDashSDK's signer FFI
//  (`RawKeySigner.sign`) hashes internally, so callers pass these framed
//  bytes whole, never a digest.
//
//  The length prefixes are Bitcoin CompactSize, NOT the protobuf LEB128
//  varint in `ProtoWriter.appendVarInt` (they diverge from value 128 up)
//  — don't swap one for the other.
//
//  Pure leaf: Foundation only (harness-compilable).
//

import Foundation

enum DarkCoinMessage {
    static let magic = "DarkCoin Signed Message:\n"

    /// The framed bytes whose SHA256d is the message digest. UTF-8 lengths,
    /// matching DashSync's `appendString:` (UTF-8) framing.
    static func framed(_ message: String) -> Data {
        var data = Data()
        appendCompactSizeString(magic, to: &data)
        appendCompactSizeString(message, to: &data)
        return data
    }

    private static func appendCompactSizeString(_ string: String, to data: inout Data) {
        let bytes = Data(string.utf8)
        appendCompactSize(UInt64(bytes.count), to: &data)
        data.append(bytes)
    }

    /// Bitcoin CompactSize: <0xFD → 1 byte; ≤0xFFFF → 0xFD + uint16 LE;
    /// ≤0xFFFFFFFF → 0xFE + uint32 LE; else 0xFF + uint64 LE.
    private static func appendCompactSize(_ value: UInt64, to data: inout Data) {
        switch value {
        case ..<0xfd:
            data.append(UInt8(value))
        case ...UInt64(UInt16.max):
            data.append(0xfd)
            appendLittleEndian(UInt16(value), to: &data)
        case ...UInt64(UInt32.max):
            data.append(0xfe)
            appendLittleEndian(UInt32(value), to: &data)
        default:
            data.append(0xff)
            appendLittleEndian(value, to: &data)
        }
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}

//
//  PaymentProtocolWireFormat.swift
//  DashWallet
//
//  BIP70 payment-protocol — protobuf wire format (Layer 1, pure Foundation).
//
//  A minimal protobuf reader/writer covering only the two wire types BIP70 uses:
//  varint (0) and length-delimited (2). Ported 1:1 from DashSync's hand-rolled
//  `NSData(ProtoBuf)` / `NSMutableData(ProtoBuf)` categories so the byte layout is
//  identical (this matters for byte-exact signature verification — see
//  `PaymentRequestVerifier`). No third-party protobuf dependency.
//
//  This file must stay pure: Foundation only, no I/O, no crypto, no SDK types.
//

import Foundation

/// protobuf wire types (only the two BIP70 uses are handled; 64/32-bit are skipped).
enum ProtoWireType: Int {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

/// Sequential reader over a protobuf-encoded buffer. Mirrors the loose decoding of
/// DashSync's `protoBufVarIntAtOffset:` (a truncated varint yields 0; an out-of-range
/// length yields nil while still advancing the offset).
struct ProtoReader {
    private let bytes: [UInt8]
    private(set) var offset: Int = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var isAtEnd: Bool { offset >= bytes.count }

    /// Reads a base-128 varint. Returns 0 if the buffer ends mid-varint (matches the
    /// reference `(b & 0x80) ? 0 : varInt`).
    mutating func readVarInt() -> UInt64 {
        var result: UInt64 = 0
        var i = 0
        var b: UInt8 = 0x80
        while (b & 0x80) != 0 && offset < bytes.count {
            b = bytes[offset]
            offset += 1
            let shift = 7 * i
            if shift < 64 { result &+= UInt64(b & 0x7f) << shift }
            i += 1
        }
        return (b & 0x80) != 0 ? 0 : result
    }

    /// Reads a length-delimited chunk. Returns nil and consumes the rest of the buffer when the
    /// declared length runs past the end (a truncated or hostile length, including one exceeding
    /// Int.max). The length stays in UInt64 and is bounds-checked before any narrowing, so a
    /// wire-controlled value can never trap (Int(UInt64) overflow) or slice out of range.
    mutating func readLengthDelimited() -> Data? {
        let len = readVarInt()
        let remaining = UInt64(bytes.count - offset) // offset <= bytes.count here, so >= 0
        guard len <= remaining else {
            offset = bytes.count // overrun → end the decode loop (matches the reference)
            return nil
        }
        let count = Int(len) // len <= remaining <= bytes.count, safe to narrow
        let chunk = Data(bytes[offset ..< offset + count])
        offset += count
        return chunk
    }

    /// One decoded field: its number, plus either a varint or a length-delimited payload.
    /// 64-bit / 32-bit fields are skipped (unused by BIP70). Returns nil at end of buffer.
    mutating func readField() -> (field: Int, varint: UInt64?, data: Data?)? {
        guard !isAtEnd else { return nil }
        let key = readVarInt()
        let field = Int(key >> 3) // >> 3 caps the value at 2^61-1, always fits in Int
        switch ProtoWireType(rawValue: Int(key & 0x07)) { // 0...7, always fits
        case .varint:
            return (field, readVarInt(), nil)
        case .lengthDelimited:
            return (field, nil, readLengthDelimited())
        case .fixed64:
            offset += 8
            return (field, nil, nil)
        case .fixed32:
            offset += 4
            return (field, nil, nil)
        case .none:
            return (field, nil, nil)
        }
    }
}

/// Accumulating writer. Field order is the caller's responsibility — BIP70 messages are
/// always written in ascending field number to stay byte-exact with the reference.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func appendVarInt(_ value: UInt64) {
        var i = value
        repeat {
            var b = UInt8(i & 0x7f)
            i >>= 7
            if i > 0 { b |= 0x80 }
            data.append(b)
        } while i > 0
    }

    mutating func appendLengthDelimited(_ payload: Data) {
        appendVarInt(UInt64(payload.count))
        data.append(payload)
    }

    /// varint field (wire type 0).
    mutating func append(key: Int, varInt value: UInt64) {
        appendVarInt(UInt64(key << 3) | UInt64(ProtoWireType.varint.rawValue))
        appendVarInt(value)
    }

    /// length-delimited field (wire type 2) — used for bytes, strings and embedded messages.
    /// Writing an empty `Data` still emits the field header + zero length (e.g. an empty
    /// signature emits `2a 00`), which the verification re-encode relies on.
    mutating func append(key: Int, data payload: Data) {
        appendVarInt(UInt64(key << 3) | UInt64(ProtoWireType.lengthDelimited.rawValue))
        appendLengthDelimited(payload)
    }

    mutating func append(key: Int, string value: String) {
        append(key: key, data: Data(value.utf8))
    }
}

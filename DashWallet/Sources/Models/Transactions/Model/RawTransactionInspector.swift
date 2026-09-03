//
//  RawTransactionInspector.swift
//  DashWallet
//

import Foundation
import SwiftData
import SwiftDashSDK

// MARK: - RawTransactionDetails

/// Everything the transaction inspector shows for one transaction,
/// consensus-decoded from the persisted raw bytes (display-only — nothing
/// here feeds signing or validation). Structural fields come from the
/// app-side parser below; addresses render via `ScriptAddressCodec` (outputs)
/// and the SDK's `TransactionDecoder` (best-effort input sender addresses);
/// amounts for spent inputs come from the wallet's own TXO rows when the
/// input is ours.
struct RawTransactionDetails {
    struct Input {
        let index: Int
        /// Explorer-style (reversed) hex of the spent outpoint's txid.
        let prevTxidDisplayHex: String
        let prevVout: UInt32
        let scriptSig: Data
        let sequence: UInt32
        /// Best-effort sender address recovered from a P2PKH scriptSig.
        /// Unauthenticated — display only (see `DecodedTransaction.Input`).
        let address: String?
        /// Value of the spent outpoint when it is one of the wallet's own
        /// TXOs; unknown (nil) for external inputs — the raw tx doesn't
        /// carry input values.
        let amountDuffs: UInt64?
        /// True for a coinbase input (null outpoint).
        let isCoinbase: Bool
    }

    struct Output {
        enum Kind {
            case standard(address: String)
            /// OP_RETURN with the concatenated pushed data.
            case opReturn(data: Data)
            /// Any other non-standard script.
            case nonStandard
        }

        let index: Int
        let valueDuffs: UInt64
        let scriptPubKey: Data
        let kind: Kind
    }

    struct PayloadField {
        let label: String
        let value: String
    }

    let txidDisplayHex: String
    let version: UInt16
    let typeRaw: UInt16
    /// DIP-2 special-transaction name; nil for a classic (type 0) tx.
    let typeName: String?
    let sizeBytes: Int
    let lockTime: UInt32
    let inputs: [Input]
    let outputs: [Output]
    /// DIP-2 extra payload bytes; nil for classic transactions.
    let extraPayload: Data?
    /// Parsed fields for payload types the app understands (coinbase height,
    /// asset-lock credit outputs). Everything else shows as hex only —
    /// unknown data is never guessed at.
    let payloadFields: [PayloadField]
    let rawHex: String
    /// Fee the wallet recorded for this row, when known.
    let feeDuffs: UInt64?
    /// Mined height from the persisted row; nil while unmined.
    let blockHeight: UInt32?
}

// MARK: - RawTransactionInspector

/// Loads a transaction's raw bytes from the wallet's SwiftData store and
/// consensus-decodes them for the inspector UI.
enum RawTransactionInspector {

    /// Full details for the inspector screen. Main-actor: reads the host's
    /// main-context SwiftData rows.
    @MainActor
    static func load(txidWire: Data) -> RawTransactionDetails? {
        guard let row = fetchRow(txidWire: txidWire) else { return nil }
        return details(from: row)
    }

    /// Just the raw serialized transaction hex (for copy-to-pasteboard).
    @MainActor
    static func rawHex(txidWire: Data) -> String? {
        guard let row = fetchRow(txidWire: txidWire), !row.transactionData.isEmpty else { return nil }
        return row.transactionData.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func fetchRow(txidWire: Data) -> PersistentTransaction? {
        guard let container = SwiftDashSDKHost.shared.modelContainer else { return nil }
        var descriptor = FetchDescriptor<PersistentTransaction>(
            predicate: #Predicate { $0.txid == txidWire })
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }

    /// Value of a spent outpoint read from the parent transaction's own
    /// stored bytes. This is dashj's "connect the input to a known
    /// transaction" step: the wallet keeps whole transactions, so an input
    /// spending an output that is not ours — a counterparty paying us back
    /// with coins we sent them, say — still has a knowable value, and with it
    /// a computable fee. Nil when we don't hold the parent, which is the
    /// ordinary case for a payment from someone we've never paid.
    @MainActor
    private static func parentOutputValue(prevTxid: Data, vout: UInt32) -> UInt64? {
        guard let row = fetchRow(txidWire: prevTxid), !row.transactionData.isEmpty,
              let parsed = try? ParsedRawTransaction(data: row.transactionData),
              Int(vout) < parsed.outputs.count else { return nil }
        return parsed.outputs[Int(vout)].valueDuffs
    }

    @MainActor
    private static func details(from row: PersistentTransaction) -> RawTransactionDetails? {
        let data = row.transactionData
        guard !data.isEmpty, let parsed = try? ParsedRawTransaction(data: data) else { return nil }

        let network: PaymentNetwork = WalletEnvironment.isTestnet ? .testnet : .mainnet

        // Best-effort input sender addresses from the SDK's consensus decoder
        // (P2PKH scriptSig recovery). Optional — a decode failure only loses
        // the sender annotations, not the inspector.
        var decodedInputs: [DecodedTransaction.Input] = []
        if let sdkNetwork = SwiftDashSDKHost.shared.runningNetwork,
           let decoded = try? TransactionDecoder.decode(data, network: sdkNetwork) {
            decodedInputs = decoded.inputs
        }

        // Wallet-owned spent TXOs, keyed by outpoint — the first source of
        // input values (the raw tx carries none).
        var ownedByOutpoint: [Data: PersistentTxo] = [:]
        for txo in row.inputs {
            ownedByOutpoint[txo.outpoint] = txo
        }

        let inputs = parsed.inputs.enumerated().map { index, input -> RawTransactionDetails.Input in
            let outpoint = PersistentTxo.makeOutpoint(txid: input.prevTxid, vout: input.prevVout)
            let owned = ownedByOutpoint[outpoint]
            let decodedAddress = index < decodedInputs.count ? decodedInputs[index].address : nil
            let isCoinbase = input.prevTxid.allSatisfy { $0 == 0 } && input.prevVout == UInt32.max
            return RawTransactionDetails.Input(
                index: index,
                prevTxidDisplayHex: input.prevTxid.reversed().map { String(format: "%02x", $0) }.joined(),
                prevVout: input.prevVout,
                scriptSig: input.scriptSig,
                sequence: input.sequence,
                address: owned?.address.isEmpty == false ? owned?.address : decodedAddress,
                amountDuffs: owned?.amount
                    ?? Self.parentOutputValue(prevTxid: input.prevTxid, vout: input.prevVout),
                isCoinbase: isCoinbase)
        }

        let outputs = parsed.outputs.enumerated().map { index, output -> RawTransactionDetails.Output in
            let kind: RawTransactionDetails.Output.Kind
            if let opReturnData = Self.opReturnData(script: output.scriptPubKey) {
                kind = .opReturn(data: opReturnData)
            } else if let address = ScriptAddressCodec.address(forScript: output.scriptPubKey, network: network) {
                kind = .standard(address: address)
            } else {
                kind = .nonStandard
            }
            return RawTransactionDetails.Output(
                index: index,
                valueDuffs: output.valueDuffs,
                scriptPubKey: output.scriptPubKey,
                kind: kind)
        }

        return RawTransactionDetails(
            txidDisplayHex: row.txid.reversed().map { String(format: "%02x", $0) }.joined(),
            version: parsed.version,
            typeRaw: parsed.type,
            typeName: Self.specialTypeName(parsed.type),
            sizeBytes: data.count,
            lockTime: parsed.lockTime,
            inputs: inputs,
            outputs: outputs,
            extraPayload: parsed.extraPayload,
            payloadFields: Self.parsePayloadFields(type: parsed.type, payload: parsed.extraPayload, network: network),
            rawHex: data.map { String(format: "%02x", $0) }.joined(),
            feeDuffs: row.fee,
            blockHeight: row.blockHeight > 0 ? row.blockHeight : nil)
    }

    // MARK: - Script helpers

    /// The concatenated data pushes of an OP_RETURN script, or nil when the
    /// script isn't OP_RETURN-shaped.
    static func opReturnData(script: Data) -> Data? {
        let bytes = [UInt8](script)
        guard bytes.first == 0x6a else { return nil }
        var data = Data()
        var i = 1
        while i < bytes.count {
            let op = bytes[i]
            i += 1
            let length: Int
            switch op {
            case 0x01...0x4b:
                length = Int(op)
            case 0x4c: // OP_PUSHDATA1
                guard i < bytes.count else { return data }
                length = Int(bytes[i]); i += 1
            case 0x4d: // OP_PUSHDATA2
                guard i + 1 < bytes.count else { return data }
                length = Int(bytes[i]) | (Int(bytes[i + 1]) << 8); i += 2
            case 0x00: // OP_0 pushes empty
                continue
            default:
                // Non-push opcode after OP_RETURN — stop collecting.
                return data
            }
            guard i + length <= bytes.count else { return data }
            data.append(contentsOf: bytes[i ..< i + length])
            i += length
        }
        return data
    }

    // MARK: - Special transaction payloads

    /// One credit output of an asset-lock payload: the locked value and the
    /// destination scriptPubKey it credits on Platform.
    struct AssetLockCreditOutput {
        let valueDuffs: UInt64
        let script: Data
    }

    /// Consensus-decode the credit outputs of a DIP-2 asset-lock payload
    /// (u8 version, varint count, TxOuts). Nil when the bytes don't parse as
    /// that shape — callers must treat the lock as undecodable rather than
    /// substitute a guess. Shared by the inspector's field list and
    /// `ShieldedTxLookup`'s restore-time reconstruction.
    static func assetLockCreditOutputs(payload: Data) -> [AssetLockCreditOutput]? {
        var reader = ByteReader(payload)
        guard (try? reader.readUInt8()) != nil,
              let count = try? reader.readVarInt(),
              count > 0, count <= 32 else { return nil }
        var outputs: [AssetLockCreditOutput] = []
        for _ in 0 ..< count {
            guard let value = try? reader.readUInt64(),
                  let scriptLength = try? reader.readVarInt(),
                  let script = try? reader.readBytes(length: scriptLength) else { return nil }
            outputs.append(AssetLockCreditOutput(valueDuffs: value, script: script))
        }
        return outputs
    }

    /// The 20-byte pubkey hash of a P2PKH script, or nil for any other shape.
    static func p2pkhKeyHash(script: Data) -> Data? {
        let b = [UInt8](script)
        guard b.count == 25, b[0] == 0x76, b[1] == 0xa9, b[2] == 0x14, b[23] == 0x88, b[24] == 0xac else {
            return nil
        }
        return Data(b[3 ..< 23])
    }

    /// The 16 network-order bytes of a DIP-3 service address as text: an
    /// IPv4-mapped address renders as a dotted quad, anything else as IPv6
    /// groups.
    private static func ipText(_ bytes: Data) -> String {
        let octets = [UInt8](bytes)
        guard octets.count == 16 else {
            return octets.map { String(format: "%02x", $0) }.joined()
        }
        let isV4Mapped = octets[0..<10].allSatisfy { $0 == 0 }
            && octets[10] == 0xFF && octets[11] == 0xFF
        if isV4Mapped {
            return "\(octets[12]).\(octets[13]).\(octets[14]).\(octets[15])"
        }
        let groups = stride(from: 0, to: 16, by: 2).map { i in
            String(format: "%x", Int(octets[i]) << 8 | Int(octets[i + 1]))
        }
        return "[\(groups.joined(separator: ":"))]"
    }

    /// DIP-2 special transaction names, keyed by the tx `type` field.
    static func specialTypeName(_ type: UInt16) -> String? {
        switch type {
        case 0: return nil
        case 1: return "Provider Registration (ProRegTx)"
        case 2: return "Provider Update Service (ProUpServTx)"
        case 3: return "Provider Update Registrar (ProUpRegTx)"
        case 4: return "Provider Update Revocation (ProUpRevTx)"
        case 5: return "Coinbase (CbTx)"
        case 6: return "Quorum Commitment (QcTx)"
        case 7: return "Masternode Hard Fork Signal (MnHfTx)"
        case 8: return "Asset Lock"
        case 9: return "Asset Unlock"
        default: return String(format: NSLocalizedString("Unknown special type %d", comment: "Raw transaction inspector"), type)
        }
    }

    /// Parsed fields for the payload types the app understands. Anything the
    /// parser doesn't positively recognize contributes no fields — the UI
    /// falls back to the payload hex rather than showing guessed values.
    ///
    /// Internal: the unban preview renders the same fields for a ProUpServTx
    /// it has built but not yet broadcast.
    static func parsePayloadFields(type: UInt16, payload: Data?, network: PaymentNetwork) -> [RawTransactionDetails.PayloadField] {
        guard let payload, !payload.isEmpty else { return [] }
        var fields: [RawTransactionDetails.PayloadField] = []

        switch type {
        case 2: // ProUpServTx — see DIP-3. Field order matches dashcore's
                // `base_payload_data_encode`; the service port is
                // byte-swapped on the wire, the platform ports are not.
            var reader = ByteReader(payload)
            guard let version = try? reader.readUInt16() else { break }
            fields.append(.init(label: "Payload version", value: "\(version)"))

            var masternodeType: UInt16?
            if version >= 2 {
                masternodeType = try? reader.readUInt16()
                if let masternodeType {
                    fields.append(.init(
                        label: "Masternode type",
                        value: masternodeType == 1
                            ? NSLocalizedString("Evonode", comment: "")
                            : NSLocalizedString("Masternode", comment: "")))
                }
            }

            guard let proTxHash = try? reader.readBytes(32),
                  let ipBytes = try? reader.readBytes(16),
                  let portBytes = try? reader.readBytes(2) else { break }
            fields.append(.init(
                label: "proTxHash",
                value: proTxHash.reversed().map { String(format: "%02x", $0) }.joined()))
            let port = UInt16(portBytes[portBytes.startIndex]) << 8
                | UInt16(portBytes[portBytes.startIndex + 1])
            fields.append(.init(
                label: NSLocalizedString("Service", comment: "Masternodes"),
                value: "\(Self.ipText(ipBytes)):\(port)"))

            guard let scriptLength = try? reader.readVarInt(),
                  let script = try? reader.readBytes(Int(scriptLength)),
                  let inputsHash = try? reader.readBytes(32) else { break }
            fields.append(.init(
                label: NSLocalizedString("Operator payout", comment: "Masternode unban"),
                value: script.isEmpty
                    ? NSLocalizedString("None", comment: "Masternode unban")
                    : (ScriptAddressCodec.address(forScript: script, network: network)
                        ?? script.map { String(format: "%02x", $0) }.joined())))
            fields.append(.init(
                label: "Inputs hash",
                value: inputsHash.reversed().map { String(format: "%02x", $0) }.joined()))

            if version >= 2, masternodeType == 1 {
                if let nodeId = try? reader.readBytes(20),
                   let p2pPort = try? reader.readUInt16(),
                   let httpPort = try? reader.readUInt16() {
                    fields.append(.init(
                        label: NSLocalizedString("Platform Node ID", comment: ""),
                        value: nodeId.map { String(format: "%02x", $0) }.joined()))
                    fields.append(.init(label: "Platform P2P port", value: "\(p2pPort)"))
                    fields.append(.init(label: "Platform HTTP port", value: "\(httpPort)"))
                }
            }

            if let signature = try? reader.readBytes(96) {
                fields.append(.init(
                    label: NSLocalizedString("Operator signature (BLS)", comment: "Masternode unban"),
                    value: signature.map { String(format: "%02x", $0) }.joined()))
            }
        case 5: // CbTx: u16 version, u32 height, 32B merkle root MN list, …
            var reader = ByteReader(payload)
            if let version = try? reader.readUInt16(),
               let height = try? reader.readUInt32(),
               let mnRoot = try? reader.readBytes(32) {
                fields.append(.init(label: "Payload version", value: "\(version)"))
                fields.append(.init(label: "Block height", value: "\(height)"))
                fields.append(.init(label: "Masternode list merkle root", value: mnRoot.reversed().map { String(format: "%02x", $0) }.joined()))
                if version >= 2, let quorumRoot = try? reader.readBytes(32) {
                    fields.append(.init(label: "Quorums merkle root", value: quorumRoot.reversed().map { String(format: "%02x", $0) }.joined()))
                }
            }
        case 8: // Asset lock: u8 version, varint count, credit outputs (TxOuts).
            if let creditOutputs = assetLockCreditOutputs(payload: payload) {
                fields.append(.init(label: "Payload version", value: "\(payload[payload.startIndex])"))
                fields.append(.init(label: "Credit outputs", value: "\(creditOutputs.count)"))
                for (i, output) in creditOutputs.enumerated() {
                    let destination = ScriptAddressCodec.address(forScript: output.script, network: network)
                        ?? output.script.map { String(format: "%02x", $0) }.joined()
                    fields.append(.init(
                        label: String(format: "Credit output %d", i),
                        value: "\(output.valueDuffs.formattedDashAmountWithoutCurrencySymbol) → \(destination)"))
                }
            }
        default:
            break
        }
        return fields
    }
}

// MARK: - ParsedRawTransaction

/// Minimal consensus parser for the structural fields the SDK decoder does
/// not surface: version/type split, scriptSigs, sequences, locktime, and the
/// DIP-2 extra payload. Throws on malformed bytes (including short reads) —
/// the inspector shows an honest "can't decode" state instead of guessing.
struct ParsedRawTransaction {
    struct Input {
        let prevTxid: Data
        let prevVout: UInt32
        let scriptSig: Data
        let sequence: UInt32
    }

    struct Output {
        let valueDuffs: UInt64
        let scriptPubKey: Data
    }

    let version: UInt16
    /// DIP-2 type (upper 16 bits of the 4-byte version field).
    let type: UInt16
    let inputs: [Input]
    let outputs: [Output]
    let lockTime: UInt32
    let extraPayload: Data?

    init(data: Data) throws {
        var reader = ByteReader(data)

        let versionField = try reader.readUInt32()
        version = UInt16(versionField & 0xFFFF)
        type = UInt16(versionField >> 16)

        let inputCount = try reader.readVarInt()
        guard inputCount <= 100_000 else { throw ByteReader.ReadError.malformed }
        inputs = try (0 ..< inputCount).map { _ in
            let prevTxid = try reader.readBytes(32)
            let prevVout = try reader.readUInt32()
            let scriptLength = try reader.readVarInt()
            let scriptSig = try reader.readBytes(length: scriptLength)
            let sequence = try reader.readUInt32()
            return Input(prevTxid: prevTxid, prevVout: prevVout, scriptSig: scriptSig, sequence: sequence)
        }

        let outputCount = try reader.readVarInt()
        guard outputCount <= 100_000 else { throw ByteReader.ReadError.malformed }
        outputs = try (0 ..< outputCount).map { _ in
            let value = try reader.readUInt64()
            let scriptLength = try reader.readVarInt()
            let script = try reader.readBytes(length: scriptLength)
            return Output(valueDuffs: value, scriptPubKey: script)
        }

        lockTime = try reader.readUInt32()

        if type > 0, reader.remaining > 0 {
            let payloadLength = try reader.readVarInt()
            extraPayload = try reader.readBytes(length: payloadLength)
        } else {
            extraPayload = nil
        }

        // Trailing garbage means we mis-parsed somewhere — refuse rather
        // than show wrong structure.
        guard reader.remaining == 0 else { throw ByteReader.ReadError.malformed }
    }
}

// MARK: - ByteReader

/// Little-endian cursor over consensus-serialized bytes.
private struct ByteReader {
    enum ReadError: Error {
        case outOfBounds
        case malformed
    }

    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var remaining: Int { bytes.count - offset }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= bytes.count else { throw ReadError.outOfBounds }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[b.startIndex]) | (UInt16(b[b.startIndex + 1]) << 8)
    }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        var value: UInt32 = 0
        for i in (0 ..< 4).reversed() {
            value = (value << 8) | UInt32(b[b.startIndex + i])
        }
        return value
    }

    mutating func readUInt64() throws -> UInt64 {
        let b = try readBytes(8)
        var value: UInt64 = 0
        for i in (0 ..< 8).reversed() {
            value = (value << 8) | UInt64(b[b.startIndex + i])
        }
        return value
    }

    /// Bitcoin-style CompactSize.
    mutating func readVarInt() throws -> UInt64 {
        let first = try readUInt8()
        switch first {
        case 0 ..< 0xfd: return UInt64(first)
        case 0xfd: return UInt64(try readUInt16())
        case 0xfe: return UInt64(try readUInt32())
        default: return try readUInt64()
        }
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= bytes.count else { throw ReadError.outOfBounds }
        defer { offset += count }
        return Data(bytes[offset ..< offset + count])
    }

    /// Consensus lengths arrive as CompactSize `UInt64`s; a plain `Int(_:)`
    /// conversion traps on values above `Int.max`, which malformed bytes can
    /// encode. Reject those as out-of-bounds instead of crashing.
    mutating func readBytes(length: UInt64) throws -> Data {
        guard let count = Int(exactly: length) else { throw ReadError.outOfBounds }
        return try readBytes(count)
    }
}

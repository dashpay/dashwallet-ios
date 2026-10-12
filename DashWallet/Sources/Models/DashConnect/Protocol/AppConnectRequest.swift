import Foundation

/// Why an App Connect request was refused. The two cases are the statuses a
/// wallet reports back to the app: `unsupported` for a version, mandatory
/// field or binding kind this decoder does not know (a newer app), `invalid`
/// for anything else that breaks the format.
enum AppConnectRequestError: Error, Equatable {
    case unsupported(String)
    case invalid(String)
}

/// App Connect request v2, as proposed by Yappr's `docs/APP_CONNECT_PROFILE.md`:
///
///     body = 0x02 ‖ appEphPub (33) ‖ appId (32) ‖ labelLen (1) ‖ label ‖ TLV*
///     TLV  = type (1) ‖ length (1) ‖ value
///
/// Even TLV types must be understood, so an unknown one refuses the request;
/// unknown odd types are skipped. TLVs come in ascending type order, and of
/// the known types only the two bindings repeat. Integers are big-endian.
///
/// This type only decodes and checks the format. Nothing in the login flow
/// reads it yet.
struct AppConnectRequest: Equatable {
    /// Wire tags, equal to Platform's `ContractBounds` bincode tags.
    enum BindingKind: UInt8 {
        case singleContract = 0
        case documentType = 1
        case contractGroup = 2
    }

    /// The security levels a binding may ask for, as Platform numbers them.
    enum SecurityLevel: UInt8 {
        case critical = 1
        case high = 2
    }

    /// The key purposes an encryption binding may ask for, as Platform
    /// numbers them.
    enum EncryptionPurpose: UInt8 {
        case encryption = 1
        case decryption = 2
    }

    struct AuthBinding: Equatable {
        let kind: BindingKind
        let securityLevel: SecurityLevel
        /// The contract id, or the group id for `contractGroup`.
        let id: Data
        /// Proposed lifetime budget in credits; nil when the request asks for
        /// none. A `contractGroup` binding always has one.
        let totalBudget: UInt64?
        /// Proposed expiry as a block time in milliseconds; nil for none.
        let expiresAt: UInt64?
        /// Set on `documentType` only.
        let documentTypeName: String?
    }

    struct EncryptionBinding: Equatable {
        let contractId: Data
        let purpose: EncryptionPurpose
    }

    enum Age: Equatable {
        case fresh
        /// Created more than `maxAge` before the wallet's clock.
        case stale
        /// Created more than `maxClockSkew` after it.
        case future
    }

    static let version: UInt8 = 0x02
    static let maxAuthBindings = 4
    static let maxEncryptionBindings = 2
    static let maxAge: TimeInterval = 10 * 60
    static let maxClockSkew: TimeInterval = 2 * 60

    let appEphemeralPubKey: Data
    /// The app's id: the contract the wallet brands the request with.
    let appId: Data
    /// Unauthenticated display hint from the payload; spoofable.
    let label: String
    /// The identity the app expects to answer.
    let identityHint: Data?
    /// One to four; the first is the primary binding.
    let authBindings: [AuthBinding]
    /// 16 bytes naming the app install, used to supersede its previous login.
    let connectionId: Data?
    let encryptionBindings: [EncryptionBinding]
    /// The request asks to renew an existing grant instead of logging in.
    let isRenewal: Bool
    /// Milliseconds since the epoch.
    let createdAt: UInt64

    func age(now: Date) -> Age {
        let created = TimeInterval(createdAt) / 1000
        let current = now.timeIntervalSince1970
        if current - created > Self.maxAge { return .stale }
        if created - current > Self.maxClockSkew { return .future }
        return .fresh
    }
}

extension AppConnectRequest {
    private enum TLV {
        static let identityHint: UInt8 = 0x01
        static let authBinding: UInt8 = 0x02
        static let connectionId: UInt8 = 0x03
        static let encryptionBinding: UInt8 = 0x04
        static let mode: UInt8 = 0x05
        static let createdAt: UInt8 = 0x06

        static let known: Set<UInt8> = [identityHint, authBinding, connectionId, encryptionBinding, mode, createdAt]
        static let fixedLengths: [UInt8: Int] = [
            identityHint: 32, connectionId: 16, encryptionBinding: 33, mode: 1, createdAt: 8,
        ]
    }

    private static let publicKeyLength = 33
    private static let idLength = 32
    private static let maxLabelLength = 64
    private static let maxDocumentTypeNameLength = 64
    private static let authBindingFixedLength = 1 + 1 + idLength + 8 + 8
    private static let modeRenew: UInt8 = 1
    /// The reference codec is JavaScript: a timestamp it cannot hold exactly
    /// is out of range there, so it is here too.
    private static let maxTimestamp: UInt64 = (1 << 53) - 1

    /// Whether a refusal is `unsupported` or `invalid` follows the reference
    /// codec. Framing, the most bindings allowed, the mode and the timestamps
    /// are checked as each TLV is read, and so is an unknown mandatory TLV or
    /// binding kind. The remaining rules (the key, the label's characters,
    /// levels, the group budget, type names, repeated bindings, the
    /// encryption purpose, the required fields) are checked after the last
    /// TLV, so an unknown part further on is reported first. Which of several
    /// broken rules is named may differ from the reference.
    static func decode(_ body: Data) throws -> AppConnectRequest {
        let bytes = [UInt8](body)
        guard let first = bytes.first else {
            throw AppConnectRequestError.invalid("empty request")
        }
        guard first == version else {
            throw AppConnectRequestError.unsupported("request version \(first)")
        }
        var offset = 1
        guard bytes.count >= offset + publicKeyLength + idLength + 1 else {
            throw AppConnectRequestError.invalid("request is truncated")
        }

        let appEphemeralPubKey = Data(bytes[offset ..< offset + publicKeyLength])
        offset += publicKeyLength
        var brokenRule: AppConnectRequestError?
        func note(_ message: String) {
            if brokenRule == nil { brokenRule = .invalid(message) }
        }
        if !Secp256k1.isValidCompressedPoint(appEphemeralPubKey) {
            note("app ephemeral public key is not a compressed secp256k1 point")
        }
        let appId = Data(bytes[offset ..< offset + idLength])
        offset += idLength

        let labelLength = Int(bytes[offset])
        offset += 1
        guard labelLength <= maxLabelLength else {
            throw AppConnectRequestError.invalid("label is longer than \(maxLabelLength) bytes")
        }
        guard offset + labelLength <= bytes.count else {
            throw AppConnectRequestError.invalid("request is truncated")
        }
        guard let label = String(validating: bytes[offset ..< offset + labelLength], as: UTF8.self) else {
            throw AppConnectRequestError.invalid("label is not valid UTF-8")
        }
        // None of the characters a label could use to disguise itself on the
        // approval sheet.
        if label.unicodeScalars.contains(where: isForbiddenInLabel) {
            note("label contains control or bidirectional formatting characters")
        }
        offset += labelLength

        var identityHint: Data?
        var authBindings: [AuthBinding] = []
        var connectionId: Data?
        var encryptionBindings: [EncryptionBinding] = []
        var isRenewal = false
        var createdAt: UInt64?
        var previousType: UInt8 = 0

        while offset < bytes.count {
            guard offset + 2 <= bytes.count else {
                throw AppConnectRequestError.invalid("TLV header is truncated")
            }
            let type = bytes[offset]
            let length = Int(bytes[offset + 1])
            offset += 2
            guard offset + length <= bytes.count else {
                throw AppConnectRequestError.invalid("TLV \(type) is truncated")
            }
            let value = bytes[offset ..< offset + length]
            offset += length

            // The two binding types repeat, and so may an optional type this
            // decoder does not know.
            let isRepeatable = type == TLV.authBinding || type == TLV.encryptionBinding
                || (!type.isMultiple(of: 2) && !TLV.known.contains(type))
            guard type > previousType || (type == previousType && isRepeatable) else {
                throw AppConnectRequestError.invalid("TLV \(type) is out of order or repeated")
            }
            previousType = type

            if let fixedLength = TLV.fixedLengths[type], length != fixedLength {
                throw AppConnectRequestError.invalid("TLV \(type) must be \(fixedLength) bytes")
            }

            switch type {
            case TLV.identityHint:
                identityHint = Data(value)
            case TLV.authBinding:
                guard authBindings.count < maxAuthBindings else {
                    throw AppConnectRequestError.invalid("more than \(maxAuthBindings) auth bindings")
                }
                let binding = try decodeAuthBinding(value, note: note)
                if authBindings.contains(where: {
                    $0.kind == binding.kind && $0.id == binding.id && $0.documentTypeName == binding.documentTypeName
                }) {
                    note("duplicate auth binding")
                }
                authBindings.append(binding)
            case TLV.connectionId:
                connectionId = Data(value)
            case TLV.encryptionBinding:
                guard encryptionBindings.count < maxEncryptionBindings else {
                    throw AppConnectRequestError.invalid("more than \(maxEncryptionBindings) encryption bindings")
                }
                let rawPurpose = value[value.index(before: value.endIndex)]
                let purpose = EncryptionPurpose(rawValue: rawPurpose)
                if purpose == nil {
                    note("encryption binding purpose \(rawPurpose)")
                }
                // The stand-in purpose never leaves: a noted rule refuses the request.
                let binding = EncryptionBinding(contractId: Data(value.prefix(idLength)), purpose: purpose ?? .encryption)
                if purpose != nil, encryptionBindings.contains(binding) {
                    note("duplicate encryption binding")
                }
                encryptionBindings.append(binding)
            case TLV.mode:
                guard value.first == modeRenew else {
                    throw AppConnectRequestError.invalid("unknown mode")
                }
                isRenewal = true
            case TLV.createdAt:
                let timestamp = try readTimestamp(value, what: "created-at")
                guard timestamp > 0 else {
                    throw AppConnectRequestError.invalid("created-at is zero")
                }
                createdAt = timestamp
            default:
                guard !type.isMultiple(of: 2) else {
                    throw AppConnectRequestError.unsupported("mandatory TLV \(type)")
                }
            }
        }

        guard let createdAt else {
            throw AppConnectRequestError.invalid("request has no created-at")
        }
        if let brokenRule {
            throw brokenRule
        }
        guard !authBindings.isEmpty else {
            throw AppConnectRequestError.invalid("request has no auth binding")
        }

        return AppConnectRequest(
            appEphemeralPubKey: appEphemeralPubKey,
            appId: appId,
            label: label,
            identityHint: identityHint,
            authBindings: authBindings,
            connectionId: connectionId,
            encryptionBindings: encryptionBindings,
            isRenewal: isRenewal,
            createdAt: createdAt
        )
    }

    /// Throws when the binding cannot be read; a rule its values break goes
    /// to `note`, and the binding returned then never leaves `decode`.
    private static func decodeAuthBinding(_ value: ArraySlice<UInt8>, note: (String) -> Void) throws -> AuthBinding {
        let bytes = Array(value)
        guard bytes.count >= authBindingFixedLength else {
            throw AppConnectRequestError.invalid("auth binding is truncated")
        }
        guard let kind = BindingKind(rawValue: bytes[0]) else {
            throw AppConnectRequestError.unsupported("auth binding kind \(bytes[0])")
        }
        // CRITICAL only on a contract group; HIGH on every kind.
        let securityLevel = SecurityLevel(rawValue: bytes[1])
        if securityLevel == nil || (securityLevel == .critical && kind != .contractGroup) {
            note("security level \(bytes[1]) is not allowed on this binding")
        }

        let id = Data(bytes[2 ..< 2 + idLength])
        let budget = readUInt64(bytes[34 ..< 42])
        let expiresAt = try readTimestamp(bytes[42 ..< 50], what: "expires-at")
        if kind == .contractGroup, budget == 0 {
            note("a contractGroup binding must carry a budget")
        }

        let rest = bytes[authBindingFixedLength...]
        var documentTypeName: String?
        if kind == .documentType {
            guard let nameLength = rest.first, Int(nameLength) + 1 == rest.count else {
                throw AppConnectRequestError.invalid("document type name length does not match")
            }
            let name = rest.dropFirst()
            guard let text = String(validating: name, as: UTF8.self) else {
                throw AppConnectRequestError.invalid("document type name is not valid UTF-8")
            }
            if !(1 ... maxDocumentTypeNameLength).contains(name.count) || !name.allSatisfy(isDocumentTypeNameByte) {
                note("document type name must be 1-64 of [A-Za-z0-9_-]")
            }
            documentTypeName = text
        } else {
            guard rest.isEmpty else {
                throw AppConnectRequestError.invalid("binding carries trailing bytes")
            }
        }

        return AuthBinding(
            kind: kind,
            securityLevel: securityLevel ?? .high,
            id: id,
            totalBudget: budget > 0 ? budget : nil,
            expiresAt: expiresAt > 0 ? expiresAt : nil,
            documentTypeName: documentTypeName
        )
    }

    /// C0 and C1 controls, and the bidirectional marks, embeddings, overrides
    /// and isolates.
    private static func isForbiddenInLabel(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00 ... 0x1F, 0x7F ... 0x9F, 0x061C, 0x200E, 0x200F, 0x202A ... 0x202E, 0x2066 ... 0x2069:
            return true
        default:
            return false
        }
    }

    private static func isDocumentTypeNameByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "a") ... UInt8(ascii: "z"),
             UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    private static func readUInt64(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }

    private static func readTimestamp(_ bytes: ArraySlice<UInt8>, what: String) throws -> UInt64 {
        let value = readUInt64(bytes)
        guard value <= maxTimestamp else {
            throw AppConnectRequestError.invalid("\(what) is out of range")
        }
        return value
    }
}

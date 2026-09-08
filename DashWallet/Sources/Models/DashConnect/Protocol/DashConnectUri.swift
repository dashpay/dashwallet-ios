import Foundation

enum DashConnectUriError: LocalizedError, Equatable {
    case invalidKeyScheme
    case invalidStScheme
    case unexpectedAuthority
    case missingQuery
    case emptyBody
    case missingNetwork
    case missingVersion
    case unsupportedVersion
    case unknownNetwork
    case invalidBase58
    case keyPayloadTooShort
    case invalidKeyPayloadVersion
    case keyLabelTooLong
    case keyLabelLengthOverrunsPayload
    case invalidEphemeralPublicKey
    case emptyTransitionPayload
    case invalidKeyLabelEncoding
    case bodyTooLong

    var errorDescription: String? {
        switch self {
        case .invalidKeyScheme:
            return "The URI does not use the dash-key scheme."
        case .invalidStScheme:
            return "The URI does not use the dash-st scheme."
        case .unexpectedAuthority:
            return "DashConnect URIs must not contain // authority separators."
        case .missingQuery:
            return "DashConnect URIs must include query parameters."
        case .emptyBody:
            return "DashConnect URIs must include a non-empty Base58 body."
        case .missingNetwork:
            return "DashConnect URIs must include the network query item."
        case .missingVersion:
            return "DashConnect URIs must include the version query item."
        case .unsupportedVersion:
            return "Only DashConnect URI version 1 is supported."
        case .unknownNetwork:
            return "The URI contains an unknown DashConnect network code."
        case .invalidBase58:
            return "The URI body is not valid Base58."
        case .keyPayloadTooShort:
            return "The dash-key payload is shorter than the minimum 67-byte format."
        case .invalidKeyPayloadVersion:
            return "The dash-key payload version byte is not supported."
        case .keyLabelTooLong:
            return "The dash-key payload label is longer than 64 bytes."
        case .keyLabelLengthOverrunsPayload:
            return "The dash-key payload label length overruns the payload."
        case .invalidEphemeralPublicKey:
            return "The dash-key payload contains an invalid compressed secp256k1 point."
        case .invalidKeyLabelEncoding:
            return "The dash-key application label is not valid UTF-8."
        case .emptyTransitionPayload:
            return "The dash-st payload must be non-empty."
        case .bodyTooLong:
            return "The URI body is longer than the DashConnect payload format allows."
        }
    }
}

enum DashConnectUri {
    private static let keyScheme = "dash-key:"
    private static let stScheme = "dash-st:"
    private static let expectedVersion = "1"
    private static let keyPayloadVersion: UInt8 = 0x01
    private static let compressedPubKeyLength = 33
    private static let contractIdLength = 32
    private static let minKeyPayloadLength = 1 + compressedPubKeyLength + contractIdLength + 1
    private static let maxLabelLength = 64

    /// Largest payloads the two formats can legitimately carry.
    ///
    /// `dash-key:` is fully specified: version + compressed point + contract id
    /// + label length + label. `dash-st:` carries a serialized state
    /// transition, which Platform caps well below this.
    private static let maxKeyPayloadLength = minKeyPayloadLength + maxLabelLength
    private static let maxStPayloadLength = 32 * 1024

    /// Encoded-length ceilings, enforced BEFORE decoding.
    ///
    /// `base58Decode` allocates a buffer proportional to the input and walks all
    /// of it once per input character, so its cost is quadratic in the encoded
    /// length. A QR code bounds that by its own capacity; a URL does not — any
    /// installed app, or a tapped remote link, can hand this an arbitrarily long
    /// run of valid Base58 characters, once per link. `parseQR` is `nonisolated
    /// async`, so that work runs on the cooperative pool rather than the main
    /// actor: it does not freeze the UI by itself, but it does burn CPU and
    /// battery on threads the rest of the app shares, and a burst of links
    /// starves them. The bound belongs here rather than at the URL boundary so
    /// every carrier, including ones added later, inherits it.
    ///
    /// Base58 expands by log(256)/log(58) ≈ 1.366 characters per byte; the
    /// integer form below rounds up, and the +8 absorbs the leading-zero
    /// characters the encoding adds one-for-one.
    private static func maxEncodedLength(forPayloadBytes bytes: Int) -> Int {
        (bytes * 1366 + 999) / 1000 + 8
    }
    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    private static let base58Reverse: [Int8] = {
        var map = [Int8](repeating: -1, count: 128)
        for (index, byte) in base58Alphabet.enumerated() {
            map[Int(byte)] = Int8(index)
        }
        return map
    }()

    static func isKeyUri(_ uri: String) -> Bool {
        uri.hasPrefix(keyScheme)
    }

    static func isStUri(_ uri: String) -> Bool {
        uri.hasPrefix(stScheme)
    }

    static func parseKeyRequest(_ uri: String) throws -> DashKeyRequest {
        let envelope = try parseEnvelope(uri,
                                         scheme: keyScheme,
                                         invalidScheme: .invalidKeyScheme,
                                         maxPayloadLength: maxKeyPayloadLength)
        let payload = envelope.payload

        guard payload.count >= minKeyPayloadLength else {
            throw DashConnectUriError.keyPayloadTooShort
        }
        guard payload[payload.startIndex] == keyPayloadVersion else {
            throw DashConnectUriError.invalidKeyPayloadVersion
        }

        let pubKeyStart = payload.index(after: payload.startIndex)
        let pubKeyEnd = payload.index(pubKeyStart, offsetBy: compressedPubKeyLength)
        let contractEnd = payload.index(pubKeyEnd, offsetBy: contractIdLength)
        let labelLengthIndex = contractEnd
        let labelStart = payload.index(after: labelLengthIndex)

        let appEphemeralPubKey = Data(payload[pubKeyStart ..< pubKeyEnd])
        guard Secp256k1.isValidCompressedPoint(appEphemeralPubKey) else {
            throw DashConnectUriError.invalidEphemeralPublicKey
        }

        let contractId = Data(payload[pubKeyEnd ..< contractEnd])
        let labelLength = Int(payload[labelLengthIndex])
        guard labelLength <= maxLabelLength else {
            throw DashConnectUriError.keyLabelTooLong
        }

        let requiredLabelEndOffset = payload.distance(from: payload.startIndex, to: labelStart)
        let expectedCount = requiredLabelEndOffset + labelLength
        guard payload.count >= expectedCount else {
            throw DashConnectUriError.keyLabelLengthOverrunsPayload
        }

        let labelEnd = payload.index(labelStart, offsetBy: labelLength)
        // `String(decoding:as:)` would substitute U+FFFD for malformed bytes and
        // hand back a label that no app actually sent; the payload spec requires
        // valid UTF-8, so a failure to decode is a malformed URI.
        guard let label = String(data: Data(payload[labelStart ..< labelEnd]), encoding: .utf8) else {
            throw DashConnectUriError.invalidKeyLabelEncoding
        }

        return DashKeyRequest(
            appEphemeralPubKey: appEphemeralPubKey,
            contractId: contractId,
            label: label,
            network: envelope.network
        )
    }

    static func parseStRequest(_ uri: String) throws -> DashStRequest {
        let envelope = try parseEnvelope(uri,
                                         scheme: stScheme,
                                         invalidScheme: .invalidStScheme,
                                         maxPayloadLength: maxStPayloadLength)
        guard !envelope.payload.isEmpty else {
            throw DashConnectUriError.emptyTransitionPayload
        }

        return DashStRequest(transitionBytes: envelope.payload, network: envelope.network)
    }

    private static func parseEnvelope(_ uri: String,
                                      scheme: String,
                                      invalidScheme: DashConnectUriError,
                                      maxPayloadLength: Int) throws
        -> (payload: Data, network: DashConnectNetwork) {
        guard uri.hasPrefix(scheme) else {
            throw invalidScheme
        }

        let remainder = String(uri.dropFirst(scheme.count))
        guard !remainder.hasPrefix("//") else {
            throw DashConnectUriError.unexpectedAuthority
        }

        guard let queryIndex = remainder.firstIndex(of: "?") else {
            throw DashConnectUriError.missingQuery
        }

        let body = String(remainder[..<queryIndex])
        guard !body.isEmpty else {
            throw DashConnectUriError.emptyBody
        }
        // Before the decode, not after: the point is to never run the quadratic
        // loop on an oversized body.
        guard body.utf8.count <= maxEncodedLength(forPayloadBytes: maxPayloadLength) else {
            throw DashConnectUriError.bodyTooLong
        }

        let query = String(remainder[remainder.index(after: queryIndex)...])
        let parameters = parseQueryItems(query)

        guard let version = parameters["v"] else {
            throw DashConnectUriError.missingVersion
        }
        guard version == expectedVersion else {
            throw DashConnectUriError.unsupportedVersion
        }

        guard let networkCode = parameters["n"] else {
            throw DashConnectUriError.missingNetwork
        }
        guard let network = DashConnectNetwork(rawValue: networkCode) else {
            throw DashConnectUriError.unknownNetwork
        }

        guard let payload = base58Decode(body) else {
            throw DashConnectUriError.invalidBase58
        }
        // The encoded ceiling is an upper bound with rounding slack in it; this
        // is the exact one the format allows.
        guard payload.count <= maxPayloadLength else {
            throw DashConnectUriError.bodyTooLong
        }

        return (payload, network)
    }

    private static func parseQueryItems(_ query: String) -> [String: String] {
        var result: [String: String] = [:]

        for item in query.split(separator: "&", omittingEmptySubsequences: false) {
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0])
            let value = parts.count == 2 ? String(parts[1]) : ""
            if !key.isEmpty, result[key] == nil {
                result[key] = value
            }
        }

        return result
    }

    private static func base58Decode(_ string: String) -> Data? {
        let input = Array(string.utf8)
        var leadingZeros = 0
        while leadingZeros < input.count, input[leadingZeros] == base58Alphabet[0] {
            leadingZeros += 1
        }

        let size = input.count * 733 / 1000 + 1
        var buffer = [UInt8](repeating: 0, count: size)

        for i in leadingZeros ..< input.count {
            let byte = input[i]
            guard byte < 128 else { return nil }

            let digit = base58Reverse[Int(byte)]
            guard digit >= 0 else { return nil }

            var carry = Int(digit)
            for j in stride(from: size - 1, through: 0, by: -1) {
                carry += 58 * Int(buffer[j])
                buffer[j] = UInt8(carry & 0xff)
                carry >>= 8
            }
        }

        var start = 0
        while start < size, buffer[start] == 0 {
            start += 1
        }

        var result = [UInt8](repeating: 0, count: leadingZeros)
        if start < buffer.count {
            result.append(contentsOf: buffer[start...])
        }
        return Data(result)
    }
}

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
    /// + label length + label.
    ///
    /// `dash-st:` carries one `IdentityUpdateTransition` that adds the two
    /// login keys: identity id, revision, nonce, two key entries with their
    /// contract bounds and per-key signatures, and the transition signature —
    /// well under a kilobyte. The ceiling is deliberately not Platform's own
    /// state-transition limit, which is far larger than this format ever needs
    /// and which the decode below cannot afford: its cost is quadratic in the
    /// encoded length, so a 32 KiB ceiling would admit a ~44,800-character body
    /// worth ~1.5 billion inner iterations — seconds of CPU per link, from any
    /// installed app. 4 KiB costs ~23 million, tens of milliseconds, and still
    /// leaves several times the headroom a longer key form or an added field
    /// would need.
    private static let maxKeyPayloadLength = minKeyPayloadLength + maxLabelLength
    private static let maxStPayloadLength = 4 * 1024
    /// The largest App Connect request the format defines today (a 64-byte
    /// label, four auth bindings with full-length names, two encryption
    /// bindings and every optional field) is 734 bytes. The rest is room for optional
    /// fields a newer app may add, which this decoder has to skip, at a
    /// decode cost that stays small.
    private static let maxAppConnectPayloadLength = 1024
    private static let appConnectVersion = "2"
    private static let maxCallbackLength = 512

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
    /// starves them. That is why the payload ceilings above are the smallest
    /// each format can be given rather than the largest Platform would accept.
    /// The bound belongs here rather than at the URL boundary so every carrier,
    /// including ones added later, inherits it.
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

    /// Whether a `dash-key:` URI asks for request version 2 (`v=2`), and so
    /// belongs to `parseAppConnectRequest`. The v1 parser cannot tell: it
    /// measures the body before it reads the version. The query is read as
    /// that parser reads it, form-decoded, so `v=%32` is version 2 as well.
    static func isAppConnectUri(_ uri: String) -> Bool {
        guard isKeyUri(uri), let queryIndex = uri.unicodeScalars.firstIndex(of: "?") else { return false }
        var query = uri.unicodeScalars[uri.unicodeScalars.index(after: queryIndex)...]
        if query.first == "?" { query = query.dropFirst() }
        return query.split(separator: "&").contains { item in
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 && formDecoded(parts[0]) == "v" && formDecoded(parts[1]) == appConnectVersion
        }
    }

    /// Parses a `dash-key:` URI of version 2. A version 1 URI is
    /// `unsupported` here: it belongs to `parseKeyRequest`.
    static func parseAppConnectRequest(_ uri: String) throws -> AppConnectUri {
        // Scalars, not characters: a combining mark after the scheme or a
        // delimiter must not hide it.
        guard uri.unicodeScalars.starts(with: keyScheme.unicodeScalars) else {
            throw AppConnectRequestError.invalid("not a dash-key URI")
        }
        let remainder = uri.unicodeScalars.dropFirst(keyScheme.unicodeScalars.count)
        guard let queryIndex = remainder.firstIndex(of: "?") else {
            throw AppConnectRequestError.invalid("URI has no query")
        }
        let body = String(remainder[..<queryIndex])

        var query = remainder[remainder.index(after: queryIndex)...]
        if query.first == "?" { query = query.dropFirst() }
        let parameters = try appConnectParameters(query, known: ["n", "v", "cb"])

        return try finishAppConnectRequest(parameters) {
            // Before the decode, as for the other two formats: its cost is
            // quadratic in the encoded length.
            guard body.utf8.count <= maxEncodedLength(forPayloadBytes: maxAppConnectPayloadLength) else {
                throw AppConnectRequestError.invalid("request is too long")
            }
            guard let payload = base58Decode(body) else {
                throw AppConnectRequestError.invalid("request is not base58")
            }
            return payload
        }
    }

    // MARK: - dashpay://connect

    private static let dashpayUrlPrefix = Array("dashpay://".unicodeScalars)
    private static let connectHost = "connect"
    /// Hosts of `dashpay:` links that other parts of the wallet read (an
    /// invitation, a contact's user code). They are not unknown verbs.
    private static let otherKnownDashpayHosts: Set<String> = ["invite", "user"]
    /// The whole URI, checked on the raw string before anything is decoded.
    private static let maxConnectUriBytes = 4096
    /// 1,024 bytes of body in unpadded base64url.
    private static let maxConnectBodyCharacters = 1366
    /// How much of the text after `dashpay://` `dashpayHost` reads.
    private static let maxAuthorityScalars = 256

    /// The lowercased host of a `dashpay://` URI, which names its verb, or nil
    /// for any other string. Scheme and host compare case-insensitively. A
    /// userinfo or port is dropped here so that `dashpay://connect:80` is
    /// still read as `connect` and refused by the parser, not as another
    /// link.
    ///
    /// This runs on any string before the connect parser's size limit, so it
    /// reads at most `maxAuthorityScalars` scalars after the scheme and its
    /// cost does not grow with the input. A real verb, userinfo and port fit
    /// well inside that; a longer authority is classified from its first
    /// scalars, which makes it an unknown verb, not a connect link.
    private static func dashpayHost(of uri: String) -> String? {
        let scalars = uri.unicodeScalars
        let head = Array(scalars.prefix(dashpayUrlPrefix.count))
        guard head.count == dashpayUrlPrefix.count,
              zip(head, dashpayUrlPrefix).allSatisfy({ asciiLowercased($0) == $1 }) else { return nil }
        let authority = Array(scalars.dropFirst(dashpayUrlPrefix.count).prefix(maxAuthorityScalars)
            .prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        let afterUserinfo = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? []
        let host = afterUserinfo.prefix { $0 != ":" }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: host.map(asciiLowercased))
        return String(result)
    }

    private static func asciiLowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        ("A" ... "Z").contains(scalar) ? Unicode.Scalar(scalar.value + 0x20)! : scalar
    }

    /// Whether `uri` is a `dashpay://connect` link. Only the verb is read;
    /// `parseConnectRequest` decides whether the rest is valid.
    static func isConnectUri(_ uri: String) -> Bool {
        dashpayHost(of: uri) == connectHost
    }

    /// Whether `uri` is a `dashpay://` link whose verb this wallet does not
    /// know (the DIP's `sign`, or one a later DIP adds). The user should be
    /// told the link needs a newer wallet, not that it is not a Dash link.
    static func isUnsupportedDashpayVerb(_ uri: String) -> Bool {
        guard let host = dashpayHost(of: uri), !host.isEmpty else { return false }
        return host != connectHost && !otherKnownDashpayHosts.contains(host)
    }

    /// Parses `dashpay://connect?v=2&n=<m|t|d>&r=<base64url body>[&cb=<https URL>]`
    /// (DIP App Connect, "connect URI"). The body is the one a `dash-key:`
    /// version 2 URI carries and is processed identically.
    static func parseConnectRequest(_ uri: String) throws -> AppConnectUri {
        // The raw string, before anything is decoded or split.
        guard uri.utf8.count <= maxConnectUriBytes else {
            throw AppConnectRequestError.invalid("URI is too long")
        }
        guard dashpayHost(of: uri) == connectHost else {
            throw AppConnectRequestError.invalid("not a dashpay://connect URI")
        }
        let rest = uri.unicodeScalars.dropFirst(dashpayUrlPrefix.count)
        guard !rest.contains("#") else {
            throw AppConnectRequestError.invalid("URI has a fragment")
        }
        let authority = rest.prefix { !["/", "?"].contains($0) }
        guard authority.count == connectHost.unicodeScalars.count else {
            throw AppConnectRequestError.invalid("URI has userinfo or a port")
        }
        // The path is empty, or a single `/` that is ignored.
        let afterAuthority = rest.dropFirst(authority.count)
        let path = afterAuthority.prefix { $0 != "?" }
        guard path.isEmpty || String(path) == "/" else {
            throw AppConnectRequestError.invalid("URI has a path")
        }
        let query = afterAuthority.dropFirst(path.count)
        guard query.first == "?" else {
            throw AppConnectRequestError.invalid("URI has no query")
        }
        let parameters = try appConnectParameters(query.dropFirst(), known: ["n", "v", "r", "cb"])

        return try finishAppConnectRequest(parameters) {
            guard let encoded = parameters["r"], !encoded.isEmpty else {
                throw AppConnectRequestError.invalid("request is missing")
            }
            // Before the decode, as everywhere.
            guard encoded.utf8.count <= maxConnectBodyCharacters else {
                throw AppConnectRequestError.invalid("request is too long")
            }
            // 1,366 characters decode to at most 1,024 bytes, the ceiling checked after.
            guard let payload = base64URLDecode(encoded) else {
                throw AppConnectRequestError.invalid("request is not canonical base64url")
            }
            return payload
        }
    }

    /// Canonical base64url (RFC 4648 section 5, no padding), or nil. Refused:
    /// `=`, `+`, `/`, anything outside the alphabet, a length of 1 mod 4, and
    /// non-zero bits in the last character, so each value has one encoding.
    static func base64URLDecode(_ string: String) -> Data? {
        let input = Array(string.utf8)
        guard input.count % 4 != 1 else { return nil }

        var output = Data()
        output.reserveCapacity(input.count * 3 / 4)
        var accumulator: UInt32 = 0
        var bits = 0
        for byte in input {
            let value: UInt32
            switch byte {
            case UInt8(ascii: "A") ... UInt8(ascii: "Z"): value = UInt32(byte - UInt8(ascii: "A"))
            case UInt8(ascii: "a") ... UInt8(ascii: "z"): value = UInt32(byte - UInt8(ascii: "a")) + 26
            case UInt8(ascii: "0") ... UInt8(ascii: "9"): value = UInt32(byte - UInt8(ascii: "0")) + 52
            case UInt8(ascii: "-"): value = 62
            case UInt8(ascii: "_"): value = 63
            default: return nil
            }
            accumulator = accumulator << 6 | value
            bits += 6
            if bits >= 8 {
                bits -= 8
                output.append(UInt8(truncatingIfNeeded: accumulator >> UInt32(bits)))
                accumulator &= (1 << UInt32(bits)) - 1
            }
        }
        // What is left are the padding bits of the last character.
        guard accumulator == 0 else { return nil }
        return output
    }

    // MARK: - Shared by the App Connect carriers

    /// Splits a query on `&` and keeps the `known` parameters. Names and
    /// values are form-decoded before they are compared, as the app's
    /// `URLSearchParams` does; a repeated known parameter is invalid and
    /// unknown ones are ignored.
    private static func appConnectParameters(_ query: Substring.UnicodeScalarView, known: Set<String>) throws -> [String: String] {
        var parameters: [String: String] = [:]
        for item in query.split(separator: "&") {
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = formDecoded(parts[0])
            guard known.contains(name) else { continue }
            guard parameters[name] == nil else {
                throw AppConnectRequestError.invalid("query parameter \(name) is repeated")
            }
            parameters[name] = parts.count == 2 ? formDecoded(parts[1]) : ""
        }
        return parameters
    }

    /// The part both carriers share: `v`, then `n`, then the body bytes the
    /// carrier produces, then `cb`, then the body decoder.
    private static func finishAppConnectRequest(_ parameters: [String: String],
                                                payload: () throws -> Data) throws -> AppConnectUri {
        guard parameters["v"] == appConnectVersion else {
            // The value is untrusted and unbounded: only a short number is echoed.
            let version = parameters["v"].map { (1 ... 3).contains($0.utf8.count) && $0.utf8.allSatisfy { (0x30 ... 0x39).contains($0) } ? $0 : "(unreadable)" }
            throw AppConnectRequestError.unsupported("URI version \(version ?? "(none)")")
        }
        guard let network = parameters["n"].flatMap(DashConnectNetwork.init(rawValue:)) else {
            throw AppConnectRequestError.invalid("unknown network")
        }
        let body = try payload()
        guard body.count <= maxAppConnectPayloadLength else {
            throw AppConnectRequestError.invalid("request is too long")
        }
        let callback = try parameters["cb"].map(parseCallback)

        return AppConnectUri(request: try AppConnectRequest.decode(body), network: network, callback: callback)
    }

    /// `+` is a space and each well-formed `%XX` a byte; a `%` that is not
    /// followed by two hex digits stands as written. Bytes that are not
    /// UTF-8 come out as U+FFFD.
    private static func formDecoded(_ scalars: Substring.UnicodeScalarView) -> String {
        let source = Array(String(scalars).utf8)
        let hexValue = { (byte: UInt8) -> UInt8? in
            byte < 0x80 ? Character(UnicodeScalar(byte)).hexDigitValue.map(UInt8.init) : nil
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(source.count)
        var index = 0
        while index < source.count {
            let byte = source[index]
            if byte == UInt8(ascii: "%"), index + 2 < source.count,
               let high = hexValue(source[index + 1]), let low = hexValue(source[index + 2]) {
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(byte == UInt8(ascii: "+") ? 0x20 : byte)
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `cb` is an absolute `https` URL without credentials, already
    /// form-decoded. The app's own check takes anything a browser's URL
    /// parser repairs or percent-encodes; this refuses what `URLComponents`
    /// does not take as written, and takes a host only when it is a plain
    /// lowercase DNS name (see `isPlainHostName`) and a port only when it is
    /// a port. The host is what the user will be shown. In one case this is
    /// the looser side: an `xn--` label that is not valid punycode passes
    /// here and not in the app.
    private static func parseCallback(_ text: String) throws -> URL {
        guard text.utf16.count <= maxCallbackLength,
              let components = URLComponents(string: text, encodingInvalidCharacters: false),
              components.scheme?.lowercased() == "https",
              // Presence, not the decoded value: that is nil for bytes that are not UTF-8.
              components.rangeOfUser == nil, components.rangeOfPassword == nil,
              let hostRange = components.rangeOfHost, isPlainHostName(text[hostRange]),
              components.rangeOfPort == nil || components.port.map({ (0 ... 65535).contains($0) }) == true,
              let url = components.url else {
            throw AppConnectRequestError.invalid("callback is not an https URL without credentials")
        }
        return url
    }

    /// Dot-separated labels of lowercase ASCII letters, digits and hyphens,
    /// none of them empty, the last one starting with a letter. That leaves
    /// out IP addresses in every spelling (`[::1]`, `1.2.3.4`, `2130706433`,
    /// `1.2.3.0x4`), bracketed text, which `URL.host` reads back without the
    /// brackets, percent-encoding, and capitals, which a browser lowercases
    /// (`paypaI.com` opens `paypai.com`). Whether an `xn--` label is valid
    /// punycode is not checked.
    private static func isPlainHostName(_ host: Substring) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isLetter = { (scalar: Unicode.Scalar) in ("a" ... "z").contains(scalar) }
        return labels.allSatisfy { label in
            !label.isEmpty && label.unicodeScalars.allSatisfy { isLetter($0) || ("0" ... "9").contains($0) || $0 == "-" }
        } && labels.last?.unicodeScalars.first.map(isLetter) == true
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

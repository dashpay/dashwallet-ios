import XCTest
@testable import dashpay

final class DashConnectUriTests: XCTestCase {
    private let appPrivateKey = Data(repeating: 0x01, count: 32)
    private let contractId = Data(repeating: 0xcd, count: 32)
    private let label = "Login to Yappr"

    func testParsesValidDashKeyRequest() throws {
        let request = try DashConnectUri.parseKeyRequest(try validKeyUri())

        XCTAssertEqual(request.network, .testnet)
        XCTAssertEqual(
            request.appEphemeralPubKey.hexEncodedString(),
            "031b84c5567b126440995d3ed5aaba0565d71e1834604819ff9c17f5e9d5dd078f"
        )
        XCTAssertEqual(request.contractId, contractId)
        XCTAssertEqual(request.label, label)
    }

    func testParsesValidDashStRequest() throws {
        let request = try DashConnectUri.parseStRequest(validStUri())
        XCTAssertEqual(request.network, .testnet)
        XCTAssertEqual(request.transitionBytes, Data([0x01, 0x02, 0x03, 0x04]))
    }

    func testRecognizesUriKinds() throws {
        XCTAssertTrue(DashConnectUri.isKeyUri(try validKeyUri()))
        XCTAssertFalse(DashConnectUri.isKeyUri(validStUri()))
        XCTAssertTrue(DashConnectUri.isStUri(validStUri()))
        XCTAssertFalse(DashConnectUri.isStUri(try validKeyUri()))
    }

    func testParsesAllSupportedNetworks() throws {
        XCTAssertEqual(try DashConnectUri.parseKeyRequest(try validKeyUri(network: .mainnet)).network, .mainnet)
        XCTAssertEqual(try DashConnectUri.parseKeyRequest(try validKeyUri(network: .testnet)).network, .testnet)
        XCTAssertEqual(try DashConnectUri.parseKeyRequest(try validKeyUri(network: .devnet)).network, .devnet)
    }

    func testRejectsWrongScheme() {
        assertKeyError("dash:123?n=t&v=1", .invalidKeyScheme)
        assertStError("dash:123?n=t&v=1", .invalidStScheme)
    }

    func testRejectsAuthorityComponent() {
        assertKeyError("dash-key://abc?n=t&v=1", .unexpectedAuthority)
        assertStError("dash-st://abc?n=t&v=1", .unexpectedAuthority)
    }

    func testRejectsMissingQueryAndEmptyBody() {
        assertKeyError("dash-key:abc", .missingQuery)
        assertKeyError("dash-key:?n=t&v=1", .emptyBody)
        assertStError("dash-st:abc", .missingQuery)
        assertStError("dash-st:?n=t&v=1", .emptyBody)
    }

    func testRejectsMissingNetworkAndMissingVersion() throws {
        assertKeyError(try validKeyUri(query: "v=1"), .missingNetwork)
        assertKeyError(try validKeyUri(query: "n=t"), .missingVersion)
        assertStError(validStUri(query: "v=1"), .missingNetwork)
        assertStError(validStUri(query: "n=t"), .missingVersion)
    }

    func testRejectsUnsupportedVersionAndUnknownNetwork() throws {
        assertKeyError(try validKeyUri(query: "n=t&v=2"), .unsupportedVersion)
        assertKeyError(try validKeyUri(query: "n=x&v=1"), .unknownNetwork)
        assertStError(validStUri(query: "n=t&v=2"), .unsupportedVersion)
        assertStError(validStUri(query: "n=x&v=1"), .unknownNetwork)
    }

    func testRejectsInvalidBase58() {
        assertKeyError("dash-key:0OIl?n=t&v=1", .invalidBase58)
        assertStError("dash-st:0OIl?n=t&v=1", .invalidBase58)
    }

    func testRejectsShortKeyPayloadAndWrongPayloadVersion() throws {
        assertKeyError(keyUri(payload: Data(repeating: 0x00, count: 66)), .keyPayloadTooShort)

        var payload = try validKeyPayload()
        payload[0] = 0x02
        assertKeyError(keyUri(payload: payload), .invalidKeyPayloadVersion)
    }

    func testRejectsTooLongAndOverrunningLabelLengths() throws {
        var tooLong = try validKeyPayload()
        tooLong[66] = 65
        assertKeyError(keyUri(payload: tooLong), .keyLabelTooLong)

        var overrunning = try validKeyPayload()
        overrunning[66] = UInt8(label.utf8.count + 1)
        assertKeyError(keyUri(payload: overrunning), .keyLabelLengthOverrunsPayload)
    }

    func testRejectsInvalidEphemeralPoint() throws {
        var payload = try validKeyPayload()
        payload.replaceSubrange(1 ..< 34, with: data([Data([0x02]), Data(repeating: 0x00, count: 32)]))
        assertKeyError(keyUri(payload: payload), .invalidEphemeralPublicKey)
    }

    func testAllowsEmptyLabel() throws {
        let ephemeralKey = try validEphemeralPublicKey()
        let payload = Data([0x01]) + ephemeralKey + contractId + Data([0x00])
        let request = try DashConnectUri.parseKeyRequest(keyUri(payload: payload))
        XCTAssertEqual(request.label, "")
    }

    func testRejectsEmptyTransitionBody() {
        assertStError("dash-st:?n=t&v=1", .emptyBody)
    }

    // MARK: - Deep links

    func testDeepLinkAcceptsBothDashConnectSchemes() throws {
        let keyUri = try validKeyUri()
        let stUri = validStUri()

        XCTAssertEqual(DashConnectDeepLink.uri(from: try url(keyUri)), keyUri)
        XCTAssertEqual(DashConnectDeepLink.uri(from: try url(stUri)), stUri)
        XCTAssertTrue(DashConnectDeepLink.canHandle(try url(keyUri)))
    }

    func testDeepLinkRejectsTheAppsOtherSchemes() throws {
        for uri in [
            "dash:XnhkeQZLtHqzYqbxLXaAvB9RLnKGrRWKgy?amount=0.1",
            "dashwallet://scanqr",
            "dashpay://invite/abc",
            "pay:XnhkeQZLtHqzYqbxLXaAvB9RLnKGrRWKgy",
            "https://yap.pr/login",
        ] {
            XCTAssertNil(DashConnectDeepLink.uri(from: try url(uri)), uri)
            XCTAssertFalse(DashConnectDeepLink.canHandle(try url(uri)), uri)
        }
    }

    // MARK: - Scanned codes

    func testScannedStringAcceptsBothDashConnectSchemes() throws {
        let keyUri = try validKeyUri()
        let stUri = validStUri()

        XCTAssertEqual(DashConnectDeepLink.uri(from: keyUri), keyUri)
        XCTAssertEqual(DashConnectDeepLink.uri(from: stUri), stUri)
        XCTAssertEqual(DashConnectDeepLink.uri(from: " \(keyUri)\n"), keyUri)
    }

    func testScannedStringRejectsPaymentCodes() {
        for code in [
            "XnhkeQZLtHqzYqbxLXaAvB9RLnKGrRWKgy",
            "dash:XnhkeQZLtHqzYqbxLXaAvB9RLnKGrRWKgy?amount=0.1",
            "pay:XnhkeQZLtHqzYqbxLXaAvB9RLnKGrRWKgy",
            "https://yap.pr/login",
            "",
        ] {
            XCTAssertNil(DashConnectDeepLink.uri(from: code), code)
        }
    }


    private func assertKeyError(_ uri: String, _ expected: DashConnectUriError) {
        XCTAssertThrowsError(try DashConnectUri.parseKeyRequest(uri)) { error in
            XCTAssertEqual(error as? DashConnectUriError, expected)
        }
    }

    private func assertStError(_ uri: String, _ expected: DashConnectUriError) {
        XCTAssertThrowsError(try DashConnectUri.parseStRequest(uri)) { error in
            XCTAssertEqual(error as? DashConnectUriError, expected)
        }
    }

    private func validKeyUri(network: DashConnectNetwork = .testnet, query: String? = nil) throws -> String {
        keyUri(payload: try validKeyPayload(), network: network, query: query)
    }

    private func validStUri(network: DashConnectNetwork = .testnet, query: String? = nil) -> String {
        stUri(payload: Data([0x01, 0x02, 0x03, 0x04]), network: network, query: query)
    }

    private func keyUri(payload: Data,
                        network: DashConnectNetwork = .testnet,
                        query: String? = nil) -> String {
        "dash-key:\(base58Encode(payload))?\(query ?? "n=\(network.rawValue)&v=1")"
    }

    private func stUri(payload: Data,
                       network: DashConnectNetwork = .testnet,
                       query: String? = nil) -> String {
        "dash-st:\(base58Encode(payload))?\(query ?? "n=\(network.rawValue)&v=1")"
    }

    private func validKeyPayload() throws -> Data {
        let labelData = Data(label.utf8)
        return data([
            Data([0x01]),
            try validEphemeralPublicKey(),
            contractId,
            Data([UInt8(labelData.count)]),
            labelData,
        ])
    }

    private func validEphemeralPublicKey() throws -> Data {
        try Secp256k1.compressedPublicKey(privateKey: appPrivateKey)
    }

    private func base58Encode(_ data: Data) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
        let bytes = [UInt8](data)
        var leadingZeros = 0
        while leadingZeros < bytes.count, bytes[leadingZeros] == 0 {
            leadingZeros += 1
        }

        let size = (bytes.count - leadingZeros) * 138 / 100 + 1
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
        while start < size, buffer[start] == 0 {
            start += 1
        }

        var result = [UInt8]()
        result.reserveCapacity(leadingZeros + size - start)
        result.append(contentsOf: repeatElement(alphabet[0], count: leadingZeros))
        for i in start ..< size {
            result.append(alphabet[Int(buffer[i])])
        }
        return String(decoding: result, as: UTF8.self)
    }

    private func data(_ chunks: [Data]) -> Data {
        var result = Data()
        for chunk in chunks {
            result.append(chunk)
        }
        return result
    }

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string), "not a URL: \(string)")
    }

    // MARK: payload size limits

    // The decoder's cost is quadratic in the encoded length. A QR code bounds
    // that by its own capacity; a link does not, so the bound is enforced here
    // and every carrier inherits it.

    private func keyUri(body: String) -> String { "dash-key:\(body)?v=1&n=t" }
    private func stUri(body: String) -> String { "dash-st:\(body)?v=1&n=t" }

    func testOversizedKeyBodyIsRejectedBeforeDecoding() {
        // 131 bytes is the largest legal dash-key payload; 4096 Base58
        // characters is far past its encoded ceiling.
        let body = String(repeating: "z", count: 4096)
        XCTAssertThrowsError(try DashConnectUri.parseKeyRequest(keyUri(body: body))) { error in
            XCTAssertEqual(error as? DashConnectUriError, .bodyTooLong)
        }
    }

    func testOversizedStBodyIsRejectedBeforeDecoding() {
        let body = String(repeating: "z", count: 200_000)
        XCTAssertThrowsError(try DashConnectUri.parseStRequest(stUri(body: body))) { error in
            XCTAssertEqual(error as? DashConnectUriError, .bodyTooLong)
        }
    }

    func testTheLimitIsCheckedCheaply() {
        // The guard must fire on length alone, not after a decode: a body of
        // characters that are not even Base58 must still be rejected as too
        // long, which is only possible if the check precedes the decode.
        let body = String(repeating: "0", count: 500_000)   // '0' is not in the alphabet
        XCTAssertThrowsError(try DashConnectUri.parseStRequest(stUri(body: body))) { error in
            XCTAssertEqual(error as? DashConnectUriError, .bodyTooLong,
                           "a length check that ran after the decode would report invalidBase58")
        }
    }

    func testAnStPayloadAtTheCeilingIsAccepted() throws {
        // The ceiling is several times what an IdentityUpdateTransition adding
        // two login keys needs, so a payload sitting exactly on it must parse.
        let payload = Data(repeating: 0x7f, count: 4 * 1024)
        let request = try DashConnectUri.parseStRequest(stUri(payload: payload))
        XCTAssertEqual(request.transitionBytes, payload)
    }

    func testAnStPayloadOverTheCeilingIsRejected() {
        let payload = Data(repeating: 0x7f, count: 4 * 1024 + 1)
        XCTAssertThrowsError(try DashConnectUri.parseStRequest(stUri(payload: payload))) { error in
            XCTAssertEqual(error as? DashConnectUriError, .bodyTooLong)
        }
    }

    func testAKeyBodyWithinTheFormatIsNotRejectedForLength() {
        // A body that is too short to be a valid payload must fail on its own
        // merits, never on length — the ceiling must not clip legitimate URIs.
        let body = String(repeating: "z", count: 32)
        XCTAssertThrowsError(try DashConnectUri.parseKeyRequest(keyUri(body: body))) { error in
            XCTAssertNotEqual(error as? DashConnectUriError, .bodyTooLong)
        }
    }

    // MARK: - App Connect request v2

    /// Yappr's published vectors (`vendor/platform-auth/src/app-connect/vectors.json`).
    private enum AppConnectVector {
        static let requestBytes = Data(hex: "0203e83cb927e85f96ae50a95ca3be21cc7a3755139a941b15d99b01af4fecf0d270f8833c7a2d58ab816c24ae915fe2aa94676588b467ba1e9f2b24c1a3df7fdb7805596170707202320201b0590e59269c6885acf71d27ddfce85187e2cc9736c42e958127cd35be6d38e80000000ba43b7400000001a2f7beb400023a0102a2a1b4ac6fef22ea2a1a68e8123644b357875f6b412c18109281c146e7b271bc000000003b9aca00000001a2f7beb4000770726f66696c650310a69b1b4f666681453dec3734667a5ab20421f8833c7a2d58ab816c24ae915fe2aa94676588b467ba1e9f2b24c1a3df7fdb78010608000001a128425c00")!
        static let requestUri = "dash-key:2fAANHHASdojyjV9Sqa2wf2nwZE8kLLqmeHpZWa8sBfaGsddVqyMG2ZVte7xJkTKsXvmFYbXzXbNnMo7bJQBxNcf79N8YWi7pLKyb39Rqv6b1KUmxw9UeJGYz2CV9hFGNUQtcyMYVq2Fg6vAxtxpYays61H8gLMcWqaG8TfgGA3H7setGAYiBsM5YmdZgeuCdGAHSwfNfav5cfFjXNDkPWv37UNSgFxj6o58jfXc3kCLKqLJtc5ZPjm1thEGYxK8HVYBi8fRQeEVy76n27DXGrVTyHz94CfJRuMnH76xGYbMgeuvurxjJMLrQgWUu53cjocYyzzNWdJrgs2D5?n=d&v=2&cb=https%3A%2F%2Fyap.pr%2Fconnect%3Fr%3Dd77dc0da9df83a47755a15c42c5d9db9d7a7fd62"
        static let renewBytes = Data(hex: "0203e83cb927e85f96ae50a95ca3be21cc7a3755139a941b15d99b01af4fecf0d270f8833c7a2d58ab816c24ae915fe2aa94676588b467ba1e9f2b24c1a3df7fdb7805596170707201209296d642338cb3bfceeb554285462719e15f004d0579ce53ea77fb6d86cd9ab902320201b0590e59269c6885acf71d27ddfce85187e2cc9736c42e958127cd35be6d38e80000000ba43b7400000001a2f7beb4000310a69b1b4f666681453dec3734667a5ab20501010608000001a128425c00")!
        static let renewUri = "dash-key:iJ1PNsQ8ThpuRCEMwQJG9ffSCyMb7vfLJDiYFhU3epnaeTDAZxAdVv9NyHP4CeToE4XT1UYUtTeBzHZ6pFcCRtRnDkeVA32woHqKBGsGrJWYcmVFeTKM5Sip7jKiWC2emRfmekq3qpcrXBmUZon1Ro4vTxztmGCbEdwyMf6DKHbJ9JLuBF3G17bXdjrg32xMMftA36fKEtNr9J2auvn8XBi322CmWUWUgKmwxpAvtwnnvZYTG81eQ73YPiCRX6Soh?n=t&v=2"
        static let appEphemeralPubKey = Data(hex: "03e83cb927e85f96ae50a95ca3be21cc7a3755139a941b15d99b01af4fecf0d270")!
        static let appId = Data(hex: "f8833c7a2d58ab816c24ae915fe2aa94676588b467ba1e9f2b24c1a3df7fdb78")!
        static let groupId = Data(hex: "b0590e59269c6885acf71d27ddfce85187e2cc9736c42e958127cd35be6d38e8")!
        static let dashpayContractId = Data(hex: "a2a1b4ac6fef22ea2a1a68e8123644b357875f6b412c18109281c146e7b271bc")!
        static let ownerId = Data(hex: "9296d642338cb3bfceeb554285462719e15f004d0579ce53ea77fb6d86cd9ab9")!
        static let connectionId = Data(hex: "a69b1b4f666681453dec3734667a5ab2")!
        static let createdAt: UInt64 = 1791676800000
        static let expiresAt: UInt64 = 1799452800000
    }

    func testDecodesThePublishedAppConnectRequest() throws {
        let request = try AppConnectRequest.decode(AppConnectVector.requestBytes)

        XCTAssertEqual(request, AppConnectRequest(
            appEphemeralPubKey: AppConnectVector.appEphemeralPubKey,
            appId: AppConnectVector.appId,
            label: "Yappr",
            identityHint: nil,
            authBindings: [
                .init(kind: .contractGroup, securityLevel: .critical, id: AppConnectVector.groupId,
                      totalBudget: 50_000_000_000, expiresAt: AppConnectVector.expiresAt, documentTypeName: nil),
                .init(kind: .documentType, securityLevel: .high, id: AppConnectVector.dashpayContractId,
                      totalBudget: 1_000_000_000, expiresAt: AppConnectVector.expiresAt, documentTypeName: "profile"),
            ],
            connectionId: AppConnectVector.connectionId,
            encryptionBindings: [.init(contractId: AppConnectVector.appId, purpose: .encryption)],
            isRenewal: false,
            createdAt: AppConnectVector.createdAt
        ))
    }

    func testParsesThePublishedAppConnectUri() throws {
        let parsed = try DashConnectUri.parseAppConnectRequest(AppConnectVector.requestUri)

        XCTAssertEqual(parsed.request, try AppConnectRequest.decode(AppConnectVector.requestBytes))
        XCTAssertEqual(parsed.network, .devnet)
        XCTAssertEqual(
            parsed.callback?.absoluteString,
            "https://yap.pr/connect?r=d77dc0da9df83a47755a15c42c5d9db9d7a7fd62")
    }

    func testParsesThePublishedRenewRequest() throws {
        let parsed = try DashConnectUri.parseAppConnectRequest(AppConnectVector.renewUri)

        XCTAssertEqual(parsed.request, try AppConnectRequest.decode(AppConnectVector.renewBytes))
        XCTAssertEqual(parsed.network, .testnet)
        XCTAssertNil(parsed.callback)
        XCTAssertTrue(parsed.request.isRenewal)
        XCTAssertEqual(parsed.request.identityHint, AppConnectVector.ownerId)
        XCTAssertEqual(parsed.request.authBindings.map(\.kind), [.contractGroup])
        XCTAssertEqual(parsed.request.encryptionBindings, [])
    }

    func testAVersion1UriIsUnsupportedByTheAppConnectParserAndViceVersa() throws {
        XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(try validKeyUri())) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .unsupported("URI version 1"))
        }
        // The version 1 parser measures the body before it reads the version,
        // so a full version 2 request is refused there for its length.
        XCTAssertThrowsError(try DashConnectUri.parseKeyRequest(AppConnectVector.requestUri)) { error in
            XCTAssertEqual(error as? DashConnectUriError, .bodyTooLong)
        }
        XCTAssertThrowsError(try DashConnectUri.parseKeyRequest(try validKeyUri(query: "n=t&v=2"))) { error in
            XCTAssertEqual(error as? DashConnectUriError, .unsupportedVersion)
        }
    }

    func testAppConnectUriQueryRules() {
        let base = AppConnectVector.renewUri
        // `n`, `v` and `cb` may each appear once; other parameters are ignored.
        XCTAssertNoThrow(try DashConnectUri.parseAppConnectRequest(base + "&x=1&x=2"))
        for repeated in ["&n=t", "&v=2", "&cb=https%3A%2F%2Fa.example&cb=https%3A%2F%2Fa.example"] {
            XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(base + repeated), repeated) { error in
                guard case .invalid = error as? AppConnectRequestError else { return XCTFail("\(error)") }
            }
        }
        for callback in [
            "http%3A%2F%2Fyap.pr%2Fconnect", "https%3A%2F%2Fuser%3Apw%40yap.pr%2F", "https%3A%2F%2Fuser%40yap.pr%2F",
            // Credentials that do not decode as text are still credentials.
            "https%3A%2F%2F%25FF%40yap.pr%2F", "https%3A%2F%2Fyap.pr%25FF%40evil.example%2F",
            "https%3A%2F%2Fyap.pr%25FF%3A%25FF%40evil.example%2F",
            "yap.pr%2Fconnect", "https%3A%2F%2Fyap.pr%2F" + String(repeating: "a", count: 513 - "https://yap.pr/".count),
        ] {
            XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(base + "&cb=" + callback), callback) { error in
                guard case .invalid = error as? AppConnectRequestError else { return XCTFail("\(error)") }
            }
        }
        XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(base.replacingOccurrences(of: "n=t", with: "n=x"))) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .invalid("unknown network"))
        }
    }

    func testAnOversizedAppConnectBodyIsRejectedBeforeDecoding() {
        // `0` is not a Base58 character: a length check that ran after the
        // decode would report that instead.
        let uri = "dash-key:" + String(repeating: "0", count: 1500) + "?n=t&v=2"
        XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(uri)) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .invalid("request is too long"))
        }
        XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest("dash-key:0?n=t&v=2")) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .invalid("request is not base58"))
        }
    }

    func testAnAppConnectPayloadAtTheCeilingIsReadAndOneOverIsNot() {
        // Padded with optional TLVs this decoder skips.
        let minimal = Self.appConnectHeader + Self.groupBinding + Self.createdAtTlv
        let padding = { (count: Int) -> Data in
            var data = Data()
            var left = count
            while left > 0 {
                let chunk = min(left, 257)
                data += Self.tlv(0x07, Data(repeating: 0, count: chunk - 2))
                left -= chunk
            }
            return data
        }
        let uri = { (payload: Data) in "dash-key:\(self.base58Encode(payload))?n=t&v=2" }

        XCTAssertNoThrow(try DashConnectUri.parseAppConnectRequest(uri(minimal + padding(1024 - minimal.count))))
        XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(uri(minimal + padding(1025 - minimal.count)))) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .invalid("request is too long"))
        }
    }

    func testAppConnectQueryIsFormDecodedBeforeItIsRead() throws {
        let body = String(AppConnectVector.renewUri.dropFirst("dash-key:".count).prefix { $0 != "?" })
        let parse = { (query: String) in try DashConnectUri.parseAppConnectRequest("dash-key:\(body)?\(query)") }

        XCTAssertEqual(try parse("%6E=t&%76=%32").network, .testnet)
        XCTAssertEqual(try parse("?n=t&v=2").network, .testnet)
        // An encoded name is still the same parameter.
        XCTAssertThrowsError(try parse("n=t&v=2&%76=1")) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .invalid("query parameter v is repeated"))
        }
        // A combining mark after a delimiter does not swallow it.
        XCTAssertEqual(try parse("v=2&\u{301}x=1&n=t").network, .testnet)

        // `+` is a space, which no parameter here may contain.
        XCTAssertEqual(try parse("n=t&v=2&cb=https://yap.pr/a-b").callback?.path, "/a-b")
        XCTAssertThrowsError(try parse("n=t&v=2&cb=https://yap.pr/a+b"))
        XCTAssertThrowsError(try parse("n=t&v=+2"))
        // Each sequence decodes on its own: the `%3F` here opens a query
        // even though `%FF` is not text, and the result is then not a URL
        // as written.
        XCTAssertEqual(try parse("n=t&v=2&cb=https://yap.pr/a%3Fr%3D1").callback?.query, "r=1")
        XCTAssertThrowsError(try parse("n=t&v=2&cb=https://yap.pr/a%3Fr%3D1%FF"))
        // A `%` without two hex digits stands as written, at the end too.
        XCTAssertThrowsError(try parse("n=t&v=2&cb=https://yap.pr/a%"))
        for version in ["%", "%4", ""] {
            XCTAssertThrowsError(try parse("n=t&v=" + version), version) { error in
                XCTAssertEqual(error as? AppConnectRequestError, .unsupported("URI version (unreadable)"))
            }
        }
        XCTAssertThrowsError(try parse("n=t&v=" + String(repeating: "9", count: 4))) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .unsupported("URI version (unreadable)"))
        }
    }

    func testAppConnectCallbackHostMustReadAsWritten() throws {
        let base = AppConnectVector.renewUri
        let exact = "https://yap.pr/" + String(repeating: "a", count: 512 - "https://yap.pr/".count)
        XCTAssertEqual(try DashConnectUri.parseAppConnectRequest(base + "&cb=" + exact).callback?.absoluteString, exact)

        // Decodes to `https://yap.pr%2F.evil.example/`: a host that only looks like yap.pr.
        for callback in ["https%3A%2F%2Fyap.pr%252F.evil.example%2F", "https%3A%2F%2Fyap.pr%2540evil.example%2F",
                         "https%3A%2F%2Fyap.pr%3A99999%2F", "https%3A%2F%2Fyap.pr%3A99999999999999999999%2F",
                         "https%3A%2F%2Fb%C3%BCcher.example%2F",
                         // Bracketed text reads back without its brackets.
                         "https%3A%2F%2F%5Byap.pr%5D%2F", "https%3A%2F%2F%5B%5D%2F", "https%3A%2F%2F%5Byap.pr%3Aevil.example%5D%2F",
                         // Addresses, in the spellings a browser takes.
                         "https%3A%2F%2F%5B%3A%3A1%5D%2F", "https%3A%2F%2F1.2.3.4%2F", "https%3A%2F%2F2130706433%2F",
                         "https%3A%2F%2F0x7f.1%2F", "https%3A%2F%2Ffoo.123%2F", "https%3A%2F%2F1.2.3.0x4%2F", "https%3A%2F%2F0x7f000001%2F",
                         // A browser lowercases the host: `paypaI.com` opens `paypai.com`.
                         "https%3A%2F%2FpaypaI.com%2F", "https%3A%2F%2FYAP.PR%2F",
                         "https%3A%2F%2Fyap..pr%2F", "https%3A%2F%2Fyap.pr.%2F", "https%3A%2F%2Fyap_pr.example%2F"] {
            XCTAssertThrowsError(try DashConnectUri.parseAppConnectRequest(base + "&cb=" + callback), callback)
        }
        // An international host is written in its ASCII form.
        XCTAssertEqual(
            try DashConnectUri.parseAppConnectRequest(base + "&cb=https%3A%2F%2Fxn--bcher-kva.example%3A8443%2F").callback?.port,
            8443)
    }

    // The renew request in pieces: header, then one TLV per element.
    private static let appConnectHeader = AppConnectVector.renewBytes.prefix(1 + 33 + 32 + 1 + 5)
    private static let groupBinding = tlv(0x02, Data([2, 1]) + AppConnectVector.groupId + u64(50_000_000_000) + u64(0))
    private static let createdAtTlv = tlv(0x06, u64(AppConnectVector.createdAt))

    private static func tlv(_ type: UInt8, _ value: Data) -> Data {
        Data([type, UInt8(value.count)]) + value
    }

    private static func u64(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func authBinding(kind: UInt8, level: UInt8, id: UInt8, budget: UInt64 = 1, tail: Data = Data()) -> Data {
        tlv(0x02, Data([kind, level]) + Data(repeating: id, count: 32) + u64(budget) + u64(0) + tail)
    }

    private func decodeAppConnect(_ parts: Data...) throws -> AppConnectRequest {
        try AppConnectRequest.decode(parts.reduce(Self.appConnectHeader, +))
    }

    private func assertInvalid(_ parts: Data..., file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AppConnectRequest.decode(parts.reduce(Self.appConnectHeader, +)), file: file, line: line) { error in
            guard case .invalid = error as? AppConnectRequestError else {
                return XCTFail("expected invalid, got \(error)", file: file, line: line)
            }
        }
    }

    private func assertUnsupported(_ parts: Data..., file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AppConnectRequest.decode(parts.reduce(Self.appConnectHeader, +)), file: file, line: line) { error in
            guard case .unsupported = error as? AppConnectRequestError else {
                return XCTFail("expected unsupported, got \(error)", file: file, line: line)
            }
        }
    }

    func testTheSmallestAppConnectRequestDecodes() throws {
        let request = try decodeAppConnect(Self.groupBinding, Self.createdAtTlv)
        XCTAssertEqual(request.authBindings.count, 1)
        XCTAssertNil(request.authBindings[0].expiresAt)
        XCTAssertNil(request.identityHint)
        XCTAssertNil(request.connectionId)
        XCTAssertFalse(request.isRenewal)
    }

    func testUnknownOddTlvsAreSkippedAndUnknownEvenOnesRefuse() throws {
        // 0x07 and 0x09 are unknown and optional; 0x07 may even repeat.
        let request = try decodeAppConnect(
            Self.groupBinding, Self.createdAtTlv,
            Self.tlv(0x07, Data([1])), Self.tlv(0x07, Data()), Self.tlv(0x09, Data([1, 2, 3])))
        XCTAssertEqual(request, try decodeAppConnect(Self.groupBinding, Self.createdAtTlv))

        assertUnsupported(Self.groupBinding, Self.createdAtTlv, Self.tlv(0x08, Data()))
        // An unknown binding kind is a newer format too.
        assertUnsupported(Self.authBinding(kind: 3, level: 2, id: 1), Self.createdAtTlv)
        // So is another body version.
        XCTAssertThrowsError(try AppConnectRequest.decode(Data([0x03]) + Self.appConnectHeader.dropFirst())) { error in
            XCTAssertEqual(error as? AppConnectRequestError, .unsupported("request version 3"))
        }
    }

    func testAnUnknownMandatoryPartOutranksABrokenRule() {
        let badLevel = Self.authBinding(kind: 0, level: 1, id: 1)
        let unknownKind = Self.authBinding(kind: 7, level: 2, id: 2)
        let unknownTlv = Self.tlv(0x08, Data())
        let encryption = { (purpose: UInt8) in Self.tlv(0x04, Data(repeating: 1, count: 32) + Data([purpose])) }

        // Alone, each of these is a broken rule...
        assertInvalid(badLevel, Self.createdAtTlv)
        assertInvalid(Self.groupBinding, encryption(3), Self.createdAtTlv)
        // ...and still a newer format when something unknown follows.
        assertUnsupported(badLevel, Self.createdAtTlv, unknownTlv)
        assertUnsupported(badLevel, unknownKind)
        assertUnsupported(Self.groupBinding, Self.groupBinding, Self.createdAtTlv, unknownTlv)
        assertUnsupported(Self.groupBinding, encryption(3), Self.createdAtTlv, unknownTlv)
        assertUnsupported(Self.authBinding(kind: 2, level: 1, id: 1, budget: 0), Self.createdAtTlv, unknownTlv)

        let offCurve = Data([0x02]) + Data([0x02]) + Data(repeating: 0xFF, count: 32) + AppConnectVector.appId
        let badLabel = Data([3]) + Data("a\nb".utf8)
        XCTAssertThrowsError(try AppConnectRequest.decode(
            offCurve + badLabel + Self.groupBinding + Self.createdAtTlv + unknownTlv)) { error in
                guard case .unsupported = error as? AppConnectRequestError else { return XCTFail("\(error)") }
            }
        let name = { (text: String) in Data([UInt8(text.utf8.count)]) + Data(text.utf8) }
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: name("pro file")), Self.createdAtTlv)
        assertUnsupported(Self.authBinding(kind: 1, level: 2, id: 1, tail: name("pro file")), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.groupBinding, encryption(1), encryption(1), Self.createdAtTlv)
        assertUnsupported(Self.groupBinding, encryption(1), encryption(1), Self.createdAtTlv, unknownTlv)

        // What is checked as each TLV is read stays a broken rule, whatever follows.
        let single = { (id: UInt8) in Self.authBinding(kind: 0, level: 2, id: id) }
        assertInvalid(Self.groupBinding, Self.tlv(0x05, Data([1, 1])), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x05, Data([2])), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x06, Self.u64(0)), unknownTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x06, Self.u64(1 << 53)), unknownTlv)
        assertInvalid(
            Self.tlv(0x02, Data([2, 1]) + AppConnectVector.groupId + Self.u64(1) + Self.u64(1 << 53)),
            Self.createdAtTlv, unknownTlv)
        assertInvalid(single(1), single(2), single(3), single(4), single(5), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.groupBinding, encryption(1), encryption(2), encryption(1), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: Data([3]) + Data("ab".utf8)), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: Data([1, 0xFF])), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.authBinding(kind: 0, level: 2, id: 1, tail: name("profile")), Self.createdAtTlv, unknownTlv)
        assertInvalid(Self.createdAtTlv, Self.groupBinding, unknownTlv)
    }

    func testAppConnectTextAndTimestampEdges() throws {
        let header = { (label: Data) in
            Data([0x02]) + AppConnectVector.appEphemeralPubKey + AppConnectVector.appId + Data([UInt8(label.count)]) + label
        }
        let tail = Self.groupBinding + Self.createdAtTlv
        let name = { (bytes: Data) in Data([UInt8(bytes.count)]) + bytes }

        // A leading BOM stays part of the label.
        let withBom = try AppConnectRequest.decode(header(Data([0xEF, 0xBB, 0xBF]) + Data("Yappr".utf8)) + tail)
        XCTAssertEqual(withBom.label.unicodeScalars.first, "\u{FEFF}")
        // A document type name is ASCII; a BOM in front is not.
        assertInvalid(
            Self.authBinding(kind: 1, level: 2, id: 1, tail: name(Data([0xEF, 0xBB, 0xBF]) + Data("profile".utf8))),
            Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: name(Data([0xFF]))), Self.createdAtTlv)

        // The largest timestamp the reference codec can hold.
        let last = try decodeAppConnect(Self.groupBinding, Self.tlv(0x06, Self.u64((1 << 53) - 1)))
        XCTAssertEqual(last.createdAt, (1 << 53) - 1)
        assertInvalid(
            Self.tlv(0x02, Data([2, 1]) + AppConnectVector.groupId + Self.u64(1) + Self.u64(1 << 53)),
            Self.createdAtTlv)
    }

    func testAppConnectTlvOrderAndCountRules() {
        let hint = Self.tlv(0x01, Data(repeating: 7, count: 32))
        let connection = Self.tlv(0x03, Data(repeating: 7, count: 16))
        let mode = Self.tlv(0x05, Data([1]))

        // Out of order.
        assertInvalid(Self.groupBinding, hint, Self.createdAtTlv)
        assertInvalid(Self.createdAtTlv, Self.groupBinding)
        // A known singleton twice.
        assertInvalid(hint, hint, Self.groupBinding, Self.createdAtTlv)
        assertInvalid(Self.groupBinding, connection, connection, Self.createdAtTlv)
        assertInvalid(Self.groupBinding, mode, mode, Self.createdAtTlv)
        assertInvalid(Self.groupBinding, Self.createdAtTlv, Self.createdAtTlv)
        // The required ones missing.
        assertInvalid(Self.groupBinding)
        assertInvalid(Self.createdAtTlv)
        // Too many bindings, or the same one twice.
        assertInvalid(
            Self.authBinding(kind: 0, level: 2, id: 1), Self.authBinding(kind: 0, level: 2, id: 2),
            Self.authBinding(kind: 0, level: 2, id: 3), Self.authBinding(kind: 0, level: 2, id: 4),
            Self.authBinding(kind: 0, level: 2, id: 5), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 0, level: 2, id: 1), Self.authBinding(kind: 0, level: 2, id: 1), Self.createdAtTlv)
        let encryption = { (id: UInt8, purpose: UInt8) in Self.tlv(0x04, Data(repeating: id, count: 32) + Data([purpose])) }
        assertInvalid(Self.groupBinding, encryption(1, 1), encryption(1, 2), encryption(2, 1), Self.createdAtTlv)
        assertInvalid(Self.groupBinding, encryption(1, 1), encryption(1, 1), Self.createdAtTlv)
        XCTAssertNoThrow(try decodeAppConnect(Self.groupBinding, encryption(1, 1), encryption(1, 2), Self.createdAtTlv))
    }

    func testAppConnectTlvValueRules() {
        // Wrong lengths of the fixed-size values.
        assertInvalid(Self.tlv(0x01, Data(repeating: 7, count: 31)), Self.groupBinding, Self.createdAtTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x03, Data(repeating: 7, count: 17)), Self.createdAtTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x04, Data(repeating: 7, count: 32)), Self.createdAtTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x06, Data(repeating: 1, count: 7)))
        // Values outside what is defined.
        assertInvalid(Self.groupBinding, Self.tlv(0x04, Data(repeating: 7, count: 32) + Data([3])), Self.createdAtTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x05, Data([2])), Self.createdAtTlv)
        assertInvalid(Self.groupBinding, Self.tlv(0x06, Self.u64(0)))
        assertInvalid(Self.groupBinding, Self.tlv(0x06, Self.u64(1 << 53)))
        // A TLV running past the end, and a lone type byte.
        assertInvalid(Self.groupBinding, Self.createdAtTlv.dropLast())
        assertInvalid(Self.groupBinding, Self.createdAtTlv, Data([0x07]))
    }

    func testAppConnectAuthBindingRules() throws {
        let name = { (text: String) in Data([UInt8(text.utf8.count)]) + Data(text.utf8) }

        // CRITICAL only on a contract group; nothing but CRITICAL and HIGH.
        XCTAssertNoThrow(try decodeAppConnect(Self.authBinding(kind: 2, level: 2, id: 1), Self.createdAtTlv))
        assertInvalid(Self.authBinding(kind: 0, level: 1, id: 1), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 1, id: 1, tail: name("profile")), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 2, level: 0, id: 1), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 2, level: 3, id: 1), Self.createdAtTlv)
        // A contract group always carries a budget; the others need not.
        assertInvalid(Self.authBinding(kind: 2, level: 1, id: 1, budget: 0), Self.createdAtTlv)
        let unlimited = try decodeAppConnect(Self.authBinding(kind: 0, level: 2, id: 1, budget: 0), Self.createdAtTlv)
        XCTAssertNil(unlimited.authBindings[0].totalBudget)
        // The name belongs to documentType, and only there.
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: Data([0])), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: Data([3]) + Data("ab".utf8)), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: name("pro file")), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 1, level: 2, id: 1, tail: name(String(repeating: "a", count: 65))), Self.createdAtTlv)
        assertInvalid(Self.authBinding(kind: 0, level: 2, id: 1, tail: name("profile")), Self.createdAtTlv)
        // Two types of one contract are two bindings.
        let two = try decodeAppConnect(
            Self.authBinding(kind: 1, level: 2, id: 1, tail: name("a")),
            Self.authBinding(kind: 1, level: 2, id: 1, tail: name("b")), Self.createdAtTlv)
        XCTAssertEqual(two.authBindings.map(\.documentTypeName), ["a", "b"])
        // Truncated.
        assertInvalid(Self.tlv(0x02, Data([0, 2]) + Data(repeating: 1, count: 32)), Self.createdAtTlv)
    }

    func testAppConnectHeaderRules() {
        let tail = Self.groupBinding + Self.createdAtTlv
        let key = AppConnectVector.appEphemeralPubKey
        let header = { (key: Data, label: Data) -> Data in
            var data = Data([0x02])
            data.append(key)
            data.append(AppConnectVector.appId)
            data.append(UInt8(label.count))
            data.append(label)
            return data
        }
        let decode = { (data: Data) in try AppConnectRequest.decode(data) }
        let offCurveKey: Data = Data([0x02]) + Data(repeating: 0xFF, count: 32)
        let overrunningLabel: Data = header(key, Data()).dropLast() + Data([5]) + Data("ab".utf8)

        XCTAssertNoThrow(try decode(header(key, Data("Ünï".utf8)) + tail))
        let invalidBodies: [Data] = [
            Data(),
            Data(header(key, Data()).dropLast()),
            // Not a point on the curve.
            header(offCurveKey, Data()) + tail,
            // A label over 64 bytes, one running past the end, and malformed UTF-8.
            header(key, Data(repeating: 0x41, count: 65)) + tail,
            overrunningLabel,
            header(key, Data([0xC3, 0x28])) + tail,
            // Overlong and surrogate encodings are not UTF-8.
            header(key, Data([0xC0, 0xAF])) + tail,
            header(key, Data([0xED, 0xA0, 0x80])) + tail,
        ]
        for (index, body) in invalidBodies.enumerated() {
            XCTAssertThrowsError(try decode(body), "body \(index)") { error in
                guard case .invalid = error as? AppConnectRequestError else { return XCTFail("body \(index): \(error)") }
            }
        }
        // Characters a label could disguise itself with.
        for forbidden in ["a\u{0}b", "a\nb", "a\u{7F}b", "a\u{85}b", "a\u{202E}b", "a\u{200F}b", "a\u{2066}b", "a\u{061C}b"] {
            XCTAssertThrowsError(try decode(header(key, Data(forbidden.utf8)) + tail), forbidden) { error in
                XCTAssertEqual(
                    error as? AppConnectRequestError,
                    .invalid("label contains control or bidirectional formatting characters"))
            }
        }
    }

    func testAppConnectRequestAge() throws {
        let request = try AppConnectRequest.decode(AppConnectVector.requestBytes)
        let created = Date(timeIntervalSince1970: TimeInterval(AppConnectVector.createdAt) / 1000)

        XCTAssertEqual(request.age(now: created), .fresh)
        XCTAssertEqual(request.age(now: created.addingTimeInterval(10 * 60)), .fresh)
        XCTAssertEqual(request.age(now: created.addingTimeInterval(10 * 60 + 1)), .stale)
        XCTAssertEqual(request.age(now: created.addingTimeInterval(-2 * 60)), .fresh)
        XCTAssertEqual(request.age(now: created.addingTimeInterval(-2 * 60 - 1)), .future)
    }
}

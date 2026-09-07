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
}

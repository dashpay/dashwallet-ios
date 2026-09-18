import XCTest
@testable import dashpay

/// Wire format of the Bluetooth login handoff. The pairing-code and layout
/// vectors are the ones the browser (Yappr) and the platform SwiftExampleApp
/// pin as well, so a drift on any side shows up as a red test.
final class BrowserLoginBleProtocolTests: XCTestCase {
    private let appPrivateKey = Data(repeating: 0x11, count: 32)
    private let contractId = Data(repeating: 0x44, count: 32)
    private let identityId = Data(repeating: 0x33, count: 32)

    private var appPublicKey: Data {
        try! Secp256k1.compressedPublicKey(privateKey: appPrivateKey)
    }

    func testRequestRoundTripsThroughTheDashKeyRequestShape() throws {
        let request = DashKeyRequest(
            appEphemeralPubKey: appPublicKey,
            contractId: contractId,
            label: "Login to Yappr",
            network: .devnet
        )
        let bytes = try BrowserLoginBleProtocol.serializeRequest(request)
        XCTAssertEqual(bytes.count, 1 + 1 + 33 + 32 + 1 + 14)
        XCTAssertEqual(bytes[0], 1)
        XCTAssertEqual(bytes[1], UInt8(ascii: "d"))
        XCTAssertEqual(try BrowserLoginBleProtocol.parseRequest(bytes), request)
    }

    func testRequestRejectsWrongVersionUnknownNetworkAndBadPoint() throws {
        var bytes = try BrowserLoginBleProtocol.serializeRequest(DashKeyRequest(
            appEphemeralPubKey: appPublicKey, contractId: contractId, label: "x", network: .testnet))

        bytes[0] = 2
        XCTAssertThrowsError(try BrowserLoginBleProtocol.parseRequest(bytes)) {
            XCTAssertEqual($0 as? BrowserLoginBleProtocol.ProtocolError, .unsupportedVersion(2))
        }
        bytes[0] = 1

        bytes[1] = UInt8(ascii: "z")
        XCTAssertThrowsError(try BrowserLoginBleProtocol.parseRequest(bytes)) {
            XCTAssertEqual($0 as? BrowserLoginBleProtocol.ProtocolError, .unknownNetwork(UInt8(ascii: "z")))
        }
        bytes[1] = UInt8(ascii: "t")

        bytes[2] = 0x05
        XCTAssertThrowsError(try BrowserLoginBleProtocol.parseRequest(bytes)) {
            XCTAssertEqual($0 as? BrowserLoginBleProtocol.ProtocolError, .invalidEphemeralPublicKey)
        }

        XCTAssertThrowsError(try BrowserLoginBleProtocol.parseRequest(Data(repeating: 1, count: 10))) {
            XCTAssertEqual($0 as? BrowserLoginBleProtocol.ProtocolError, .truncatedRequest)
        }
    }

    func testPairingCodeMatchesTheBrowserVector() throws {
        XCTAssertEqual(appPublicKey.hexEncodedString(), "034f355bdcb7cc0af728ef3cceb9615d90684bb5b2ca5f859ab0f0b704075871aa")
        XCTAssertEqual(try BrowserLoginBleProtocol.pairingCode(for: appPublicKey), "350178")
    }

    func testResponseRoundTripsAndEncodesAbsentLimitsAsZero() throws {
        let response = BrowserLoginBleProtocol.Response(
            identityId: identityId,
            walletEphemeralPublicKey: appPublicKey,
            encryptedPayload: Data((0 ..< 60).map { UInt8($0) }),
            keyId: 0x0102_0304,
            expiresAt: 1_800_000_000_000,
            totalBudget: nil
        )
        let bytes = try response.serialized()
        XCTAssertEqual(bytes.count, BrowserLoginBleProtocol.Response.length)
        XCTAssertEqual(Array(bytes[126 ..< 130]), [1, 2, 3, 4])
        XCTAssertEqual(Array(bytes[138 ..< 146]), [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(try BrowserLoginBleProtocol.Response.parse(bytes), response)
    }

    func testResponseRefusesMalformedFields() {
        let short = BrowserLoginBleProtocol.Response(
            identityId: Data(repeating: 0, count: 31),
            walletEphemeralPublicKey: appPublicKey,
            encryptedPayload: Data(repeating: 0, count: 60),
            keyId: 1, expiresAt: nil, totalBudget: nil)
        XCTAssertThrowsError(try short.serialized())
    }

    func testSealedLoginKeyOpensWithTheBrowsersKeys() throws {
        let walletPrivateKey = Data(repeating: 0x22, count: 32)
        let walletPublicKey = try Secp256k1.compressedPublicKey(privateKey: walletPrivateKey)
        let loginKey = Data(repeating: 0x55, count: 32)

        let sealed = try KeyExchangeCrypto.encryptLoginKey(
            loginKey, walletEphemeralPriv: walletPrivateKey, appEphemeralPub: appPublicKey)
        let opened = try KeyExchangeCrypto.decryptLoginKey(
            sealed, walletEphemeralPriv: appPrivateKey, appEphemeralPub: walletPublicKey)
        XCTAssertEqual(opened, loginKey)

        // HKDF-SHA256(ikm = 0x55 * 32, salt = 0x33 * 32, info = "auth"), the
        // browser's derivation of the key the wallet registers.
        let authKey = try KeyExchangeCrypto.deriveAuthPrivateKey(loginKey: loginKey, identityId: identityId)
        XCTAssertEqual(authKey.hexEncodedString(), "6f0aa5dd9454cb33b8a96b93a4d3b8936ce81bd8d2b9e054dee938f59c022e35")
    }

    func testLimitsExpiryIsMillisecondsFromNow() {
        let limits = BrowserLoginKeyLimits(totalBudget: 1_000_000_000, lifetime: 3_600)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(limits.expiresAt(from: now), 1_700_003_600_000)
    }
}

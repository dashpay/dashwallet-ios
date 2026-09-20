import XCTest
@testable import dashpay

/// Wire format of the Bluetooth login handoff. The pairing-code and layout
/// vectors are the ones the browser (Yappr) and the platform SwiftExampleApp
/// pin as well, so a drift on any side shows up as a red test.
final class BrowserLoginBleProtocolTests: XCTestCase {
    private let appPrivateKey = Data(repeating: 0x11, count: 32)
    private let contractId = Data(repeating: 0x44, count: 32)
    private let identityId = Data(repeating: 0x33, count: 32)
    private let pairingNonce = Data(repeating: 0x77, count: 32)

    private var appPublicKey = Data()

    // Derived in setUp rather than a computed property: `force_try` is enabled
    // at error severity and the Xcode lint phase runs over this target, so a
    // `try!` here can fail the build. A throw surfaces as a test error instead.
    override func setUpWithError() throws {
        try super.setUpWithError()
        appPublicKey = try Secp256k1.compressedPublicKey(privateKey: appPrivateKey)
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
        XCTAssertEqual(
            try BrowserLoginBleProtocol.pairingCommitment(nonce: pairingNonce).hexEncodedString(),
            "107705455ec941a76431097d33ec3de9fdbca6046bc85d16863a74ae2db1b185")
        XCTAssertEqual(
            try BrowserLoginBleProtocol.pairingCode(nonce: pairingNonce, requestBytes: try sampleRequestBytes()),
            "968149")
    }

    /// The whole point of hashing the request rather than the ephemeral key:
    /// a relay that rewrites the label the wallet is about to show cannot
    /// keep the digits the browser displays.
    func testPairingCodeCoversEveryByteOfTheRequest() throws {
        var tampered = try sampleRequestBytes()
        tampered[tampered.count - 1] = UInt8(ascii: "q")
        XCTAssertEqual(
            try BrowserLoginBleProtocol.pairingCode(nonce: pairingNonce, requestBytes: tampered),
            "135490")
    }

    func testPairingCodeAndCommitmentRefuseAMissizedNonce() {
        let short = Data(repeating: 0x77, count: 31)
        XCTAssertThrowsError(try BrowserLoginBleProtocol.pairingCommitment(nonce: short))
        XCTAssertThrowsError(try BrowserLoginBleProtocol.pairingCode(nonce: short, requestBytes: Data()))
    }

    func testSessionValueRoundTripsAndRefusesUnknownStages() throws {
        let reveal = BrowserLoginBleProtocol.SessionValue(stage: .reveal, payload: pairingNonce)
        var bytes = try BrowserLoginBleProtocol.serializeSession(reveal)
        XCTAssertEqual(bytes.count, 2 + 32)
        XCTAssertEqual(try BrowserLoginBleProtocol.parseSession(bytes), reveal)

        let ack = BrowserLoginBleProtocol.SessionValue(stage: .received, payload: Data())
        XCTAssertEqual(try BrowserLoginBleProtocol.parseSession(try BrowserLoginBleProtocol.serializeSession(ack)), ack)

        bytes[1] = 9
        XCTAssertThrowsError(try BrowserLoginBleProtocol.parseSession(bytes)) {
            XCTAssertEqual($0 as? BrowserLoginBleProtocol.ProtocolError, .unknownSessionStage(9))
        }
        XCTAssertThrowsError(try BrowserLoginBleProtocol.parseSession(Data([1]))) {
            XCTAssertEqual($0 as? BrowserLoginBleProtocol.ProtocolError, .truncatedRequest)
        }
    }

    private func sampleRequestBytes() throws -> Data {
        try BrowserLoginBleProtocol.serializeRequest(DashKeyRequest(
            appEphemeralPubKey: appPublicKey,
            contractId: contractId,
            label: "Login to Yappr",
            network: .devnet
        ))
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

/// The peripheral's session bookkeeping — the half of it that never touches
/// CoreBluetooth, so it can be exercised without a radio. Lives next to the
/// protocol tests because it is the same handshake seen from the wallet side.
@MainActor
final class BrowserLoginPeripheralSessionTests: XCTestCase {
    private func makePeripheral() -> BrowserLoginPeripheral {
        let peripheral = BrowserLoginPeripheral(localName: "Dash Wallet")
        peripheral.prepareSession()
        return peripheral
    }

    func testSessionServesTheCommitmentUntilARequestIsAccepted() throws {
        let peripheral = makePeripheral()

        let before = try BrowserLoginBleProtocol.parseSession(peripheral.sessionValueBytes())
        XCTAssertEqual(before.stage, .commitment)
        XCTAssertEqual(before.payload, try BrowserLoginBleProtocol.pairingCommitment(nonce: peripheral.pairingNonce))
        XCTAssertNotEqual(before.payload, peripheral.pairingNonce)

        peripheral.revealPairingNonce()
        let after = try BrowserLoginBleProtocol.parseSession(peripheral.sessionValueBytes())
        XCTAssertEqual(after.stage, .reveal)
        XCTAssertEqual(after.payload, peripheral.pairingNonce)
    }

    func testEachSessionDrawsItsOwnNonce() {
        let peripheral = makePeripheral()
        let first = peripheral.pairingNonce
        peripheral.prepareSession()
        XCTAssertEqual(first.count, BrowserLoginBleProtocol.pairingNonceLength)
        XCTAssertNotEqual(first, peripheral.pairingNonce)
    }

    func testAcknowledgementOnlyCountsOnceThereIsAResponseToRead() throws {
        let peripheral = makePeripheral()
        let ack = try BrowserLoginBleProtocol.serializeSession(
            BrowserLoginBleProtocol.SessionValue(stage: .received, payload: Data()))

        // Nothing to read yet: a central cannot unlock the screen early.
        peripheral.acknowledge(sessionWrite: ack)
        XCTAssertFalse(peripheral.responseWasAcknowledged)

        peripheral.deliver(response: Data(repeating: 0xAB, count: BrowserLoginBleProtocol.Response.length))
        XCTAssertFalse(peripheral.responseWasAcknowledged)

        peripheral.acknowledge(sessionWrite: Data([1, 0]))
        XCTAssertFalse(peripheral.responseWasAcknowledged, "a commitment write is not an acknowledgement")

        peripheral.acknowledge(sessionWrite: ack)
        XCTAssertTrue(peripheral.responseWasAcknowledged)
    }

    /// The regression behind "Deny tells the browser nothing": `decline()`
    /// used to set the status and stop in the same turn, which threw the
    /// notification away with the characteristic.
    func testFinishSessionKeepsTheServiceUpForTheTerminalStatus() {
        let peripheral = makePeripheral()
        peripheral.revealPairingNonce()

        peripheral.finishSession(status: .rejected)

        XCTAssertEqual(peripheral.status, .rejected)
        XCTAssertFalse(peripheral.pairingNonce.isEmpty, "the session is still up during the grace window")
        XCTAssertFalse(peripheral.sessionValueBytes().isEmpty)
    }

    func testStoppingClearsTheSession() throws {
        let peripheral = makePeripheral()
        peripheral.revealPairingNonce()
        peripheral.deliver(response: Data(repeating: 0xAB, count: 8))
        peripheral.acknowledge(sessionWrite: try BrowserLoginBleProtocol.serializeSession(
            BrowserLoginBleProtocol.SessionValue(stage: .received, payload: Data())))

        peripheral.stop()

        XCTAssertTrue(peripheral.pairingNonce.isEmpty)
        XCTAssertTrue(peripheral.sessionValueBytes().isEmpty)
        XCTAssertFalse(peripheral.responseWasAcknowledged)
        XCTAssertEqual(peripheral.status, .idle)
    }
}

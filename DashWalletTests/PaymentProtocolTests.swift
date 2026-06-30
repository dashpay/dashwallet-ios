//
//  PaymentProtocolTests.swift
//  DashWalletTests
//
//  Tests for the app-side BIP70 protocol core (L1 codec + L2 verifier).
//  Self-contained: the signed PaymentRequest fixture is embedded (captured from the
//  bip70-dash test server, see BIP70_TESTING.md), so no network/server is required.
//
//  NOTE: the DashWalletTests target is currently compile-gated; if it won't build, the
//  identical assertions run via the standalone manual harness (swiftc). See the manual
//  runner referenced in the BIP70 work.
//

import XCTest
import Security
import SwiftDashSDK
@testable import dashwallet

final class PaymentProtocolTests: XCTestCase {

    // A real x509+sha256-signed PaymentRequest (1175 bytes) from the test server:
    // network "test", one 0.001-DASH P2PKH output, merchant "Dash Sticker Shop".
    private static let signedRequestBase64 =
        "CAESC3g1MDkrc2hhMjU2GocGCoQGMIIDADCCAeigAwIBAgIJeF8eUl2va/tEMA0GCSqGSIb3DQEBCwUAMBwxGjAYBgNVBAMTEURhc2ggU3RpY2tlciBTaG9wMB4XDTI2MDYyOTA3MTI0MFoXDTI3MDYyOTA3MTI0MFowHDEaMBgGA1UEAxMRRGFzaCBTdGlja2VyIFNob3AwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCxelYthVoRtoiGR1BQ2tHnpw234RPUh6IIpx9u+Hikp8z2Ekk2NBqiFIPDi8Kd1RitITVn+/weivGJxOQ9K7iThUbHn8mw+iCIxWCMaWHUD+e2us2bDNgazibs7tpmaXTjK2vAcAgDRVBnlqiJG9i8+dE0nRynF5d8Yk8pzb9Nue4J5vkMYAYQ1tcuT2Lx2gTWDDOENyDW155TCjOmO9TkkCZkTQSYYV2YPKtEV8vaD/mtFDx6uhnYgxfqz4n1eK+a1gn1BYCRSI/KMugWU1Wk1caAkAB5fx7IeLIQU6rKz0kkyisVvaPfsnTdrHdeED+jrPWs/qyeQAuFB3fIvA+jAgMBAAGjRTBDMAwGA1UdEwQFMAMBAf8wCwYDVR0PBAQDAgL0MCYGA1UdEQQfMB2GG2h0dHA6Ly9leGFtcGxlLm9yZy93ZWJpZCNtZTANBgkqhkiG9w0BAQsFAAOCAQEAdyHL0WUTIyg8iwUQchYF4iS11Z6Qd9vmxD5wudeMDBfq6tJiIDfEvl1npnPogPo55EcmWBdwQWpaiV9sltCa+Y49JoOM65i/i+PjBWD3E9h0mAdNapm0yR/BgcyY+Co8LaIFnYo/9r3KV/OE7kOIVsQ2dcOgOn0sgCiPJSInHVXLQTjJUA53wlbibEzamA+GJxHHdvh2xgi+60tU0aCY+tp8OXN6bmaOZ9zXAd9HUhMJJRbCgvCFuz1UDz+pPbMA2KoY5MAJM7BvBVJe5x7tP6QuFqjHf0iL6v4tzIRZ2cOoGo/pkUfQAQBd420mNdirWDqkO9lktMwp7uJaHEKgeCJ5CgR0ZXN0Eh8IoI0GEhl2qRSqtEY2Cr6XL2tidvN0YYb+gsq9G4isGL3giNIGIM38iNIGKhlEYXNoIFN0aWNrZXIgLSAwLjAwMSBEQVNIMiZodHRwOi8vMTkyLjE2OC4wLjEwODozMDAwL3BheW1lbnQ/aWQ9MDoBMCqAAlyRLFTXZxc64H7iEoivPI4IEHQXSgfaQ0tFzK5piIXOv1Bb/Prk40GUhJcfJjk+WAZvxLFDwDg++KcWPTaMSF9797v5tFoGUfKAE1RldXUZekcB/r7eVuyYDpbmbTQKiNIGKLUi5FBmDN+3w2nS3zSwat9/ozel+iPNyaalJ2YYY2GcWnmtMVSAER2drCviPngYiY0bXDSx3t6/qyMTXLbAJo6J2NJr2+UeDXMsnBmq76x6+XFvA4vu7LKZf/86W+dgUgsiHW9GDDS+Xizm9qzaTbMukRHwfdFUxbUMcucz/Oltq17YxiXeBWIuWJ9AXdkzaMmko201pYltiQvQxO8="

    private var fixture: Data { Data(base64Encoded: Self.signedRequestBase64)! }

    // MARK: - L1 codec / messages

    func testDecodeFields() throws {
        let req = try XCTUnwrap(PaymentRequest(fixture))
        XCTAssertEqual(req.pkiType, "x509+sha256")
        XCTAssertEqual(req.version, 1)
        XCTAssertEqual(req.signature?.count, 256) // RSA-2048
        let d = req.details
        XCTAssertEqual(d.network, "test")
        XCTAssertEqual(d.outputs.count, 1)
        XCTAssertEqual(d.outputs.first?.amount, 100_000) // 0.001 DASH
        XCTAssertEqual(d.outputs.first?.script.count, 25) // P2PKH
        XCTAssertEqual(d.memo, "Dash Sticker - 0.001 DASH")
        XCTAssertEqual(d.paymentURL?.contains("/payment"), true)
    }

    func testRoundTripIdentity() throws {
        let req = try XCTUnwrap(PaymentRequest(fixture))
        XCTAssertEqual(req.encoded(), fixture, "full re-encode must reproduce the original bytes")
    }

    func testEmptySignatureFieldIsEmitted() throws {
        let req = try XCTUnwrap(PaymentRequest(fixture))
        // The empty-but-present signature field is exactly two bytes longer than omitting it: 0x2a 0x00.
        let withEmpty = req.encoded(signature: Data())
        let omitted = req.encoded(signature: nil)
        XCTAssertEqual(withEmpty.count, omitted.count + 2)
        XCTAssertEqual(withEmpty.suffix(2), Data([0x2a, 0x00]))
    }

    func testOutputGoldenBytes() {
        let out = PaymentOutput(amount: 5, script: Data([0xaa]))
        // amount(1,varint)=08 05 ; script(2,len-delim)=12 01 aa
        XCTAssertEqual(out.encoded(), Data([0x08, 0x05, 0x12, 0x01, 0xaa]))
    }

    func testVarintRoundTrip() {
        for value: UInt64 in [0, 1, 127, 128, 300, 16_384, UInt64.max] {
            var writer = ProtoWriter()
            writer.appendVarInt(value)
            var reader = ProtoReader(writer.data)
            XCTAssertEqual(reader.readVarInt(), value, "varint round-trip failed for \(value)")
        }
    }

    func testReaderTruncatedVarintYieldsZero() {
        // A lone continuation byte (high bit set, buffer ends) decodes to 0, matching the reference.
        var reader = ProtoReader(Data([0x80]))
        XCTAssertEqual(reader.readVarInt(), 0)
    }

    func testWireReaderRejectsOversizedLengthWithoutTrapping() {
        // A length-delimited field (field 4, wire type 2) whose declared length exceeds the buffer
        // — and Int.max — must yield a nil payload and consume the buffer, never trap on Int(UInt64).
        var writer = ProtoWriter()
        writer.appendVarInt(UInt64(4 << 3 | 2)) // key: field 4, wire type 2
        writer.appendVarInt(UInt64.max)         // hostile declared length
        var bytes = writer.data
        bytes.append(0xAA)                       // far fewer bytes than declared
        var reader = ProtoReader(bytes)
        let field = reader.readField()
        XCTAssertNil(field?.data)
        XCTAssertTrue(reader.isAtEnd)
        // End-to-end: a PaymentRequest with this malformed details field decodes to nil, no crash.
        XCTAssertNil(PaymentRequest(bytes))
    }

    func testWireReaderRejectsOversizedFieldKey() {
        // A field key/tag larger than Int.max must not trap when split into field number + wire type.
        var writer = ProtoWriter()
        writer.appendVarInt(UInt64.max)
        var reader = ProtoReader(writer.data)
        _ = reader.readField() // reaching the assertion without trapping is the test
        XCTAssertTrue(reader.isAtEnd)
    }

    // MARK: - L2 verifier (crypto)

    func testRealSignatureVerifiesWithCertKey() throws {
        // The load-bearing test: the real merchant signature verifies over our empty-signature
        // re-encode → proves the codec is byte-exact AND the RSA-PKCS1v15-SHA256 path is correct.
        let req = try XCTUnwrap(PaymentRequest(fixture))
        let leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, X509Certificates(req.pkiData!).certificates[0] as CFData))
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &trust), errSecSuccess)
        let publicKey = try XCTUnwrap(SecTrustCopyKey(try XCTUnwrap(trust)))
        let signedBytes = req.encoded(signature: Data())
        var error: Unmanaged<CFError>?
        let valid = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                          signedBytes as CFData, req.signature! as CFData, &error)
        XCTAssertTrue(valid, "real signature must verify against the cert public key")
    }

    func testChainValidatesWhenAnchored() throws {
        // The self-signed chain is sound: it validates once trusted (so in-app isValid==true
        // after the user installs the cert).
        let req = try XCTUnwrap(PaymentRequest(fixture))
        let leaf = try XCTUnwrap(SecCertificateCreateWithData(nil, X509Certificates(req.pkiData!).certificates[0] as CFData))
        var trust: SecTrust?
        SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &trust)
        SecTrustSetAnchorCertificates(try XCTUnwrap(trust), [leaf] as CFArray)
        var error: CFError?
        XCTAssertTrue(SecTrustEvaluateWithError(try XCTUnwrap(trust), &error))
    }

    func testVerifierExtractsCommonName() throws {
        let req = try XCTUnwrap(PaymentRequest(fixture))
        let verdict = PaymentRequestVerifier().verify(req)
        XCTAssertEqual(verdict.commonName, "Dash Sticker Shop")
        XCTAssertEqual(verdict.pkiType, "x509+sha256")
        // In CI the self-signed cert is untrusted → not valid; message names the cert problem.
        XCTAssertFalse(verdict.isValid)
        XCTAssertEqual(verdict.errorMessage?.contains("certificate"), true)
    }

    // MARK: - L2 verifier (expiry, unsigned)

    private func unsignedRequest(expires: UInt64) -> PaymentRequest {
        let p2pkh = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0), count: 20) + [0x88, 0xac])
        let details = PaymentDetails(network: "test", outputs: [PaymentOutput(amount: 100_000, script: p2pkh)],
                                     expires: expires).encoded()
        return PaymentRequest(pkiType: "none", serializedDetails: details)
    }

    func testExpiryRejectsPastRequest() {
        let verdict = PaymentRequestVerifier().verify(unsignedRequest(expires: 1)) // 1970
        XCTAssertFalse(verdict.isValid)
        XCTAssertEqual(verdict.errorMessage, "Request expired")
    }

    func testUnexpiredUnsignedIsValid() {
        let future = UInt64(Date().timeIntervalSince1970) + 3600
        let verdict = PaymentRequestVerifier().verify(unsignedRequest(expires: future))
        XCTAssertTrue(verdict.isValid)  // pki_type none, not expired
        XCTAssertFalse(verdict.isSecure) // unsigned → not "secure"
    }

    // MARK: - L3 transport (MockURLProtocol — see PhraseRepairEngineTests)

    override func tearDown() {
        MockURLProtocol.responseHandler = nil
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeTransport() -> PaymentProtocolTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return PaymentProtocolTransport(session: URLSession(configuration: config))
    }

    private var requestURL: URL { URL(string: "https://merchant.example/i/abc")! }

    private func assertThrowsBIP70<T>(_ expression: @autoclosure () async throws -> T,
                                      _ matches: (BIP70Error) -> Bool,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await expression(); XCTFail("expected a throw", file: file, line: line) }
        catch let error as BIP70Error { XCTAssertTrue(matches(error), "wrong BIP70Error: \(error)", file: file, line: line) }
        catch { XCTFail("non-BIP70 error: \(error)", file: file, line: line) }
    }

    func testTransportFetchHappyPath() async throws {
        let body = fixture
        MockURLProtocol.responseHandler = { _ in (200, ["Content-Type": "application/dash-paymentrequest"], body) }
        let req = try await makeTransport().fetchRequest(from: requestURL, scheme: "dash")
        XCTAssertEqual(req.pkiType, "x509+sha256")
        XCTAssertEqual(req.details.outputs.first?.amount, 100_000)
    }

    func testTransportRejectsWrongMIME() async {
        let body = fixture
        MockURLProtocol.responseHandler = { _ in (200, ["Content-Type": "text/plain"], body) }
        await assertThrowsBIP70(try await makeTransport().fetchRequest(from: requestURL, scheme: "dash")) {
            if case .unexpectedResponse = $0 { return true }; return false
        }
    }

    func testTransportRejectsNon2xx() async {
        MockURLProtocol.responseHandler = { _ in (404, ["Content-Type": "application/dash-paymentrequest"], Data()) }
        await assertThrowsBIP70(try await makeTransport().fetchRequest(from: requestURL, scheme: "dash")) {
            if case .unexpectedResponse = $0 { return true }; return false
        }
    }

    func testTransportRejectsOversizedPayload() async {
        let big = Data(count: 50_001)
        MockURLProtocol.responseHandler = { _ in (200, ["Content-Type": "application/dash-paymentrequest"], big) }
        await assertThrowsBIP70(try await makeTransport().fetchRequest(from: requestURL, scheme: "dash")) {
            $0 == .payloadTooLarge
        }
    }

    func testTransportFollowsBIP73() async throws {
        let realURL = "https://merchant.example/real"
        let body = fixture
        MockURLProtocol.responseHandler = { req in
            if req.url?.absoluteString == realURL {
                return (200, ["Content-Type": "application/dash-paymentrequest"], body)
            }
            return (200, ["Content-Type": "text/uri-list"], Data("# comment\n\(realURL)\n".utf8))
        }
        let req = try await makeTransport().fetchRequest(from: URL(string: "https://merchant.example/list")!, scheme: "dash")
        XCTAssertEqual(req.pkiType, "x509+sha256")
    }

    func testTransportPostPaymentSendsCorrectRequestAndParsesACK() async throws {
        let payment = Payment(transactions: [Data([0x01, 0x02])], memo: "hi")
        let ackBytes = PaymentACK(payment: payment, memo: "thanks").encoded()
        final class Box { var method: String?; var contentType: String?; var accept: String?; var body: Data? }
        let box = Box()
        MockURLProtocol.responseHandler = { req in
            box.method = req.httpMethod
            box.contentType = req.value(forHTTPHeaderField: "Content-Type")
            box.accept = req.value(forHTTPHeaderField: "Accept")
            box.body = MockURLProtocol.bodyData(of: req)
            return (200, ["Content-Type": "application/dash-paymentack"], ackBytes)
        }
        let ack = try await makeTransport().postPayment(payment, to: requestURL, scheme: "dash")
        XCTAssertEqual(box.method, "POST")
        XCTAssertEqual(box.contentType, "application/dash-payment")
        XCTAssertEqual(box.accept, "application/dash-paymentack")
        XCTAssertEqual(box.body, payment.encoded())
        XCTAssertEqual(ack.memo, "thanks")
    }

    // MARK: - L4 script ↔ address codec

    // Standard P2PKH/P2SH scripts for a synthetic hash160 (1...20).
    private static let hash160 = Data((1...20).map { UInt8($0) })
    private var p2pkhScript: Data { Data([0x76, 0xa9, 0x14]) + Self.hash160 + Data([0x88, 0xac]) }
    private var p2shScript: Data { Data([0xa9, 0x14]) + Self.hash160 + Data([0x87]) }

    private func sdkNetwork(_ network: PaymentNetwork) -> SwiftDashSDK.Network {
        network == .mainnet ? .mainnet : .testnet
    }

    func testFixtureScriptDecodesToKnownTestnetAddress() throws {
        // The fixture's real 25-byte P2PKH output → the exact address the bip70-dash server /
        // DashSync produce. This is the byte-exactness anchor for the local Base58Check.
        let script = try XCTUnwrap(PaymentRequest(fixture)).details.outputs.first!.script
        XCTAssertEqual(ScriptAddressCodec.address(forScript: script, network: .testnet),
                       "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr")
    }

    func testAddressRoundTrips() {
        for (script, network) in [(p2pkhScript, PaymentNetwork.testnet), (p2pkhScript, .mainnet),
                                  (p2shScript, .testnet), (p2shScript, .mainnet)] {
            let address = ScriptAddressCodec.address(forScript: script, network: network)
            XCTAssertNotNil(address)
            XCTAssertEqual(ScriptAddressCodec.scriptPubKey(forAddress: address!, network: network), script,
                           "round-trip failed for \(network)")
        }
    }

    func testProducedAddressesValidateViaSDK() {
        // Independent oracle: every address we emit must validate against SwiftDashSDK (Rust).
        for (script, network) in [(p2pkhScript, PaymentNetwork.testnet), (p2pkhScript, .mainnet),
                                  (p2shScript, .testnet), (p2shScript, .mainnet)] {
            let address = ScriptAddressCodec.address(forScript: script, network: network)!
            XCTAssertTrue(Address.validate(address, network: sdkNetwork(network)),
                          "SDK rejected our \(network) address \(address)")
        }
    }

    func testAddressNetworkPrefixes() {
        XCTAssertEqual(ScriptAddressCodec.address(forScript: p2pkhScript, network: .testnet)?.first, "y")
        XCTAssertEqual(ScriptAddressCodec.address(forScript: p2pkhScript, network: .mainnet)?.first, "X")
        XCTAssertEqual(ScriptAddressCodec.address(forScript: p2shScript, network: .mainnet)?.first, "7")
    }

    func testNonStandardScriptsRejected() {
        let opReturn = Data([0x6a, 0x04, 0xde, 0xad, 0xbe, 0xef])
        let p2pk = Data([0x21]) + Data(repeating: 0x02, count: 33) + Data([0xac])
        let truncated = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0), count: 19) + [0x88, 0xac])
        for script in [opReturn, p2pk, truncated] {
            XCTAssertNil(ScriptAddressCodec.address(forScript: script, network: .testnet))
        }
    }

    func testCrossNetworkAndCorruptedAddressRejected() {
        let testnetAddress = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"
        // Right address, wrong network version byte.
        XCTAssertNil(ScriptAddressCodec.scriptPubKey(forAddress: testnetAddress, network: .mainnet))
        // Last char flipped → checksum mismatch.
        XCTAssertNil(ScriptAddressCodec.scriptPubKey(forAddress: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLX", network: .testnet))
    }

    func testResolveOutputsMapsAndPreservesOrder() throws {
        let outputs = [PaymentOutput(amount: 100_000, script: p2pkhScript),
                       PaymentOutput(amount: 200_000, script: p2shScript)]
        let resolved = try ScriptAddressCodec.resolveOutputs(outputs, network: .testnet)
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].amount, 100_000)
        XCTAssertEqual(resolved[1].amount, 200_000)
        XCTAssertEqual(resolved[0].address, ScriptAddressCodec.address(forScript: p2pkhScript, network: .testnet))
    }

    func testResolveOutputsThrowsOnNonStandardScript() {
        let outputs = [PaymentOutput(amount: 1, script: p2pkhScript),
                       PaymentOutput(amount: 2, script: Data([0x6a, 0x01, 0x00]))]
        XCTAssertThrowsError(try ScriptAddressCodec.resolveOutputs(outputs, network: .testnet)) {
            XCTAssertEqual($0 as? BIP70Error, .nonStandardScript)
        }
    }

    func testResolveOutputsThrowsOnMissingAmount() {
        let outputs = [PaymentOutput(amount: nil, script: p2pkhScript)]
        XCTAssertThrowsError(try ScriptAddressCodec.resolveOutputs(outputs, network: .testnet)) {
            XCTAssertEqual($0 as? BIP70Error, .malformedRequest)
        }
    }
}

// MARK: - L5 orchestrator (fakes, no network/SDK)

private final class FakeTransport: PaymentProtocolTransporting {
    var request: PaymentRequest
    var ack = PaymentACK(payment: nil, memo: "thanks")
    var postShouldThrow: BIP70Error?
    var onPost: (() -> Void)?
    private(set) var postedPayment: Payment?
    init(_ request: PaymentRequest) { self.request = request }
    func fetchRequest(from url: URL, scheme: String) async throws -> PaymentRequest { request }
    func postPayment(_ payment: Payment, to url: URL, scheme: String) async throws -> PaymentACK {
        onPost?(); postedPayment = payment
        if let e = postShouldThrow { throw e }
        return ack
    }
}

private final class FakeWallet: WalletSending {
    var prepared = PreparedSend(txData: Data([0xde, 0xad, 0xbe, 0xef]), fee: 226,
                                txHashDisplay: Data((0..<32).map { UInt8($0) }))
    var calls: [String] = []
    var lastRecipients: [(address: String, amountDuffs: UInt64)] = []
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend {
        calls.append("build"); lastRecipients = recipients; return prepared
    }
    func broadcast(_ p: PreparedSend) async throws -> String {
        calls.append("broadcast"); return p.txHashDisplay.map { String(format: "%02x", $0) }.joined()
    }
}

private final class FakeReceive: ReceiveAddressProviding {
    var address: String? = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"
    func receiveAddress() -> String? { address }
}

private final class FakeAuth: SendAuthorizing {
    var error: Error?
    func authorize() async throws { if let e = error { throw e } }
}

final class BIP70PaymentServiceTests: XCTestCase {

    private let url = URL(string: "http://h/pr")!
    private static let testnetAddress = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"
    private var futureExpiry: UInt64 { UInt64(Date().timeIntervalSince1970) + 3600 }
    // P2PKH for a known testnet address, so the service's script→address derivation round-trips it.
    private var p2pkh: Data { ScriptAddressCodec.scriptPubKey(forAddress: Self.testnetAddress, network: .testnet)! }
    private var p2sh: Data { Data([0xa9, 0x14]) + Data((1...20).map { UInt8($0) }) + Data([0x87]) }

    private func unsigned(network: String? = "test", outputs: [PaymentOutput]? = nil,
                          paymentURL: String? = "http://h/pay", expires: UInt64? = nil,
                          merchantData: Data? = Data([0x01, 0x02, 0x03])) -> PaymentRequest {
        let outs = outputs ?? [PaymentOutput(amount: 100_000, script: p2pkh)]
        let details = PaymentDetails(network: network, outputs: outs, expires: expires ?? futureExpiry,
                                     memo: "memo", paymentURL: paymentURL, merchantData: merchantData)
        return PaymentRequest(pkiType: "none", serializedDetails: details.encoded())
    }

    private func service(_ t: FakeTransport, _ w: FakeWallet, receive: FakeReceive = FakeReceive(),
                         auth: FakeAuth = FakeAuth(), allowUntrusted: Bool = true) -> BIP70PaymentService {
        BIP70PaymentService(transport: t, verifier: PaymentRequestVerifier(), wallet: w,
                            receiveAddress: receive, auth: auth, allowUntrustedUnsigned: allowUntrusted)
    }

    private func assertThrowsBIP70<T>(_ expression: @autoclosure () async throws -> T, _ expected: BIP70Error,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await expression(); XCTFail("expected throw", file: file, line: line) }
        catch let e as BIP70Error { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("non-BIP70 error: \(error)", file: file, line: line) }
    }

    func testPrepareBuildsAndSpendsNothing() async throws {
        let w = FakeWallet()
        _ = try await service(FakeTransport(unsigned()), w).prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        XCTAssertTrue(w.calls.isEmpty)
    }

    func testConfirmAndSendOrderAndBytes() async throws {
        let w = FakeWallet(); let t = FakeTransport(unsigned()); t.onPost = { w.calls.append("post") }
        let svc = service(t, w)
        let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        let result = try await svc.confirmAndSend(confirmation)
        XCTAssertEqual(w.calls, ["build", "broadcast", "post"]) // broadcast strictly before POST
        XCTAssertEqual(t.postedPayment?.transactions, [w.prepared.txData])
        XCTAssertEqual(result.ackMemo, "thanks")
    }

    func testMultiOutputPassthrough() async throws {
        let w = FakeWallet()
        let outs = [PaymentOutput(amount: 100_000, script: p2pkh), PaymentOutput(amount: 200_000, script: p2sh)]
        let svc = service(FakeTransport(unsigned(outputs: outs)), w)
        let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        _ = try await svc.confirmAndSend(confirmation)
        XCTAssertEqual(confirmation.recipients.count, 2)
        XCTAssertEqual(confirmation.amount, 300_000)
        XCTAssertEqual(w.lastRecipients.map { $0.amountDuffs }, [100_000, 200_000])
    }

    func testNetworkMismatchThrowsBeforeBuild() async {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: "test")), w)
        await assertThrowsBIP70(try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .mainnet),
                                .networkMismatch(requested: "test"))
        XCTAssertTrue(w.calls.isEmpty)
    }

    func testNilNetworkUsesActiveNetwork() async throws {
        // nil details.network ⇒ no mismatch; the active .testnet drives L4 address derivation.
        let svc = service(FakeTransport(unsigned(network: nil)), FakeWallet())
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        XCTAssertEqual(c.recipients.first?.address, "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr")
    }

    func testPrepareExpiryThrows() async {
        let svc = service(FakeTransport(unsigned(expires: 1)), FakeWallet())
        await assertThrowsBIP70(try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet), .expired)
    }

    func testSendTimeExpiryThrowsAndDoesNotBroadcast() async throws {
        let w = FakeWallet()
        let expires = UInt64(Date().timeIntervalSince1970) + 30
        let svc = service(FakeTransport(unsigned(expires: expires)), w)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        await assertThrowsBIP70(try await svc.confirmAndSend(c, now: Date(timeIntervalSince1970: Double(expires) + 100)), .expired)
        XCTAssertFalse(w.calls.contains("broadcast"))
    }

    func testAuthCancelStopsBeforeBuild() async {
        let w = FakeWallet(); let auth = FakeAuth(); auth.error = BIP70Error.authCancelled
        let svc = service(FakeTransport(unsigned()), w, auth: auth)
        await assertThrowsBIP70(try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet), .authCancelled)
        XCTAssertTrue(w.calls.isEmpty)
    }

    func testSoftPostFailureAfterBroadcast() async throws {
        let w = FakeWallet(); let t = FakeTransport(unsigned()); t.postShouldThrow = .unexpectedResponse(host: "h")
        let svc = service(t, w)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        let result = try await svc.confirmAndSend(c) // must NOT throw — coins already moved
        XCTAssertNil(result.ackMemo)
        XCTAssertTrue(w.calls.contains("broadcast"))
    }

    func testRefundToFromOwnAddress() async throws {
        let t = FakeTransport(unsigned()); let receive = FakeReceive()
        let svc = service(t, FakeWallet(), receive: receive)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        _ = try await svc.confirmAndSend(c)
        XCTAssertEqual(t.postedPayment?.refundTo.count, 1)
        XCTAssertEqual(t.postedPayment?.refundTo.first?.script,
                       ScriptAddressCodec.scriptPubKey(forAddress: receive.address!, network: .testnet))
        XCTAssertEqual(t.postedPayment?.refundTo.first?.amount, 100_000)
        XCTAssertEqual(t.postedPayment?.merchantData, Data([0x01, 0x02, 0x03]))
        XCTAssertNil(t.postedPayment?.memo)
    }

    func testNilReceiveAddressGivesEmptyRefund() async throws {
        let t = FakeTransport(unsigned()); let receive = FakeReceive(); receive.address = nil
        let svc = service(t, FakeWallet(), receive: receive)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        _ = try await svc.confirmAndSend(c)
        XCTAssertEqual(t.postedPayment?.refundTo.isEmpty, true)
    }

    func testUntrustedUnsignedPolicyFlag() async throws {
        await assertThrowsBIP70(
            try await service(FakeTransport(unsigned()), FakeWallet(), allowUntrusted: false)
                .prepareForConfirmation(from: url, scheme: "dash", network: .testnet),
            .untrustedCertificate(detail: "Unsigned request"))
        _ = try await service(FakeTransport(unsigned()), FakeWallet(), allowUntrusted: true)
            .prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
    }

    func testCallbackURLFormat() async throws {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned()), w)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet, callbackScheme: "ctx")
        let result = try await svc.confirmAndSend(c)
        let hex = w.prepared.txHashDisplay.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(result.callbackURL?.absoluteString,
                       "ctx://callback=payack&address=ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr&txid=\(hex)")
    }

    // MARK: BIP70URI

    func testURIParsesPayToDashAndBIP72() {
        let uri = BIP70URI("pay:Xabc?amount=0.001&r=http%3A%2F%2Fh%2Fpr&sender=ctx")
        XCTAssertEqual(uri?.scheme, "dash")
        XCTAssertEqual(uri?.isBIP70, true)
        XCTAssertEqual(uri?.r?.absoluteString, "http://h/pr")
        XCTAssertEqual(uri?.callbackScheme, "ctx")
        XCTAssertEqual(uri?.amount, 100_000)
        XCTAssertEqual(uri?.address, "Xabc")
    }

    func testURIAddressless() {
        let uri = BIP70URI("dash:?r=http%3A%2F%2Fh%2Fpr")
        XCTAssertEqual(uri?.isBIP70, true)
        XCTAssertNil(uri?.address)
    }

    func testURIPlainAddressIsNotBIP70() {
        let uri = BIP70URI("dash:Xabc?amount=1.5")
        XCTAssertEqual(uri?.isBIP70, false)
        XCTAssertEqual(uri?.amount, 150_000_000)
    }

    func testURIRejectsNonPaymentScheme() {
        XCTAssertNil(BIP70URI("http://foo"))
    }
}

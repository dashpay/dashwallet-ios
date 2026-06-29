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

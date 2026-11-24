//
//  PaymentProtocolTests.swift
//  DashWalletTests
//
//  Tests for the app-side BIP70 protocol core (L1 codec + L2 verifier).
//  Self-contained: the signed PaymentRequest fixture is embedded (captured from the
//  bip70-dash test server, see BIP70_TESTING.md), so no network/server is required.
//

import XCTest
import Security
import SwiftDashSDK
@testable import dashpay

final class PaymentProtocolTests: XCTestCase {

    // A real x509+sha256-signed PaymentRequest (1175 bytes) from the test server:
    // network "test", one 0.001-DASH P2PKH output, merchant "Dash Sticker Shop".
    static let signedRequestBase64 =
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
        // In CI the self-signed cert is untrusted → not valid; the reason is the untrusted chain.
        XCTAssertFalse(verdict.isValid)
        XCTAssertEqual(verdict.certificateFailure, .untrustedChain)
        XCTAssertFalse(verdict.isExpired)
    }

    /// A signed request whose pki_data holds no certificate is refused as missing its
    /// certificate, not as an unsupported signature type.
    func testVerifierReportsMissingCertificate() throws {
        let signed = try XCTUnwrap(PaymentRequest(fixture))
        for pkiData in [nil, Data()] as [Data?] {
            let req = PaymentRequest(pkiType: signed.pkiType, pkiData: pkiData,
                                     serializedDetails: signed.serializedDetails, signature: signed.signature)
            let verdict = PaymentRequestVerifier().verify(req)
            XCTAssertFalse(verdict.isValid)
            XCTAssertEqual(verdict.certificateFailure, .missingCertificate)
            XCTAssertNil(verdict.commonName)
        }
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
        XCTAssertTrue(verdict.isExpired)
        XCTAssertNil(verdict.certificateFailure)
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
        MockURLProtocol.redirectHandler = nil
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeTransport() -> PaymentProtocolTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return PaymentProtocolTransport(session: URLSession(configuration: config), requiresHTTPS: false)
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

    private func makeHTTPSOnlyTransport() -> PaymentProtocolTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return PaymentProtocolTransport(session: URLSession(configuration: config), requiresHTTPS: true)
    }

    func testHTTPSOnlyTransportRefusesAnHTTPRequestURLWithoutFetching() async {
        var fetched = false
        let body = fixture
        MockURLProtocol.responseHandler = { _ in fetched = true; return (200, ["Content-Type": "application/dash-paymentrequest"], body) }
        await assertThrowsBIP70(try await makeHTTPSOnlyTransport()
            .fetchRequest(from: URL(string: "http://merchant.example/i/abc")!, scheme: "dash")) { $0 == .insecureTransport }
        XCTAssertFalse(fetched)
    }

    func testHTTPSOnlyTransportRefusesAnHTTPURIListTarget() async {
        var fetchedHosts: [String] = []
        MockURLProtocol.responseHandler = { request in
            fetchedHosts.append(request.url?.absoluteString ?? "")
            return (200, ["Content-Type": "text/uri-list"], Data("http://merchant.example/real\n".utf8))
        }
        await assertThrowsBIP70(try await makeHTTPSOnlyTransport().fetchRequest(from: requestURL, scheme: "dash")) {
            $0 == .insecureTransport
        }
        XCTAssertEqual(fetchedHosts, [requestURL.absoluteString])
    }

    func testDefaultTransportStillFollowsAnHTTPURIListTarget() async throws {
        let body = fixture
        MockURLProtocol.responseHandler = { request in
            request.url?.scheme == "https"
                ? (200, ["Content-Type": "text/uri-list"], Data("http://merchant.example/real\n".utf8))
                : (200, ["Content-Type": "application/dash-paymentrequest"], body)
        }
        let req = try await makeTransport().fetchRequest(from: requestURL, scheme: "dash")
        XCTAssertEqual(req.pkiType, "x509+sha256")
    }

    func testHTTPSOnlyTransportRefusesAnHTTPRedirectOfTheFetch() async {
        MockURLProtocol.redirectHandler = { $0.url?.scheme == "https" ? URL(string: "http://merchant.example/real") : nil }
        let body = fixture
        MockURLProtocol.responseHandler = { _ in (200, ["Content-Type": "application/dash-paymentrequest"], body) }
        await assertThrowsBIP70(try await makeHTTPSOnlyTransport().fetchRequest(from: requestURL, scheme: "dash")) {
            $0 == .insecureTransport
        }
    }

    func testHTTPSOnlyTransportRefusesAnHTTPPaymentURLAndRedirect() async {
        var posted = false
        MockURLProtocol.responseHandler = { _ in posted = true; return (200, ["Content-Type": "application/dash-paymentack"], Data()) }
        let payment = Payment(merchantData: nil, transactions: [Data([1])], refundTo: [], memo: nil)
        await assertThrowsBIP70(try await makeHTTPSOnlyTransport()
            .postPayment(payment, to: URL(string: "http://merchant.example/pay")!, scheme: "dash")) { $0 == .insecureTransport }
        XCTAssertFalse(posted)

        MockURLProtocol.redirectHandler = { $0.url?.scheme == "https" ? URL(string: "http://merchant.example/pay") : nil }
        await assertThrowsBIP70(try await makeHTTPSOnlyTransport()
            .postPayment(payment, to: URL(string: "https://merchant.example/pay")!, scheme: "dash")) { $0 == .insecureTransport }
        XCTAssertFalse(posted)
    }

    private func redirectDecision(enforced: Bool, to target: String) -> (followed: Bool, refused: Bool) {
        let redirects = HTTPSRedirectGuard(isEnforced: enforced)
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: requestURL)
        let response = HTTPURLResponse(url: requestURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var followed = false
        redirects.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: URL(string: target)!)) { followed = $0 != nil }
        return (followed, redirects.refusedRedirect)
    }

    func testRedirectGuardRefusesAnHTTPRedirectOnlyWhenEnforced() {
        XCTAssertTrue(redirectDecision(enforced: true, to: "http://merchant.example/real") == (false, true))
        XCTAssertTrue(redirectDecision(enforced: true, to: "https://merchant.example/real") == (true, false))
        XCTAssertTrue(redirectDecision(enforced: false, to: "http://merchant.example/real") == (true, false))
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
        switch network {
        case .mainnet: return .mainnet
        // The SDK validates devnet addresses with testnet's version bytes.
        case .testnet, .devnet: return .testnet
        }
    }

    /// Devnet is a distinct payment network but not a distinct address
    /// format. The codec must keep producing testnet's bytes for it, or every
    /// devnet address the app shows and parses changes shape.
    func testDevnetSharesTestnetAddressVersionBytes() {
        for script in [p2pkhScript, p2shScript] {
            XCTAssertEqual(ScriptAddressCodec.address(forScript: script, network: .devnet),
                           ScriptAddressCodec.address(forScript: script, network: .testnet))
        }
        XCTAssertEqual(PaymentNetwork.devnet.pubkeyHashVersion,
                       PaymentNetwork.testnet.pubkeyHashVersion)
        XCTAssertEqual(PaymentNetwork.devnet.scriptHashVersion,
                       PaymentNetwork.testnet.scriptHashVersion)
    }

    /// BIP70 has no devnet token, so no declared network string may resolve to
    /// `.devnet`. That is precisely what makes the service's equality check
    /// reject a testnet request while the wallet runs on a devnet.
    func testDeclaredNetworkStringsNeverResolveToDevnet() {
        XCTAssertEqual(BIP70PaymentService.paymentNetwork(fromString: "test"), .testnet)
        XCTAssertEqual(BIP70PaymentService.paymentNetwork(fromString: "main"), .mainnet)
        XCTAssertNil(BIP70PaymentService.paymentNetwork(fromString: "devnet"))
        XCTAssertNil(BIP70PaymentService.paymentNetwork(fromString: nil))
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

final class PreparedStandardSendBroadcastTests: XCTestCase {
    private func prepared(
        hashByte: UInt8,
        ensureOnline: @escaping () throws -> Void = {},
        action: @escaping () throws -> CoreTransactionBroadcastOutcome
    ) -> PreparedStandardSend {
        PreparedStandardSend(
            txData: Data([0x01]),
            txHash: Data(repeating: hashByte, count: 32),
            fee: 226,
            address: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr",
            amount: 100_000,
            ensureOnlineAction: ensureOnline,
            broadcastAction: action
        )
    }

    func testAcceptedRecordsRecentSendAndBecomesOneShot() throws {
        var calls = 0
        let send = prepared(hashByte: 0xa1) {
            calls += 1
            return .accepted(txid: String(repeating: "a1", count: 32))
        }

        try send.broadcast()

        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(WalletSendService.shared.recentSends.entry(forTxidWire: send.txidWire))
        XCTAssertThrowsError(try send.broadcast())
        XCTAssertEqual(calls, 1)
    }

    func testRejectedCanBeRetriedAndIsNotRecorded() {
        var calls = 0
        let send = prepared(hashByte: 0xb2) {
            calls += 1
            return .rejected(
                txid: String(repeating: "b2", count: 32),
                reason: "broadcast was not started")
        }

        for _ in 0..<2 {
            XCTAssertThrowsError(try send.broadcast()) { error in
                XCTAssertTrue(WalletSendService.isBroadcastRejectedError(error as NSError))
            }
        }

        XCTAssertEqual(calls, 2)
        XCTAssertNil(WalletSendService.shared.recentSends.entry(forTxidWire: send.txidWire))
    }

    func testUnknownBlocksSecondBroadcastAndIsNotRecorded() {
        var calls = 0
        let send = prepared(hashByte: 0xc3) {
            calls += 1
            return .unknown(txid: String(repeating: "c3", count: 32), reason: "timeout")
        }

        var firstError: NSError?
        XCTAssertThrowsError(try send.broadcast()) { error in
            firstError = error as NSError
            XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error as NSError))
        }
        var secondError: NSError?
        XCTAssertThrowsError(try send.broadcast()) { error in
            secondError = error as NSError
            XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error as NSError))
        }

        XCTAssertEqual(calls, 1)
        XCTAssertTrue(firstError === secondError)
        XCTAssertNil(WalletSendService.shared.recentSends.entry(forTxidWire: send.txidWire))
    }

    func testOfflineFailureReturnsToReady() throws {
        let offline = NSError(
            domain: "test.network", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "offline"])
        var isOnline = false
        var calls = 0
        let send = prepared(
            hashByte: 0xd4,
            ensureOnline: {
                if !isOnline { throw offline }
            },
            action: {
                calls += 1
                return .accepted(txid: String(repeating: "d4", count: 32))
            })

        XCTAssertThrowsError(try send.broadcast())
        XCTAssertEqual(calls, 0)

        isOnline = true
        try send.broadcast()
        XCTAssertEqual(calls, 1)
    }

    func testLocalBroadcastFailureReturnsToReady() throws {
        let localError = NSError(
            domain: "test.local", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "local failure"])
        var calls = 0
        let send = prepared(hashByte: 0xe5) {
            calls += 1
            if calls == 1 { throw localError }
            return .accepted(txid: String(repeating: "e5", count: 32))
        }

        XCTAssertThrowsError(try send.broadcast())
        try send.broadcast()
        XCTAssertEqual(calls, 2)
    }

    func testUnknownRemainsTerminalWhenNetworkStateChanges() {
        let offline = NSError(
            domain: "test.network", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "offline"])
        var onlineChecks = 0
        var shouldFailOnlineCheck = false
        var calls = 0
        let send = prepared(
            hashByte: 0xf6,
            ensureOnline: {
                onlineChecks += 1
                if shouldFailOnlineCheck { throw offline }
            },
            action: {
                calls += 1
                return .unknown(
                    txid: String(repeating: "f6", count: 32),
                    reason: "peer echo timed out")
            })

        XCTAssertThrowsError(try send.broadcast()) { error in
            XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error as NSError))
        }
        shouldFailOnlineCheck = true
        XCTAssertThrowsError(try send.broadcast()) { error in
            XCTAssertTrue(WalletSendService.isBroadcastUnknownError(error as NSError))
        }
        XCTAssertEqual(onlineChecks, 1)
        XCTAssertEqual(calls, 1)
    }

    func testPaymentControllerReenablesSendExceptForUnknown() throws {
        let rejected = prepared(hashByte: 0x17) {
            .rejected(txid: String(repeating: "17", count: 32), reason: "not started")
        }
        let unknown = prepared(hashByte: 0x28) {
            .unknown(txid: String(repeating: "28", count: 32), reason: "timeout")
        }

        var rejectedError: NSError?
        XCTAssertThrowsError(try rejected.broadcast()) { rejectedError = $0 as NSError }
        var unknownError: NSError?
        XCTAssertThrowsError(try unknown.broadcast()) { unknownError = $0 as NSError }

        XCTAssertTrue(PaymentController.shouldReenableSending(
            after: try XCTUnwrap(rejectedError)))
        XCTAssertFalse(PaymentController.shouldReenableSending(
            after: try XCTUnwrap(unknownError)))
        XCTAssertTrue(PaymentController.shouldReenableSending(
            after: NSError(domain: "test.local", code: 3)))
    }
}

// MARK: - L5 orchestrator (fakes, no network/SDK)

private final class FakeTransport: PaymentProtocolTransporting {
    var request: PaymentRequest
    var ack = PaymentACK(payment: nil, memo: "thanks")
    var postShouldThrow: BIP70Error?
    var onPost: (() -> Void)?
    private(set) var postedPayment: Payment?
    var onFetch: (() -> Void)?
    init(_ request: PaymentRequest) { self.request = request }
    func fetchRequest(from url: URL, scheme: String) async throws -> PaymentRequest { onFetch?(); return request }
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
    var buildErrorsRemaining = 0 // throw from build this many times before succeeding (pre-spend failure)
    var broadcastError: Error?
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend {
        calls.append("build")
        if buildErrorsRemaining > 0 { buildErrorsRemaining -= 1; throw BIP70Error.walletNotReady }
        lastRecipients = recipients; return prepared
    }
    func broadcast(_ p: PreparedSend) async throws -> String {
        calls.append("broadcast")
        if let broadcastError { throw broadcastError }
        return p.txHashDisplay.map { String(format: "%02x", $0) }.joined()
    }
}

private final class FakeReceive: ReceiveAddressProviding {
    var address: String? = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"
    func receiveAddress() -> String? { address }
}

private final class FakeAuth: SendAuthorizing {
    var error: Error?
    var onAuthorize: (() -> Void)?
    private(set) var authorizeCount = 0
    private(set) var authorizedAmounts: [UInt64] = []
    func authorize(spendAmount: UInt64) async throws {
        authorizeCount += 1
        authorizedAmounts.append(spendAmount)
        onAuthorize?()
        if let e = error { throw e }
    }
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
                         auth: FakeAuth = FakeAuth(), allowUntrusted: Bool = true,
                         clock: @escaping () -> Date = Date.init) -> BIP70PaymentService {
        BIP70PaymentService(transport: t, verifier: PaymentRequestVerifier(), wallet: w,
                            receiveAddress: receive, auth: auth, allowUntrustedUnsigned: allowUntrusted, clock: clock)
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

    /// A wallet running on a devnet must refuse a request that declares the
    /// public testnet. Devnet and testnet share address version bytes, so
    /// nothing downstream would notice: the transaction would be signed and
    /// broadcast on the devnet while the merchant waits on testnet.
    func testPrepareRejectsTestnetRequestWhileOnDevnet() async {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: "test")), w)
        await assertThrowsBIP70(
            try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .devnet),
            .networkMismatch(requested: "test"))
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// And a mainnet request, for the same reason.
    func testPrepareRejectsMainnetRequestWhileOnDevnet() async {
        let svc = service(FakeTransport(unsigned(network: "main")), FakeWallet())
        await assertThrowsBIP70(
            try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .devnet),
            .networkMismatch(requested: "main"))
    }

    /// A request that declares no network is still honoured on devnet: an
    /// absent field means "no check" on every network, and devnet resolves its
    /// outputs through testnet's address bytes.
    func testPrepareAcceptsNetworklessRequestOnDevnet() async throws {
        let svc = service(FakeTransport(unsigned(network: nil)), FakeWallet())
        let confirmation = try await svc.prepareForConfirmation(
            from: url, scheme: "dash", network: .devnet)
        XCTAssertEqual(confirmation.recipients.map(\.address), [Self.testnetAddress])
        XCTAssertEqual(confirmation.network, .devnet)
    }

    func testConfirmAndSendOrderAndBytes() async throws {
        let w = FakeWallet(); let t = FakeTransport(unsigned()); t.onPost = { w.calls.append("post") }
        let svc = service(t, w)
        let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        let result = try await svc.confirmAndSend(confirmation)
        // BIP70 order: the merchant acknowledges the signed bytes before they are broadcast.
        XCTAssertEqual(w.calls, ["build", "post", "broadcast"])
        XCTAssertEqual(t.postedPayment?.transactions, [w.prepared.txData])
        XCTAssertEqual(result.ackMemo, "thanks")
    }

    func testSecondSendOnSameConfirmationIsRejected() async throws {
        let w = FakeWallet(); let t = FakeTransport(unsigned()); t.onPost = { w.calls.append("post") }
        let svc = service(t, w)
        let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        _ = try await svc.confirmAndSend(confirmation) // first send succeeds
        await assertThrowsBIP70(try await svc.confirmAndSend(confirmation), .alreadySent)
        XCTAssertEqual(w.calls.filter { $0 == "build" }.count, 1) // no second build...
        XCTAssertEqual(w.calls.filter { $0 == "broadcast" }.count, 1) // ...and no second broadcast
    }

    func testRetryAfterPreSpendFailureSucceeds() async throws {
        let w = FakeWallet(); w.buildErrorsRemaining = 1
        let t = FakeTransport(unsigned()); t.onPost = { w.calls.append("post") }
        let svc = service(t, w)
        let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        await assertThrowsBIP70(try await svc.confirmAndSend(confirmation), .walletNotReady) // build throws → guard reset
        _ = try await svc.confirmAndSend(confirmation) // retry on the SAME confirmation now succeeds
        XCTAssertEqual(w.calls.filter { $0 == "build" }.count, 2)
        XCTAssertEqual(w.calls.filter { $0 == "broadcast" }.count, 1)
    }

    func testBroadcastFailureKeepsBIP70ConfirmationOneShot() async throws {
        let w = FakeWallet()
        w.broadcastError = BIP70Error.walletNotReady
        let svc = service(FakeTransport(unsigned(paymentURL: nil)), w)
        let confirmation = try await svc.prepareForConfirmation(
            from: url, scheme: "dash", network: .testnet)

        await assertThrowsBIP70(
            try await svc.confirmAndSend(confirmation), .walletNotReady)
        await assertThrowsBIP70(
            try await svc.confirmAndSend(confirmation), .alreadySent)
        XCTAssertEqual(w.calls.filter { $0 == "broadcast" }.count, 1)
    }

    /// Once the merchant's Payment POST was acknowledged it holds the signed bytes, so whatever the local
    /// broadcast throws afterwards is not provably unsent: the outcome is `inFlight` (no Retry), never `notSent`.
    func testErrorAfterMerchantAckIsInFlightNeverNotSent() async throws {
        let postAckErrors: [Error] = [
            PlatformWalletError.staleReservationToken("stale"),
            SwiftDashSDKTransactionSender.SendError.walletNotReady("not ready"),
            SwiftDashSDKTransactionSender.SendError.invalidInput("bad input")
        ]
        for postAckError in postAckErrors {
            let w = FakeWallet(); w.broadcastError = postAckError
            let t = FakeTransport(unsigned())
            let svc = service(t, w)
            let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)

            do {
                _ = try await svc.confirmAndSend(confirmation)
                XCTFail("expected the broadcast to throw")
            } catch {
                XCTAssertNotNil(t.postedPayment, "the merchant acknowledged before the failure")
                guard case .inFlight = SendOutcome(error: error) else {
                    return XCTFail("post-ACK \(postAckError) must be inFlight, got \(SendOutcome(error: error))")
                }
            }
        }
    }

    /// Without a payment_url nothing was POSTed, so a refused broadcast is still provably unsent.
    func testBroadcastErrorWithoutPaymentURLKeepsItsNotSentMapping() async throws {
        let w = FakeWallet(); w.broadcastError = PlatformWalletError.staleReservationToken("stale")
        let svc = service(FakeTransport(unsigned(paymentURL: nil)), w)
        let confirmation = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)

        do {
            _ = try await svc.confirmAndSend(confirmation)
            XCTFail("expected the broadcast to throw")
        } catch {
            guard case .notSent = SendOutcome(error: error) else {
                return XCTFail("no POST happened, expected notSent, got \(SendOutcome(error: error))")
            }
        }
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

    /// Built while the request was valid, tapped after it expired: nothing is POSTed or broadcast and the
    /// claim is released, so the same confirmation can be built again.
    func testExpiryAtPostThrowsBeforePostAndBroadcastAndReleasesTheClaim() async throws {
        let expires = futureExpiry
        let w = FakeWallet(); let t = FakeTransport(unsigned(expires: expires)); t.onPost = { w.calls.append("post") }
        let svc = service(t, w)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        let beforeExpiry = Date(timeIntervalSince1970: Double(expires) - 10)
        let built = try await svc.buildForSend(c, now: beforeExpiry)

        await assertThrowsBIP70(
            try await svc.postAndBroadcast(built, now: Date(timeIntervalSince1970: Double(expires) + 1)), .expired)
        XCTAssertNil(t.postedPayment)
        XCTAssertEqual(w.calls, ["build"])

        let rebuilt = try await svc.buildForSend(c, now: beforeExpiry)
        _ = try await svc.postAndBroadcast(rebuilt, now: beforeExpiry)
        XCTAssertEqual(w.calls, ["build", "build", "post", "broadcast"])
    }

    /// Valid when the Payment is POSTed, expired when the merchant's ACK comes back: the merchant holds the signed
    /// bytes, so nothing is broadcast, the claim is kept and the send is in flight, never retried.
    func testExpiryDuringThePostDoesNotBroadcastAndKeepsTheClaim() async throws {
        final class Clock { var now = Date() }
        let expires = futureExpiry
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: Double(expires) - 10)
        let w = FakeWallet(); let t = FakeTransport(unsigned(expires: expires))
        t.onPost = {
            w.calls.append("post")
            clock.now = Date(timeIntervalSince1970: Double(expires) + 1)
        }
        let svc = service(t, w, clock: { clock.now })
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet, now: clock.now)
        let built = try await svc.buildForSend(c, now: clock.now)

        var thrown: Error?
        do { _ = try await svc.postAndBroadcast(built, now: clock.now) } catch { thrown = error }

        guard case BIP70Error.failedAfterAcknowledgement(let txHash, _)? = thrown as? BIP70Error else {
            return XCTFail("expected failedAfterAcknowledgement, got \(String(describing: thrown))")
        }
        XCTAssertEqual(txHash, w.prepared.txHashDisplay)
        XCTAssertEqual(w.calls, ["build", "post"], "an expired request is never broadcast")
        await assertThrowsBIP70(
            try await svc.buildForSend(c, now: Date(timeIntervalSince1970: Double(expires) - 10)), .alreadySent)
    }

    /// The merchant acknowledged the Payment, then the broadcast failed: it holds the signed bytes and may fulfil the
    /// order, so DashSpend gets the in-progress error with the txid it records the purchase against.
    func testPayWithDashUrlReportsAFailureAfterTheAcknowledgementAsInProgressWithTheTxid() async {
        let w = FakeWallet(); w.broadcastError = NSError(domain: "test.local", code: 7)
        let svc = service(FakeTransport(unsigned(network: nil)), w)
        let sendCoins = SendCoinsService(makeBIP70Service: { svc })

        var thrown: Error?
        do { _ = try await sendCoins.payWithDashUrl(url: "dash:?r=http://h/pr", validate: { _ in }) } catch { thrown = error }

        guard case DashSpendError.paymentStatusUnknown(let txIdWire, _)? = thrown as? DashSpendError else {
            return XCTFail("expected paymentStatusUnknown, got \(String(describing: thrown))")
        }
        XCTAssertEqual(txIdWire, Data(w.prepared.txHashDisplay.reversed()))
        XCTAssertEqual(w.calls, ["build", "broadcast"])
    }

    /// A gift-card link naming two different apps to call back is refused before anything is fetched or built.
    func testPayWithDashUrlRefusesALinkWithTwoDifferentCallbacks() async {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: nil)), w)
        let sendCoins = SendCoinsService(makeBIP70Service: { svc })

        var thrown: Error?
        do { _ = try await sendCoins.payWithDashUrl(url: "dash:?r=http://h/pr&sender=a&req-sender=b", validate: { _ in }) } catch {
            thrown = error
        }

        guard case DashSpendError.paymentProcessingError? = thrown as? DashSpendError else {
            return XCTFail("expected paymentProcessingError, got \(String(describing: thrown))")
        }
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// A gift-card link the parsers reject (a required label given twice differently, a query broken across lines,
    /// two payment requests) is refused before anything is fetched or built, as the interactive Send refuses it.
    func testPayWithDashUrlRefusesALinkTheParsersReject() async {
        for link in ["dash:?r=http://h/pr&req-label=a&label=b", "dash:?r=http://h/pr&amount=1&\nreq-sender=ctx",
                     "dash:?r=http://h/pr&r=http://h/other", "dash:?r=http://h/pr&req-amount=abc",
                     "dash:?r=http://h/pr&req-amount=1&amount=2", "dash:?r=ftp://h/pr", "dash:?r=http://h/pr&req-r=http://h/other"] {
            let w = FakeWallet()
            let svc = service(FakeTransport(unsigned(network: nil)), w)
            let sendCoins = SendCoinsService(makeBIP70Service: { svc })
            var thrown: Error?
            do { _ = try await sendCoins.payWithDashUrl(url: link, validate: { _ in }) } catch { thrown = error }
            guard case DashSpendError.paymentProcessingError? = thrown as? DashSpendError else {
                return XCTFail("\(link): expected paymentProcessingError, got \(String(describing: thrown))")
            }
            XCTAssertTrue(w.calls.isEmpty, link)
        }
    }

    /// A gift-card link whose optional amount is malformed is paid: the fetched invoice sets the amount.
    func testPayWithDashUrlLeavesAMalformedOptionalAmountToTheInvoice() async throws {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: nil)), w)
        let sendCoins = SendCoinsService(makeBIP70Service: { svc })

        _ = try await sendCoins.payWithDashUrl(url: "dash:?r=http://h/pr&amount=abc", validate: { _ in })

        XCTAssertEqual(w.calls, ["build", "broadcast"])
    }

    /// A gift-card link that names the same request in `r` and `req-r` is paid: one request, no choice to make.
    func testPayWithDashUrlPaysALinkThatRepeatsItsRequest() async throws {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: nil)), w)
        let sendCoins = SendCoinsService(makeBIP70Service: { svc })

        _ = try await sendCoins.payWithDashUrl(url: "dash:?r=http://h/pr&req-r=http://h/pr", validate: { _ in })

        XCTAssertEqual(w.calls, ["build", "broadcast"])
    }

    /// O76: the same app spelled in two cases (`sender=ShopApp`, `req-sender=shopapp`) is one callback, so the gift-card
    /// link is paid, not refused as invalid.
    func testPayWithDashUrlPaysALinkWhoseCallbacksDifferOnlyInCase() async throws {
        let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: nil)), w)
        let sendCoins = SendCoinsService(makeBIP70Service: { svc })

        _ = try await sendCoins.payWithDashUrl(url: "dash:?r=http://h/pr&sender=ShopApp&req-sender=shopapp", validate: { _ in })

        XCTAssertEqual(w.calls, ["build", "broadcast"])
    }

    func testAuthCancelStopsBeforeBuild() async {
        let w = FakeWallet(); let auth = FakeAuth(); auth.error = BIP70Error.authCancelled
        let svc = service(FakeTransport(unsigned()), w, auth: auth)
        await assertThrowsBIP70(try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet), .authCancelled)
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// The headless flow fetches and verifies the request before it asks for the PIN, so the
    /// user never authorizes a request nobody has looked at yet.
    func testHeadlessFetchesRequestBeforeAuthorizing() async throws {
        var events: [String] = []
        let t = FakeTransport(unsigned()); t.onFetch = { events.append("fetch") }
        let auth = FakeAuth(); auth.onAuthorize = { events.append("authorize") }
        let w = FakeWallet()
        let svc = service(t, w, auth: auth)

        _ = try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet)

        XCTAssertEqual(events, ["fetch", "authorize"])
        XCTAssertEqual(w.calls, ["build", "broadcast"])
    }

    /// The caller's check sees the prepared request, and passing it lets the send go ahead.
    func testHeadlessValidateReceivesThePreparedRequest() async throws {
        let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(FakeTransport(unsigned()), w, auth: auth)
        var seenAmount: UInt64?

        let result = try await svc.confirmAndSendHeadless(
            from: url, scheme: "dash", network: .testnet,
            validate: { seenAmount = $0.amount })

        XCTAssertEqual(seenAmount, 100_000)
        XCTAssertEqual(result.amount, 100_000)
        XCTAssertEqual(auth.authorizeCount, 1)
        XCTAssertEqual(auth.authorizedAmounts, [100_000], "the prompt is for the request's amount")
    }

    /// A request the caller refuses ends the flow there: no PIN prompt, nothing built or
    /// broadcast, nothing posted to the merchant.
    func testHeadlessValidateRejectionStopsBeforeAuthorizeAndBuild() async {
        struct Refused: Error {}
        let t = FakeTransport(unsigned()); let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(t, w, auth: auth)

        do {
            _ = try await svc.confirmAndSendHeadless(
                from: url, scheme: "dash", network: .testnet,
                validate: { _ in throw Refused() })
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is Refused, "unexpected error: \(error)")
        }

        XCTAssertEqual(auth.authorizeCount, 0)
        XCTAssertTrue(w.calls.isEmpty)
        XCTAssertNil(t.postedPayment)
    }

    /// A request that fails verification never reaches the caller's check or the PIN prompt.
    func testHeadlessExpiredRequestStopsBeforeValidateAndAuthorize() async {
        let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(expires: 1)), w, auth: auth)
        var validateCalled = false

        await assertThrowsBIP70(
            try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet,
                                                 validate: { _ in validateCalled = true }),
            .expired)

        XCTAssertFalse(validateCalled)
        XCTAssertEqual(auth.authorizeCount, 0)
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// `SendCoinsService.payWithDashUrl` hands the caller's check the fetched request and
    /// stops on its refusal: no PIN prompt, nothing built.
    func testPayWithDashUrlRunsTheCallersCheckBeforeAuthorizing() async {
        struct Refused: Error {}
        let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(network: nil)), w, auth: auth)
        let sender = SendCoinsService(makeBIP70Service: { svc })
        var seenAmount: UInt64?

        do {
            _ = try await sender.payWithDashUrl(
                url: "dash:?r=http%3A%2F%2Fh%2Fpr",
                validate: { seenAmount = $0.amount; throw Refused() })
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is Refused, "unexpected error: \(error)")
        }

        XCTAssertEqual(seenAmount, 100_000)
        XCTAssertEqual(auth.authorizeCount, 0)
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// Outputs whose amounts do not sum within UInt64 make the request malformed.
    func testPrepareRejectsOutputsThatOverflowTheTotal() async {
        let outputs = [PaymentOutput(amount: UInt64.max, script: p2pkh), PaymentOutput(amount: 1, script: p2pkh)]
        let svc = service(FakeTransport(unsigned(outputs: outputs)), FakeWallet())
        await assertThrowsBIP70(try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet),
                                .malformedRequest)
    }

    /// A request that expires while it is being fetched gets no PIN prompt: the expiry is
    /// checked against the time after the fetch, before the caller's check and the prompt.
    func testHeadlessRequestExpiringDuringFetchIsNotAuthorized() async {
        let expiry = UInt64(Date().timeIntervalSince1970) + 60
        let beforeFetch = Date(timeIntervalSince1970: TimeInterval(expiry) - 30)
        let afterFetch = Date(timeIntervalSince1970: TimeInterval(expiry) + 30)
        var fetched = false
        let t = FakeTransport(unsigned(expires: expiry)); t.onFetch = { fetched = true }
        let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(t, w, auth: auth)
        var validateCalled = false

        await assertThrowsBIP70(
            try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet,
                                                 now: { fetched ? afterFetch : beforeFetch },
                                                 validate: { _ in validateCalled = true }),
            .expired)

        XCTAssertTrue(fetched)
        XCTAssertFalse(validateCalled)
        XCTAssertEqual(auth.authorizeCount, 0)
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// A signed request with no payment URL is refused before the caller's check and before
    /// the PIN prompt. The signed request is built from an unsigned one, because a signature
    /// the system trusts cannot be made in a test.
    func testHeadlessSignedRequestWithoutPaymentURLIsRefusedBeforeAsking() async throws {
        let t = FakeTransport(unsigned(paymentURL: nil)); let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(t, w, auth: auth)
        let prepared = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        let signed = Confirmation(
            merchantName: "Merchant", isSecure: true, recipients: prepared.recipients, amount: prepared.amount,
            estimatedFee: prepared.estimatedFee, network: prepared.network, paymentURL: nil,
            scheme: prepared.scheme, merchantData: prepared.merchantData, memo: prepared.memo,
            callbackScheme: prepared.callbackScheme, request: prepared.request)
        var validateCalled = false

        await assertThrowsBIP70(
            try await svc.authorizeAndSend(signed, validate: { _ in validateCalled = true }),
            .missingPaymentURL)

        XCTAssertFalse(validateCalled)
        XCTAssertEqual(auth.authorizeCount, 0)
        XCTAssertTrue(w.calls.isEmpty)
    }

    /// An unsigned request with no payment URL is a plain address-style payment and goes on.
    func testHeadlessUnsignedRequestWithoutPaymentURLGoesOn() async throws {
        let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(FakeTransport(unsigned(paymentURL: nil)), w, auth: auth)

        _ = try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet)

        XCTAssertEqual(auth.authorizeCount, 1)
        XCTAssertEqual(w.calls, ["build", "broadcast"])
    }

    /// The caller's check may wait for the buyer's answer. A request that expires meanwhile
    /// gets no PIN prompt: the expiry is checked again once the check returns.
    func testHeadlessRequestExpiringDuringTheCallersCheckIsNotAuthorized() async {
        let expiry = UInt64(Date().timeIntervalSince1970) + 60
        let beforeCheck = Date(timeIntervalSince1970: TimeInterval(expiry) - 30)
        let afterCheck = Date(timeIntervalSince1970: TimeInterval(expiry) + 30)
        var checked = false
        let t = FakeTransport(unsigned(expires: expiry))
        let auth = FakeAuth(); let w = FakeWallet()
        let svc = service(t, w, auth: auth)

        await assertThrowsBIP70(
            try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet,
                                                 now: { checked ? afterCheck : beforeCheck },
                                                 validate: { _ in
                                                     await Task.yield()
                                                     checked = true
                                                 }),
            .expired)

        XCTAssertTrue(checked)
        XCTAssertEqual(auth.authorizeCount, 0)
        XCTAssertTrue(w.calls.isEmpty)
        XCTAssertNil(t.postedPayment)
    }

    /// A request that is still valid when it is fetched but expires while the PIN prompt is
    /// open is not sent: the expiry is checked again against the time after the prompt.
    func testHeadlessRequestExpiringDuringAuthorizationIsNotSent() async {
        let expiry = UInt64(Date().timeIntervalSince1970) + 60
        let beforePrompt = Date(timeIntervalSince1970: TimeInterval(expiry) - 30)
        let afterPrompt = Date(timeIntervalSince1970: TimeInterval(expiry) + 30)
        var promptAnswered = false
        let t = FakeTransport(unsigned(expires: expiry))
        let auth = FakeAuth(); auth.onAuthorize = { promptAnswered = true }
        let w = FakeWallet()
        let svc = service(t, w, auth: auth)

        await assertThrowsBIP70(
            try await svc.confirmAndSendHeadless(from: url, scheme: "dash", network: .testnet,
                                                 now: { promptAnswered ? afterPrompt : beforePrompt }),
            .expired)

        XCTAssertEqual(auth.authorizeCount, 1)
        XCTAssertTrue(w.calls.isEmpty)
        XCTAssertNil(t.postedPayment)
    }

    /// A failed merchant round-trip happens BEFORE broadcast, so the money is unspent: the
    /// failure is a hard throw carrying the tx hash, nothing is broadcast, and the send
    /// guard is released so the user can retry.
    func testPostFailureBeforeBroadcastThrowsWithoutBroadcasting() async throws {
        let w = FakeWallet(); let t = FakeTransport(unsigned()); t.postShouldThrow = .unexpectedResponse(host: "h")
        let svc = service(t, w)
        let c = try await svc.prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        await assertThrowsBIP70(
            try await svc.confirmAndSend(c),
            .paymentNotAcknowledged(txHashDisplay: w.prepared.txHashDisplay, reason: "Unexpected response from h."))
        XCTAssertFalse(w.calls.contains("broadcast"))
        t.postShouldThrow = nil
        _ = try await svc.confirmAndSend(c) // guard was released: the retry goes through
        XCTAssertEqual(w.calls, ["build", "build", "broadcast"])
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
            .unsignedRequest)
        _ = try await service(FakeTransport(unsigned()), FakeWallet(), allowUntrusted: true)
            .prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        XCTAssertEqual(BIP70Error.unsignedRequest.errorDescription, "Untrusted certificate - Unsigned request.")
    }

    /// A signed request whose chain is not trusted (the self-signed fixture in CI) is refused
    /// with a typed reason, and the text names the problem once.
    func testSignedUntrustedRequestThrowsTypedReason() async throws {
        let fixture = try XCTUnwrap(Data(base64Encoded: PaymentProtocolTests.signedRequestBase64))
        let req = try XCTUnwrap(PaymentRequest(fixture))
        await assertThrowsBIP70(
            try await service(FakeTransport(req), FakeWallet())
                .prepareForConfirmation(from: url, scheme: "dash", network: .testnet),
            .untrustedCertificate(.untrustedChain))
        XCTAssertEqual(BIP70Error.untrustedCertificate(.untrustedChain).errorDescription, "Untrusted certificate.")
    }

    /// Every certificate-failure reason reads as one sentence from the text lists, with the
    /// "Untrusted certificate" prefix once.
    func testCertificateFailureTexts() {
        let texts: [BIP70CertificateFailure: String] = [
            .missingCertificate: "Untrusted certificate - Missing certificate.",
            .untrustedChain: "Untrusted certificate.",
            .invalidSignature: "Untrusted certificate - Invalid signature.",
            .unsupportedSignatureType: "Untrusted certificate - Unsupported signature type.",
        ]
        for (failure, text) in texts {
            XCTAssertEqual(BIP70Error.untrustedCertificate(failure).errorDescription, text)
        }
    }

    /// A failed verdict maps to the error that names its reason: the certificate failure, or
    /// expiry only when the verdict says the request expired.
    func testVerdictErrorMapping() {
        func verdict(_ pkiType: String, valid: Bool, failure: BIP70CertificateFailure? = nil,
                     expired: Bool = false) -> PaymentRequestVerifier.Verdict {
            PaymentRequestVerifier.Verdict(isValid: valid, commonName: nil, pkiType: pkiType,
                                           certificateFailure: failure, isExpired: expired)
        }
        let error = BIP70PaymentService.verificationError(for:)
        XCTAssertNil(error(verdict("x509+sha256", valid: true)))
        XCTAssertNil(error(verdict("none", valid: true)))
        XCTAssertEqual(error(verdict("x509+sha256", valid: false, expired: true)), .expired)
        XCTAssertEqual(error(verdict("none", valid: false, expired: true)), .expired)
        let failures: [BIP70CertificateFailure] = [.missingCertificate, .untrustedChain, .invalidSignature,
                                                   .unsupportedSignatureType]
        for failure in failures {
            XCTAssertEqual(error(verdict("x509+sha256", valid: false, failure: failure)),
                           .untrustedCertificate(failure))
        }
    }

    // MARK: Interactive policy + confirm-screen rows (unsigned requests)

    private func unsignedNamed(_ name: String?, outputs: [PaymentOutput]? = nil) -> PaymentRequest {
        let outs = outputs ?? [PaymentOutput(amount: 100_000, script: p2pkh)]
        let details = PaymentDetails(network: "test", outputs: outs, expires: futureExpiry,
                                     memo: nil, paymentURL: "http://h/pay", merchantData: nil)
        let pkiData = name.map { X509Certificates(certificates: [Data($0.utf8)]).encoded() }
        return PaymentRequest(pkiType: "none", pkiData: pkiData, serializedDetails: details.encoded())
    }

    private func paymentOutput(for request: PaymentRequest, isSecure: Bool? = nil) async throws -> DWPaymentOutput {
        let confirmation = try await service(FakeTransport(request), FakeWallet())
            .prepareForConfirmation(from: url, scheme: "dash", network: .testnet)
        let box = BIP70ConfirmationBox(confirmation)
        guard let isSecure else { return BIP70PaymentOutputFactory.paymentOutput(from: box) }
        // The lock is a property of the output, so a signed one is built directly here: a
        // request that verifies as signed needs a certificate the simulator trusts.
        return DWPaymentOutput(merchantName: box.merchantName, isSecure: isSecure, amount: box.amount,
                               fee: box.estimatedFee, address: box.primaryAddress ?? "", memo: box.memo,
                               bip70Confirmation: box)
    }

    /// The confirm screen reads an output through this protocol; Swift only sees the
    /// conformance at runtime (the Objective-C category forward-declares the protocol).
    private func rows(of output: DWPaymentOutput) throws -> ConfirmPaymentDataSource {
        try XCTUnwrap(output as AnyObject as? ConfirmPaymentDataSource)
    }

    private func addressRow(of output: DWPaymentOutput) throws -> DWTitleDetailItem? {
        try rows(of: output).address(with: UIFont.systemFont(ofSize: 12), tintColor: UIColor.black)
    }

    func testUnsignedNameIsCarriedButNotSecure() {
        let verdict = PaymentRequestVerifier().verify(unsignedNamed("Coffee Shop"))
        XCTAssertEqual(verdict.commonName, "Coffee Shop")
        XCTAssertFalse(verdict.isSecure)
    }

    func testUnsignedNamedRequestShowsAddressAndUnverifiedLabel() async throws {
        let output = try await paymentOutput(for: unsignedNamed("Coffee Shop"))
        XCTAssertEqual(try addressRow(of: output)?.attributedDetail?.string, Self.testnetAddress)
        XCTAssertEqual(try rows(of: output).nameInfo?.plainDetail, "Unverified recipient: Coffee Shop")
    }

    func testUnsignedNamelessRequestShowsAddressAndUnverifiedLabel() async throws {
        let output = try await paymentOutput(for: unsignedNamed(nil))
        XCTAssertEqual(try addressRow(of: output)?.attributedDetail?.string, Self.testnetAddress)
        XCTAssertEqual(try rows(of: output).nameInfo?.plainDetail, "Unverified recipient")
    }

    func testSignedRequestKeepsNameInPlaceOfAddress() async throws {
        let output = try await paymentOutput(for: unsignedNamed("Coffee Shop"), isSecure: true)
        XCTAssertNil(try addressRow(of: output))
        XCTAssertEqual(try rows(of: output).nameInfo?.plainDetail, "🔒 Coffee Shop")
    }

    func testSignedMultiOutputRequestSaysHowManyAddressesItPays() async throws {
        let outs = [PaymentOutput(amount: 100_000, script: p2pkh), PaymentOutput(amount: 200_000, script: p2sh)]
        let output = try await paymentOutput(for: unsignedNamed("Coffee Shop", outputs: outs), isSecure: true)
        XCTAssertEqual(try rows(of: output).generalInfo?.plainDetail, "This payment goes to 2 addresses.")
    }

    func testUnsignedOutputAlwaysRequiresAuthentication() async throws {
        let output = try await paymentOutput(for: unsignedNamed("Coffee Shop"))
        XCTAssertFalse(output.isSecure)
        XCTAssertTrue(BIP70InteractiveCoordinator.requiresAuthentication(for: output, spendingConfirmationDisabled: false))
        XCTAssertTrue(BIP70InteractiveCoordinator.requiresAuthentication(for: output, spendingConfirmationDisabled: true))
    }

    func testSignedOutputFollowsTheSpendingConfirmationSetting() async throws {
        let output = try await paymentOutput(for: unsignedNamed("Coffee Shop"), isSecure: true)
        XCTAssertTrue(BIP70InteractiveCoordinator.requiresAuthentication(for: output, spendingConfirmationDisabled: false))
        XCTAssertFalse(BIP70InteractiveCoordinator.requiresAuthentication(for: output, spendingConfirmationDisabled: true))
    }

    private var twoAddresses: [PaymentOutput] {
        [PaymentOutput(amount: 100_000, script: p2pkh), PaymentOutput(amount: 200_000, script: p2sh)]
    }

    private func coordinator(_ request: PaymentRequest, allowsInsecureTransport: Bool) -> BIP70InteractiveCoordinator {
        BIP70InteractiveCoordinator(service: service(FakeTransport(request), FakeWallet()),
                                    allowsInsecureTransport: allowsInsecureTransport)
    }

    private func prepare(_ request: PaymentRequest, allowsInsecureTransport: Bool = true) async throws -> Confirmation {
        try await coordinator(request, allowsInsecureTransport: allowsInsecureTransport)
            .prepare(requestURL: url, scheme: "pay", callbackScheme: nil, network: .testnet)
    }

    func testUnsignedRequestPayingTwoAddressesIsAllowedAndSaysSo() async throws {
        let confirmation = try await prepare(unsignedNamed(nil, outputs: twoAddresses))
        XCTAssertEqual(BIP70ConfirmationBox(confirmation).recipientCount, 2)

        let output = try await paymentOutput(for: unsignedNamed(nil, outputs: twoAddresses))
        // The address row shows the first address, and its title says there are more.
        XCTAssertEqual(try addressRow(of: output)?.title, "Send to (1 of 2)")
        let single = try await paymentOutput(for: unsignedNamed(nil))
        XCTAssertEqual(try addressRow(of: single)?.title, "Send to")
        let info = try XCTUnwrap(try rows(of: output).generalInfo?.plainDetail)
        XCTAssertTrue(info.contains("This payment goes to 2 addresses."))
        // Each address is listed with the amount it receives.
        let lines = BIP70ConfirmationBox(confirmation).recipientLines
        XCTAssertEqual(lines.count, 2)
        for (line, recipient) in zip(lines, confirmation.recipients) {
            XCTAssertTrue(line.hasSuffix(" DASH: " + recipient.address))
            XCTAssertEqual(line, "\(recipient.amount.formattedDashAmountWithoutCurrencySymbol) DASH: \(recipient.address)")
            XCTAssertTrue(info.contains(line))
        }

        // 0.001 and 0.002 DASH, each next to its own address (digits only: the separator follows the locale).
        XCTAssertEqual(confirmation.recipients.map(\.amount), [100_000, 200_000])
        XCTAssertEqual(lines.map { $0.prefix { $0 != " " }.filter(\.isNumber) }, ["0001", "0002"])

        // A signed request keeps the count line only: its signer answers for the outputs.
        let signed = try await paymentOutput(for: unsignedNamed(nil, outputs: twoAddresses), isSecure: true)
        let signedInfo = try XCTUnwrap(try rows(of: signed).generalInfo?.plainDetail)
        XCTAssertTrue(signedInfo.contains("This payment goes to 2 addresses."))
        XCTAssertFalse(signedInfo.contains(lines[0]))
    }

    func testTwoOutputsToOneAddressCountAsOneAddress() async throws {
        let sameAddress = [PaymentOutput(amount: 100_000, script: p2pkh), PaymentOutput(amount: 200_000, script: p2pkh)]
        let confirmation = try await prepare(unsignedNamed(nil, outputs: sameAddress))
        XCTAssertEqual(confirmation.amount, 300_000)
        XCTAssertEqual(BIP70ConfirmationBox(confirmation).recipientCount, 1)
        let subtotals = BIP70InteractivePolicy.subtotals(of: confirmation)
        XCTAssertEqual(subtotals.count, 1)
        XCTAssertEqual(subtotals.first?.amount, 300_000)
    }

    func testCoordinatorRefusesAnHTTPPaymentURLWhenHTTPSIsRequired() async throws {
        // `unsignedNamed` carries payment_url "http://h/pay".
        do {
            _ = try await prepare(unsignedNamed("Coffee Shop"), allowsInsecureTransport: false)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? BIP70Error, .insecureTransport)
            XCTAssertTrue(BIP70InteractiveCoordinator.isRefusal(BIP70InteractiveCoordinator.nsError(error)))
        }
        _ = try await prepare(unsignedNamed("Coffee Shop"), allowsInsecureTransport: true)
        XCTAssertFalse(BIP70InteractiveCoordinator.isRefusal(BIP70InteractiveCoordinator.nsError(BIP70Error.expired)))
    }

    func testCoordinatorRefusesAPaymentURLThatDoesNotParse() async throws {
        let details = PaymentDetails(network: "test", outputs: [PaymentOutput(amount: 100_000, script: p2pkh)],
                                     expires: futureExpiry, memo: nil, paymentURL: "https://[h/pay", merchantData: nil)
        XCTAssertNil(URL(string: "https://[h/pay"))
        let request = PaymentRequest(pkiType: "none", pkiData: nil, serializedDetails: details.encoded())
        do {
            _ = try await prepare(request, allowsInsecureTransport: true)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? BIP70Error, .malformedRequest)
        }
    }

    func testUnsignedNoteIsLabelledFlattenedAndCapped() async throws {
        let details = PaymentDetails(network: "test", outputs: [PaymentOutput(amount: 100_000, script: p2pkh)],
                                     expires: futureExpiry, memo: "Verified merchant:\n  Coffee Shop\n" + String(repeating: "x", count: 300),
                                     paymentURL: "http://h/pay", merchantData: nil)
        let request = PaymentRequest(pkiType: "none", pkiData: nil, serializedDetails: details.encoded())
        let unsignedOutput = try await paymentOutput(for: request)
        let unsignedNote = try XCTUnwrap(try rows(of: unsignedOutput).generalInfo?.plainDetail)
        XCTAssertEqual(String(unsignedNote.prefix(49)), "Unverified note: Verified merchant: Coffee Shop x")
        XCTAssertFalse(unsignedNote.contains("\n"))
        XCTAssertEqual(unsignedNote.count, "Unverified note: ".count + 140)
        XCTAssertTrue(unsignedNote.hasSuffix("…"))

        let signedOutput = try await paymentOutput(for: request, isSecure: true)
        let signedNote = try XCTUnwrap(try rows(of: signedOutput).generalInfo?.plainDetail)
        XCTAssertTrue(signedNote.hasPrefix("Verified merchant:"))
        XCTAssertGreaterThan(signedNote.count, 300)
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

    /// dashpay/dashwallet-ios#1383: Receive's payment requests on Platform, Shielded and Identity carry a bech32m
    /// address or a bare Base58 Identity ID before `?amount=`; the URI hands it over whole, with the amount.
    func testURICarriesABech32mAddressOrAnIdentityIDWithItsAmount() throws {
        let platform = try XCTUnwrap(Bech32m.encode(
            hrp: Bech32m.platformHrp(mainnet: false), data: Data([0xb0] + Array(repeating: 0x02, count: 20))))
        let shielded = try XCTUnwrap(Bech32m.encode(
            hrp: Bech32m.platformHrp(mainnet: false), data: Data([0x10] + Array(repeating: 0x07, count: 43))))
        let identityID = ScriptAddressCodec.base58Encode(Data((1 ... 32).map { UInt8($0 * 3) }))

        for address in [platform, shielded, identityID] {
            let uri = BIP70URI("dash:\(address)?amount=0.1")
            XCTAssertEqual(uri?.address, address)
            XCTAssertEqual(uri?.amount, 10_000_000)
            XCTAssertEqual(uri?.isBIP70, false)
        }
    }

    func testURIRejectsNonPaymentScheme() {
        XCTAssertNil(BIP70URI("http://foo"))
    }

    // MARK: - L5 URI — new parse-side params + amount parity

    func testURICarriesUserCurrencyLocalSender() {
        let uri = BIP70URI("dash:Xabc?user=alice&currency=USD&local=12.5&req-sender=ctx")
        XCTAssertEqual(uri?.dashpayUsername, "alice")
        XCTAssertEqual(uri?.fiatCurrencyCode, "USD")
        XCTAssertEqual(uri?.fiatAmount, 12.5)
        XCTAssertEqual(uri?.callbackScheme, "ctx")
    }

    func testURIAmountRoundsUpSubDuff() {
        // 0.000000001 DASH = 0.1 duff → rounds up to 1 (DSPaymentRequest.m:146 NSRoundUp parity).
        XCTAssertEqual(BIP70URI("dash:X?amount=0.000000001")?.amount, 1)
    }

    func testURIAmountNegativeIsAbsent() {
        XCTAssertNil(BIP70URI("dash:X?amount=-5")?.amount)
    }

    func testURIAmountPresenceIsKeptApartFromItsValue() {
        for value in ["-5", "abc", "", "1e30", "184467440738"] {
            let uri = BIP70URI("dash:X?amount=\(value)")
            XCTAssertNil(uri?.amount, value)
            XCTAssertEqual(uri?.hasInvalidAmount, true, value)
        }
        XCTAssertEqual(BIP70URI("dash:X")?.hasInvalidAmount, false)
        XCTAssertEqual(BIP70URI("dash:X?amount=1")?.hasInvalidAmount, false)
        XCTAssertEqual(BIP70URI("dash:X?amount=184467440737.09551615")?.amount, UInt64.max)
    }

    func testURIRequiredFields() {
        XCTAssertEqual(BIP70URI("dash:X?req-foo=1&req-amount=1&req-r=https://a.b/c")?.requiredFields, ["foo", "amount", "r"])
        XCTAssertEqual(BIP70URI("dash:X?amount=1")?.requiredFields, [])
    }

    func testURIAmountMustParseWhollyAndOnce() {
        for value in ["1abc", "1,5", "1.2.3", "1e", "1e3x", "+1", "."] {
            let uri = BIP70URI("dash:X?amount=\(value)")
            XCTAssertNil(uri?.amount, value)
            XCTAssertEqual(uri?.hasInvalidAmount, true, value)
        }
        let repeated = BIP70URI("dash:X?req-amount=-1&amount=1")
        XCTAssertNil(repeated?.amount)
        XCTAssertEqual(repeated?.hasInvalidAmount, true)
        XCTAssertEqual(BIP70URI("dash:X?amount=.5")?.amount, 50_000_000)
    }

    /// O53: a payment page that repeats the link's own amount still means that amount; two different amounts, or an
    /// invalid one next to a valid one in either order, leave it open.
    func testURIRepeatedAmountIsKeptOnlyWhenEqual() {
        for link in ["dash:X?amount=1&amount=1", "dash:X?amount=1&req-amount=1.0", "dash:X?req-amount=1&amount=1e0"] {
            let uri = BIP70URI(link)
            XCTAssertEqual(uri?.amount, 100_000_000, link)
            XCTAssertEqual(uri?.hasInvalidAmount, false, link)
        }
        for link in ["dash:X?amount=1&amount=2", "dash:X?amount=1&amount=-1", "dash:X?amount=abc&amount=1",
                     "dash:X?amount=1&amount=1&amount=2"] {
            let uri = BIP70URI(link)
            XCTAssertNil(uri?.amount, link)
            XCTAssertEqual(uri?.hasInvalidAmount, true, link)
        }
    }

    /// O53: the existing Send prefills a repeated amount and rejects a link whose amount is invalid instead of
    /// opening it with no amount.
    func testParsedBoxKeepsARepeatedAmountAndRejectsAnInvalidOne() {
        let address = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        let repeated = ParsedPaymentURI.parse(paymentString: "dash:\(address)?amount=1&amount=1")
        XCTAssertEqual(repeated.amount, 100_000_000)
        XCTAssertEqual(repeated.address, address)

        let omitted = ParsedPaymentURI.parse(paymentString: "dash:\(address)")
        XCTAssertEqual(omitted.amount, 0)
        XCTAssertEqual(omitted.address, address)

        for link in ["dash:\(address)?amount=1&amount=2", "dash:\(address)?amount=-1"] {
            let box = ParsedPaymentURI.parse(paymentString: link)
            XCTAssertNil(box.address, link)
            XCTAssertFalse(box.isAddressPayableForCurrentNetwork, link)
        }
    }

    /// O56: `sender` and `req-sender` with different values leave the app to call back open; the same value is kept.
    func testURIConflictingCallbackIsFlaggedNotReplaced() {
        let conflicting = BIP70URI("dash:X?req-sender=shopapp&sender=other")
        XCTAssertEqual(conflicting?.hasConflictingCallback, true)
        XCTAssertNil(conflicting?.callbackScheme)
        let reversed = BIP70URI("dash:X?sender=other&req-sender=shopapp")
        XCTAssertEqual(reversed?.hasConflictingCallback, true)
        XCTAssertNil(reversed?.callbackScheme)
        let same = BIP70URI("dash:X?sender=shopapp&req-sender=shopapp")
        XCTAssertEqual(same?.hasConflictingCallback, false)
        XCTAssertEqual(same?.callbackScheme, "shopapp")
        XCTAssertEqual(BIP70URI("dash:X?req-sender=shopapp")?.callbackScheme, "shopapp")
        // The box drops the address on every network; the payable verdict alone would pass on mainnet for this
        // testnet address.
        let box = ParsedPaymentURI.parse(paymentString: "dash:yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW?sender=a&sender=b")
        XCTAssertNil(box.address)
        XCTAssertFalse(box.isAddressPayableForCurrentNetwork)
    }

    /// O76: URL schemes are case-insensitive, so `sender=ShopApp` and `req-sender=shopapp` name one app.
    func testURICallbacksDifferingOnlyInCaseAreOneCallback() {
        for link in ["dash:X?sender=ShopApp&req-sender=shopapp", "dash:X?req-sender=shopapp&sender=ShopApp"] {
            let uri = BIP70URI(link)
            XCTAssertEqual(uri?.hasConflictingCallback, false, link)
            XCTAssertEqual(uri?.callbackScheme?.lowercased(), "shopapp", link)
        }
        XCTAssertEqual(BIP70URI("dash:X?sender=ShopApp&req-sender=otherapp")?.hasConflictingCallback, true)
    }

    /// Many repeats of a callback after a long first value are compared with that value normalized once, and not at
    /// all after the first conflict: the deep-link path parses on the main thread. The test checks the verdict, not
    /// the time it takes, so a paused simulator cannot fail it.
    func testURIRepeatedCallbacksAreComparedWithTheFirstNormalizedOnce() {
        let long = String(repeating: "A", count: 200_000)
        let repeats = Array(repeating: "sender=b", count: 20_000).joined(separator: "&")
        let uri = BIP70URI("dash:X?sender=\(long)&\(repeats)")
        XCTAssertEqual(uri?.hasConflictingCallback, true)
        XCTAssertNil(uri?.callbackScheme)
        let same = BIP70URI("dash:X?sender=ShopApp&" + Array(repeating: "req-sender=shopapp", count: 3).joined(separator: "&"))
        XCTAssertEqual(same?.hasConflictingCallback, false)
        XCTAssertEqual(same?.callbackScheme, "ShopApp")
    }

    /// A field name is checked for whitespace as it is read, decoded: `req%20r` is as broken as `req r`. An encoded
    /// space in a value is a value.
    func testURIFieldNameWithEncodedWhitespaceIsMalformed() {
        for link in ["dash:X?amount=1&req%20r=https://h.example/pr", "dash:X?amount=1&req%0Ar=https://h.example/pr",
                     "dash:X?amount=1&req r=https://h.example/pr"] {
            XCTAssertEqual(BIP70URI(link)?.hasMalformedQuery, true, link)
            XCTAssertNil(BIP70URI(link)?.amountSource, link)
        }
        XCTAssertEqual(BIP70URI("dash:X?label=Coffee%20Shop&amount=1")?.hasMalformedQuery, false)
    }

    /// The one judgement of a link's terms: the link's own amount, the request's when the optional amount is malformed
    /// beside one fetchable request, otherwise nothing.
    func testURIAmountSource() {
        let cases: [(String, BIP70URI.AmountSource?)] = [
            ("dash:X?amount=1", .link),
            ("dash:X", .link),
            ("dash:X?amount=abc&r=https://h.example/pr", .paymentRequest),
            ("dash:X?amount=1&amount=2&r=https://h.example/pr", .paymentRequest),
            ("dash:X?amount=abc", nil),
            ("dash:X?amount=abc&r=ftp://h.example/pr", nil),
            ("dash:X?req-amount=abc&r=https://h.example/pr", nil),
            ("dash:X?amount=abc&r=https://a.example/pr&r=https://b.example/pr", nil),
            ("dash:X?amount=1&r=https://a.example/pr&req-r=https://b.example/pr", nil),
            ("dash:X?amount=1&r=https://h.example/pr&req-r=https://h.example/pr", .link),
            ("dash:X?amount=abc&r=https://h.example/pr&req-r=https://h.example/pr", .paymentRequest),
            ("dash:X?sender=a&sender=b", nil),
            ("dash:X?req-label=a&label=b", nil),
        ]
        for (link, expected) in cases {
            XCTAssertEqual(BIP70URI(link)?.amountSource, expected, link)
        }
    }

    /// The scanner and deep links refuse an invoice with competing payment requests whatever its amount, as the new
    /// Send and DashSpend do: which request it means is open.
    func testParsedBoxRejectsCompetingPaymentRequests() {
        let address = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        for amount in ["amount=abc", "amount=1"] {
            let box = ParsedPaymentURI.parse(
                paymentString: "dash:\(address)?\(amount)&r=https%3A%2F%2Fa.example%2Fpr&r=https%3A%2F%2Fb.example%2Fpr")
            XCTAssertNil(box.rURL, amount)
            XCTAssertNil(box.address, amount)
            XCTAssertFalse(box.isValidDashPaymentIntent, amount)
        }
    }

    /// The scanner and deep links fetch an invoice that names the same request in `r` and `req-r`: one request, no
    /// choice to make.
    func testParsedBoxFetchesAnInvoiceThatRepeatsItsRequest() {
        let address = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        let request = "https%3A%2F%2Fh.example%2Fpr"
        for amount in ["amount=abc", "amount=1"] {
            let box = ParsedPaymentURI.parse(paymentString: "dash:\(address)?\(amount)&r=\(request)&req-r=\(request)")
            XCTAssertEqual(box.rURL?.absoluteString, "https://h.example/pr", amount)
            XCTAssertTrue(box.isValidDashPaymentIntent, amount)
        }
    }

    /// O73: a scanned merchant invoice with a malformed optional amount keeps its request URL, so the scanner fetches
    /// it, and loses its address, so a failed fetch never pays the address instead. Off a request, the link stays
    /// rejected.
    func testParsedBoxKeepsTheRequestAndDropsTheAddressBesideAMalformedOptionalAmount() {
        let address = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        for amount in ["amount=abc", "amount=1&amount=2"] {
            let box = ParsedPaymentURI.parse(paymentString: "dash:\(address)?\(amount)&r=https%3A%2F%2Fh.example%2Fpr")
            XCTAssertEqual(box.rURL?.absoluteString, "https://h.example/pr", amount)
            XCTAssertNil(box.address, amount)
            XCTAssertTrue(box.isValidDashPaymentIntent, amount)
            XCTAssertFalse(box.byClearingRequestURL().isValidDashPaymentIntent, amount)
        }
        for link in ["dash:\(address)?req-amount=abc&r=https%3A%2F%2Fh.example%2Fpr", "dash:\(address)?amount=abc"] {
            let box = ParsedPaymentURI.parse(paymentString: link)
            XCTAssertNil(box.rURL, link)
            XCTAssertNil(box.address, link)
        }
    }

    /// O74 / O77: the box rejects a link whose query is broken across lines or words, or whose required label is
    /// given twice with different values, as the new Send's parser does.
    func testParsedBoxRejectsABrokenQueryAndAConflictingRequiredLabel() {
        let address = "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW"
        for link in ["dash:\(address)?amount=1&\nreq-r=https://h.example/pr", "dash:\(address)?amount=1& req-r=https://h.example/pr",
                     "dash:\(address)?req-label=Invoice&label=Personal"] {
            let box = ParsedPaymentURI.parse(paymentString: link)
            XCTAssertNil(box.address, link)
            XCTAssertNil(box.rURL, link)
        }
    }

    /// O33: the interactive payment-link flow shows a payment the merchant acknowledged as one that may still
    /// complete, not as a plain failure carrying only the expiry or broadcast reason.
    func testTheInteractiveBridgeShowsAnAcknowledgedPaymentAsMayStillComplete() {
        let error = BIP70Error.failedAfterAcknowledgement(txHashDisplay: Data(repeating: 1, count: 32),
                                                          reason: "The payment request has expired.")
        let shown = BIP70InteractiveCoordinator.nsError(error).localizedDescription
        XCTAssertNotEqual(shown, "The payment request has expired.")
        XCTAssertEqual(shown, BIP70Error.acknowledgedPaymentMessage)
    }

    /// Payment requests are counted by value, whether or not it parses: the same URL in `r` and `req-r` is one request
    /// (required), two different ones are two.
    func testURICountsPaymentRequestsWhetherOrNotTheyParse() {
        XCTAssertEqual(BIP70URI("dash:X?amount=1")?.paymentRequestCount, 0)
        let unparseable = BIP70URI("dash:X?r=https://[")
        XCTAssertNil(unparseable?.r)
        XCTAssertEqual(unparseable?.paymentRequestCount, 1)
        let repeated = BIP70URI("dash:X?r=https://a.b/c&req-r=https://a.b/c")
        XCTAssertEqual(repeated?.paymentRequestCount, 1)
        XCTAssertEqual(repeated?.fetchableRequestURL?.absoluteString, "https://a.b/c")
        XCTAssertEqual(repeated?.requiredFields.contains("r"), true)
        XCTAssertEqual(BIP70URI("dash:X?r=https://a.b/c&req-r=https://a.b/d")?.paymentRequestCount, 2)
        XCTAssertEqual(BIP70URI("dash:X?r=https://[&r=https://a.b/c")?.paymentRequestCount, 2)
    }

    /// `é` composed and `é` decomposed are equal Strings but different URL paths: two requests, parsed or not.
    func testURICountsCanonicallyEqualRequestsWithDifferentBytesAsTwo() {
        XCTAssertEqual(BIP70URI("dash:X?r=https://a.b/caf%C3%A9&req-r=https://a.b/cafe%CC%81")?.paymentRequestCount, 2)
        XCTAssertEqual(BIP70URI("dash:X?r=https://[%C3%A9&r=https://[e%CC%81")?.paymentRequestCount, 2)
        let repeated = BIP70URI("dash:X?r=https://a.b/caf%C3%A9&req-r=https://a.b/caf%C3%A9")
        XCTAssertEqual(repeated?.paymentRequestCount, 1)
        XCTAssertNotNil(repeated?.fetchableRequestURL)
    }

    func testURIAmountExponent() {
        XCTAssertEqual(BIP70URI("dash:X?amount=1e2")?.amount, 10_000_000_000)
    }

    /// BUG-25: a scanned `dash:<address>&amount=…` (no `?`) used to put the whole
    /// tail into the address, so the request was rejected instead of paying.
    func testURIAcceptsAmpersandAsQuerySeparator() {
        let uri = BIP70URI("dash:ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr&amount=0.23243214")

        XCTAssertEqual(uri?.address, "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr")
        XCTAssertEqual(uri?.amount, 23_243_214)
    }

    /// The `&` form must still parse every following pair, exactly like `?`.
    func testURIAmpersandSeparatorParsesRemainingPairs() {
        let uri = BIP70URI("dash:Xabc&amount=1.5&label=Coffee&sender=ctx")

        XCTAssertEqual(uri?.address, "Xabc")
        XCTAssertEqual(uri?.amount, 150_000_000)
        XCTAssertEqual(uri?.label, "Coffee")
        XCTAssertEqual(uri?.callbackScheme, "ctx")
    }

    /// BUG-25/BUG-26: a full-precision amount must survive the URI parse. The
    /// display side is covered by `DashAmountFormatterTests`.
    func testURIKeepsAllEightDecimals() {
        XCTAssertEqual(BIP70URI("dash:X?amount=0.23243214")?.amount, 23_243_214)
    }

    // MARK: - L5 URI — paymentString init (bare address / BIP73)

    func testPaymentStringBareAddress() {
        let uri = BIP70URI(paymentString: "yeRZBWYfeNE4yVUHV4ZLs83Ppn9aMRH57A")
        XCTAssertEqual(uri?.kind, .bareAddress)
        XCTAssertEqual(uri?.scheme, "dash")
        XCTAssertEqual(uri?.isBIP70, false)
        XCTAssertEqual(uri?.address, "yeRZBWYfeNE4yVUHV4ZLs83Ppn9aMRH57A")
    }

    func testPaymentStringBareGarbageIsCarriedNotNil() {
        let uri = BIP70URI(paymentString: "certainly not dash")
        XCTAssertEqual(uri?.kind, .bareAddress)
        XCTAssertEqual(uri?.address, "certainly not dash")
        XCTAssertEqual(uri?.isBIP70, false)
    }

    func testPaymentStringHTTPBIP73() {
        let uri = BIP70URI(paymentString: "http://h/pr")
        XCTAssertEqual(uri?.kind, .bip73URL)
        XCTAssertEqual(uri?.scheme, "http")
        XCTAssertEqual(uri?.r?.absoluteString, "http://h/pr")
    }

    func testPaymentStringBIP73SpaceEncoded() {
        let uri = BIP70URI(paymentString: "http://h/pr with space")
        XCTAssertEqual(uri?.r?.absoluteString, "http://h/pr%20with%20space")
    }

    func testPaymentStringMailtoIsNil() {
        XCTAssertNil(BIP70URI(paymentString: "mailto:foo@bar"))
    }

    func testPaymentStringEmptyIsNil() {
        XCTAssertNil(BIP70URI(paymentString: "   "))
    }

    func testPaymentStringStripsDashSlashes() {
        let uri = BIP70URI(paymentString: "dash://Xabc?amount=1.5")
        XCTAssertEqual(uri?.kind, .paymentURI)
        XCTAssertEqual(uri?.address, "Xabc")
        XCTAssertEqual(uri?.amount, 150_000_000)
    }

    // MARK: - DWParsedPaymentURI box (structural; the address verdict is network-dependent)

    func testParsedBoxIsTotalForUnparseable() {
        let box = ParsedPaymentURI.parse(paymentString: "mailto:foo@bar")
        XCTAssertEqual(box.rawString, "mailto:foo@bar")
        XCTAssertNil(box.scheme)
        XCTAssertFalse(box.hasExplicitScheme)
        XCTAssertFalse(box.isValidDashPaymentIntent)
    }

    func testParsedBoxBIP72IsValidIntentViaRURL() {
        // Address-less `dash:?r=` is a valid intent regardless of the network address verdict.
        let box = ParsedPaymentURI.parse(paymentString: "dash:?r=http%3A%2F%2Fh%2Fpr")
        XCTAssertEqual(box.scheme, "dash")
        XCTAssertNotNil(box.rURL)
        XCTAssertTrue(box.isValidDashPaymentIntent)
        XCTAssertTrue(box.hasExplicitScheme)
    }

    func testParsedBoxClearRequestURLCollapsesIntent() {
        let cleared = ParsedPaymentURI.parse(paymentString: "dash:?r=http%3A%2F%2Fh%2Fpr").byClearingRequestURL()
        XCTAssertNil(cleared.rURL)
        // No address + no r ⇒ not a valid intent (mirrors the fetch-failed `request.r = nil` re-eval).
        XCTAssertFalse(cleared.isValidDashPaymentIntent)
    }

    func testParsedBoxBareCarriesAddressAndAmount() {
        let box = ParsedPaymentURI.parse(paymentString: "dash:Xabc?amount=1.5&user=bob")
        XCTAssertEqual(box.address, "Xabc")
        XCTAssertEqual(box.amount, 150_000_000)
        XCTAssertEqual(box.dashpayUsername, "bob")
        XCTAssertTrue(box.hasExplicitScheme)
    }

    /// #1092: a scanned `dashwallet://pay=` link pays the address and amount the same link pays
    /// when opened as a deep link. #1219: it names no app and calls none back.
    func testParsedBoxReadsDashWalletPayLinkLikeDeepLink() {
        let link = "dashwallet://pay=yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW&amount=0.01916910&sender=v4v.app"
        let box = ParsedPaymentURI.parse(paymentString: link)
        XCTAssertEqual(box.rawString, link)
        XCTAssertEqual(box.scheme, "dash")
        XCTAssertEqual(box.address, "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW")
        XCTAssertEqual(box.amount, 1_916_910)
        // #1219: the wallet read this link itself, so no app is named or called back.
        XCTAssertNil(box.callbackScheme)
        XCTAssertNil(box.label)
    }

    /// #1219: a link the wallet read itself keeps the label its author gave it.
    func testParsedBoxKeepsOwnLabelOfDashWalletPayLink() {
        let box = ParsedPaymentURI.parse(
            paymentString: "dashwallet://pay=yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW&amount=1&sender=v4v.app&label=Shop")
        XCTAssertEqual(box.address, "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW")
        XCTAssertEqual(box.label, "Shop")
        XCTAssertNil(box.callbackScheme)
    }

    /// Without `sender` the deep-link router rejects a `pay=` link, so the scan still falls back to
    /// `BIP70URI` and stays unpayable: the deep link's own rule, not a scan-only one.
    func testParsedBoxDashWalletPayLinkWithoutSenderStaysRejected() {
        let box = ParsedPaymentURI.parse(paymentString: "dashwallet://pay=yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW&amount=1")
        // The rewrite was not applied: `BIP70URI` read the raw link, so `pay=` is still in the
        // address. This holds on every network; the verdicts below alone would also pass on
        // mainnet for a testnet address.
        XCTAssertEqual(box.address, "pay=yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW")
        XCTAssertFalse(box.isAddressPayableForCurrentNetwork)
        XCTAssertFalse(box.isValidDashPaymentIntent)
    }

    /// The plain `dashwallet:<address>` alias is not a deep-link action and still reads as `dash:`.
    func testParsedBoxKeepsPlainDashWalletAlias() {
        let box = ParsedPaymentURI.parse(paymentString: "dashwallet:Xabc?amount=1")
        XCTAssertEqual(box.scheme, "dash")
        XCTAssertEqual(box.address, "Xabc")
        XCTAssertEqual(box.amount, 100_000_000)
    }

    // MARK: - `sender` callback scheme (#1219)

    func testCallbackSchemeAcceptsBareCustomSchemes() {
        for scheme in ["ctx", "v4v.app", "my-app+x", "A1", "MyApp"] {
            XCTAssertEqual(CallbackScheme.validated(scheme), scheme, scheme)
        }
    }

    func testCallbackSchemeRejectsAnythingThatIsNotABareScheme() {
        let notSchemes = ["", "1abc", "+abc", "a b", "a:b", "a://b", "a/b", "x?y", "x#y",
                          "x&callback=evil", "ctx://evil?", "арр" /* Cyrillic */, "app\u{0}"]
        for value in notSchemes {
            XCTAssertNil(CallbackScheme.validated(value), value)
        }
        XCTAssertNil(CallbackScheme.validated(nil))
    }

    func testCallbackSchemeRejectsSystemAndOwnSchemes() {
        let blocked = ["http", "https", "HTTPS", "tel", "sms", "smsto", "geo", "mailto", "facetime", "facetime-audio",
                       "itms-apps", "x-apple-reminder", "app-settings", "workflow", "shareddocuments",
                       "dash", "DashWallet", "dashpay", "dashid", "DashID", "dash-key", "Dash-Key", "dash-st", "pay"]
        for scheme in blocked {
            XCTAssertNil(CallbackScheme.validated(scheme), scheme)
            XCTAssertNil(CallbackScheme.payAckURL(scheme: scheme, address: "Xabc", txid: "ab12"), scheme)
            XCTAssertNil(CallbackScheme.addressRequestURL(scheme: scheme, request: "address", address: "Xabc"), scheme)
        }
    }

    /// The wallet answers every scheme it registers, so none of them can be a callback.
    func testCallbackSchemeRejectsEverySchemeTheWalletRegisters() throws {
        let urlTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let registered = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertFalse(registered.isEmpty)
        for scheme in registered {
            XCTAssertNil(CallbackScheme.validated(scheme), scheme)
        }
    }

    func testCallbackSchemeHasALengthLimit() {
        XCTAssertNotNil(CallbackScheme.validated(String(repeating: "a", count: 64)))
        XCTAssertNil(CallbackScheme.validated(String(repeating: "a", count: 65)))
    }

    /// An invalid `sender` is dropped; the payment the link asks for is untouched.
    func testURIDropsInvalidSenderAndKeepsTheRest() {
        for sender in ["https", "ctx%3A%2F%2Fevil%3F", "ctx%26callback%3Devil", "tel"] {
            let uri = BIP70URI("dash:Xabc?amount=1.5&label=Coffee&sender=\(sender)")
            XCTAssertNil(uri?.callbackScheme, sender)
            XCTAssertEqual(uri?.address, "Xabc", sender)
            XCTAssertEqual(uri?.amount, 150_000_000, sender)
            XCTAssertEqual(uri?.label, "Coffee", sender)
        }
    }

    func testPayAckURLKeepsTheLegacyForm() {
        let url = CallbackScheme.payAckURL(scheme: "ctx", address: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr", txid: "ab12")
        XCTAssertEqual(url?.absoluteString, "ctx://callback=payack&address=ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr&txid=ab12")
    }

    /// The builder checks the scheme itself, so a caller that skipped validation opens nothing.
    func testCallbackURLsRefuseAnInvalidScheme() {
        XCTAssertNil(CallbackScheme.payAckURL(scheme: "https", address: "Xabc", txid: "ab12"))
        XCTAssertNil(CallbackScheme.payAckURL(scheme: "ctx://evil?", address: "Xabc", txid: "ab12"))
        XCTAssertNil(CallbackScheme.payAckURL(scheme: nil, address: "Xabc", txid: "ab12"))
        XCTAssertNil(CallbackScheme.payAckURL(scheme: "ctx", address: nil, txid: "ab12"))
        XCTAssertNil(CallbackScheme.addressRequestURL(scheme: "tel", request: "address", address: "Xabc"))
    }

    func testCallbackURLsEncodeTheirValues() {
        let payAck = CallbackScheme.payAckURL(scheme: "ctx", address: "Xabc&txid=evil#x", txid: "ab12")
        XCTAssertEqual(payAck?.absoluteString, "ctx://callback=payack&address=Xabc%26txid%3Devil%23x&txid=ab12")

        let request = CallbackScheme.addressRequestURL(scheme: "ctx", request: "address", address: "Xabc")
        XCTAssertEqual(request?.absoluteString, "ctx://callback=address&address=Xabc&source=dashwallet")
    }

    /// A deep link names the app that asked, as the link wrote it, and keeps it as the callback.
    func testDeepLinkPayActionNamesAValidSender() throws {
        let url = try XCTUnwrap(URL(string: "dashwallet://pay=Xabc&amount=1&sender=v4v.app&label=Shop"))
        let action = try XCTUnwrap(DWURLParser.action(for: url) as? DWURLPayAction)
        let uri = try XCTUnwrap(BIP70URI(action.paymentURL.absoluteString))
        XCTAssertEqual(uri.address, "Xabc")
        XCTAssertEqual(uri.amount, 100_000_000)
        XCTAssertEqual(uri.callbackScheme, "v4v.app")
        XCTAssertTrue(uri.label?.contains("v4v.app") ?? false)
        XCTAssertNotEqual(uri.label, "Shop")
    }

    /// An invalid `sender` on a deep link: the payment opens with the link's own label and no app.
    func testDeepLinkPayActionDropsAnInvalidSender() throws {
        let url = try XCTUnwrap(URL(string: "dashwallet://pay=Xabc&amount=1&sender=https&label=Shop"))
        let action = try XCTUnwrap(DWURLParser.action(for: url) as? DWURLPayAction)
        let uri = try XCTUnwrap(BIP70URI(action.paymentURL.absoluteString))
        XCTAssertEqual(uri.address, "Xabc")
        XCTAssertEqual(uri.amount, 100_000_000)
        XCTAssertNil(uri.callbackScheme)
        XCTAssertEqual(uri.label, "Shop")
        XCTAssertFalse(action.paymentURL.absoluteString.contains("sender"))
    }

    /// `BIP70URI` reads `req-sender` as `sender`, so an invalid `sender` must not leave a
    /// `req-sender` behind to be called back.
    func testDeepLinkPayActionDropsReqSenderWithAnInvalidSender() throws {
        let url = try XCTUnwrap(URL(string: "dashwallet://pay=Xabc&amount=1&sender=https&req-sender=foo"))
        let action = try XCTUnwrap(DWURLParser.action(for: url) as? DWURLPayAction)
        let uri = try XCTUnwrap(BIP70URI(action.paymentURL.absoluteString))
        XCTAssertEqual(uri.address, "Xabc")
        XCTAssertNil(uri.callbackScheme)
        XCTAssertFalse(action.paymentURL.absoluteString.contains("sender"))
    }

    /// The app named on screen and the app called back are the same one: `sender`.
    func testDeepLinkPayActionIgnoresReqSenderNextToAValidSender() throws {
        let url = try XCTUnwrap(URL(string: "dashwallet://pay=Xabc&amount=1&sender=ctx&req-sender=foo"))
        let action = try XCTUnwrap(DWURLParser.action(for: url) as? DWURLPayAction)
        let uri = try XCTUnwrap(BIP70URI(action.paymentURL.absoluteString))
        XCTAssertEqual(uri.callbackScheme, "ctx")
        XCTAssertTrue(uri.label?.contains("ctx") ?? false)
        XCTAssertFalse(action.paymentURL.absoluteString.contains("foo"))
    }

    /// A `req-label` cannot replace the label the wallet wrote for a valid `sender`.
    func testDeepLinkPayActionKeepsItsSenderLabelOverReqLabel() throws {
        let url = try XCTUnwrap(URL(string: "dashwallet://pay=Xabc&amount=1&sender=ctx&req-label=Shop"))
        let action = try XCTUnwrap(DWURLParser.action(for: url) as? DWURLPayAction)
        let uri = try XCTUnwrap(BIP70URI(action.paymentURL.absoluteString))
        XCTAssertTrue(uri.label?.contains("ctx") ?? false)
        XCTAssertFalse(action.paymentURL.absoluteString.contains("Shop"))
    }

    /// Without a valid `sender` a `req-label` is the link's own label, like `label`.
    func testDeepLinkPayActionKeepsReqLabelWithAnInvalidSender() throws {
        let url = try XCTUnwrap(URL(string: "dashwallet://pay=Xabc&amount=1&sender=https&req-label=Shop"))
        let action = try XCTUnwrap(DWURLParser.action(for: url) as? DWURLPayAction)
        let uri = try XCTUnwrap(BIP70URI(action.paymentURL.absoluteString))
        XCTAssertNil(uri.callbackScheme)
        XCTAssertEqual(uri.label, "Shop")
    }

    /// A link the wallet read itself carries no sender under either name.
    func testParsedBoxDropsReqSenderOfDashWalletPayLink() {
        let box = ParsedPaymentURI.parse(
            paymentString: "dashwallet://pay=yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW&amount=1&sender=ctx&req-sender=foo")
        XCTAssertEqual(box.address, "yRpspK93iBf5kASFGCnmkJ1VFGo2tCdFSW")
        XCTAssertNil(box.callbackScheme)
        XCTAssertNil(box.label)
    }

    func testAddressRequestNeedsAValidSender() throws {
        let valid = try XCTUnwrap(URL(string: "dashwallet://request=address&sender=ctx"))
        XCTAssertEqual((DWURLParser.action(for: valid) as? DWURLRequestAction)?.sender, "ctx")

        let invalid = try XCTUnwrap(URL(string: "dashwallet://request=address&sender=https"))
        XCTAssertNil(DWURLParser.action(for: invalid))
    }

    /// The same `dash:` link calls its `sender` back when another app opened it, and does not when
    /// the wallet read it itself.
    func testOnlyALinkAnotherAppOpenedKeepsItsCallback() throws {
        let address = try XCTUnwrap(["yeRZBWYfeNE4yVUHV4ZLs83Ppn9aMRH57A", "XrUv3aniSvZEKx2VoFe5fTqFfYL5JYFkbg"]
            .first { ParsedPaymentURI.parse(paymentString: $0).isAddressValidForCurrentNetwork })
        let link = "dash:\(address)?amount=0.001&sender=ctx"
        let builder = DWPaymentInputBuilder()

        let opened = builder.paymentInput(with: try XCTUnwrap(URL(string: link)))
        XCTAssertEqual(opened.source, .deepLink)
        XCTAssertEqual(opened.callbackScheme, "ctx")
        // The processor sends from the intent, so the gate must hold there too.
        XCTAssertEqual(opened.paymentIntent?.callbackScheme, "ctx")

        for source in [DWPaymentInputSource.pasteboard, .NFC] {
            var read: DWPaymentInput?
            builder.payFirst(from: [link], source: source) { read = $0 }
            XCTAssertEqual(read?.parsedURI?.callbackScheme, "ctx")
            XCTAssertNil(read?.callbackScheme)
            XCTAssertNil(read?.paymentIntent?.callbackScheme)
        }
    }

    // MARK: - PaymentURIBuilder (dash: serializer — DSPaymentRequest parity)

    private static let builderAddr = "yeRZBWYfeNE4yVUHV4ZLs83Ppn9aMRH57A"

    func testBuilderBareAddress() {
        XCTAssertEqual(PaymentURIBuilder(address: Self.builderAddr).string, "dash:\(Self.builderAddr)")
    }

    func testBuilderAmountTrailingZerosDropped() {
        XCTAssertEqual(PaymentURIBuilder(address: Self.builderAddr, amount: 25_000_000).string, "dash:\(Self.builderAddr)?amount=0.25")
        XCTAssertEqual(PaymentURIBuilder(address: Self.builderAddr, amount: 100_000_000).string, "dash:\(Self.builderAddr)?amount=1")
        XCTAssertEqual(PaymentURIBuilder(address: Self.builderAddr, amount: 1).string, "dash:\(Self.builderAddr)?amount=0.00000001")
    }

    func testBuilderLabelPercentEncoded() {
        let uri = PaymentURIBuilder(address: Self.builderAddr, amount: 10_000_000, label: "Sticker Pack",
                                    message: nil, requestURL: nil, fiatCurrencyCode: nil, fiatAmount: 0,
                                    dashpayUsername: nil).string
        XCTAssertEqual(uri, "dash:\(Self.builderAddr)?amount=0.1&label=Sticker%20Pack")
    }

    func testBuilderCurrencyLocalTwoDecimalsRaw() {
        let uri = PaymentURIBuilder(address: Self.builderAddr, amount: 0, label: nil, message: nil,
                                    requestURL: nil, fiatCurrencyCode: "USD", fiatAmount: 25.5,
                                    dashpayUsername: nil).string
        XCTAssertEqual(uri, "dash:\(Self.builderAddr)?currency=USD&local=25.50")
    }

    func testBuilderUserRaw() {
        let uri = PaymentURIBuilder(address: Self.builderAddr, amount: 50_000_000, label: nil, message: nil,
                                    requestURL: nil, fiatCurrencyCode: nil, fiatAmount: 0,
                                    dashpayUsername: "alice").string
        XCTAssertEqual(uri, "dash:\(Self.builderAddr)?amount=0.5&user=alice")
    }

    func testBuilderDataIsUTF8OfString() {
        let b = PaymentURIBuilder(address: Self.builderAddr, amount: 25_000_000)
        XCTAssertEqual(b.data, Data(b.string.utf8))
    }

    func testBuilderRoundTripsThroughParser() {
        let s = PaymentURIBuilder(address: Self.builderAddr, amount: 25_000_000).string
        let parsed = BIP70URI(paymentString: s)
        XCTAssertEqual(parsed?.address, Self.builderAddr)
        XCTAssertEqual(parsed?.amount, 25_000_000)
    }

    // MARK: - PaymentIntent (send carrier)

    func testPaymentIntentCarriesFields() {
        let intent = PaymentIntent(address: Self.builderAddr, amount: 10_000_000, label: "Coffee",
                                   message: "thanks", callbackScheme: "myapp", fiatCurrencyCode: "USD",
                                   fiatAmount: 25.5, dashpayUsername: "alice")
        XCTAssertEqual(intent.address, Self.builderAddr)
        XCTAssertEqual(intent.amount, 10_000_000)
        XCTAssertEqual(intent.label, "Coffee")
        XCTAssertEqual(intent.message, "thanks")
        XCTAssertEqual(intent.callbackScheme, "myapp")
        XCTAssertEqual(intent.fiatCurrencyCode, "USD")
        XCTAssertEqual(intent.fiatAmount, 25.5)
        XCTAssertEqual(intent.dashpayUsername, "alice")
    }

    func testPaymentIntentAmountIsSettableForSendOverride() {
        // `payToAddress:amount:` supplies a fixed send amount that is not a parse fact.
        let intent = PaymentIntent(address: Self.builderAddr, amount: 0, label: nil, message: nil,
                                   callbackScheme: nil, fiatCurrencyCode: nil, fiatAmount: 0,
                                   dashpayUsername: nil)
        intent.amount = 42_000_000
        XCTAssertEqual(intent.amount, 42_000_000)
    }
}

//
//  BIP70 protocol-core manual test harness (L1 codec + L2 verifier).
//
//  A standalone, dependency-free check that compiles the REAL source files from
//  DashWallet/Sources/Models/PaymentProtocol/ (not copies) together with this file and
//  asserts the protocol core's behaviour. Use it to verify L1/L2 without the Xcode test
//  target (which is currently compile-gated). Run via ./run.sh in this directory.
//
//  The fixture below is a real x509+sha256-signed PaymentRequest (1175 bytes) captured from
//  the bip70-dash test server (see BIP70_TESTING.md). It carries the full cert chain and a
//  256-byte RSA signature, so the signature/round-trip checks exercise real merchant bytes —
//  not a synthetic input. To refresh it, fetch a new request from the server and replace B64.
//

import Foundation
import Security

let B64 = "CAESC3g1MDkrc2hhMjU2GocGCoQGMIIDADCCAeigAwIBAgIJeF8eUl2va/tEMA0GCSqGSIb3DQEBCwUAMBwxGjAYBgNVBAMTEURhc2ggU3RpY2tlciBTaG9wMB4XDTI2MDYyOTA3MTI0MFoXDTI3MDYyOTA3MTI0MFowHDEaMBgGA1UEAxMRRGFzaCBTdGlja2VyIFNob3AwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCxelYthVoRtoiGR1BQ2tHnpw234RPUh6IIpx9u+Hikp8z2Ekk2NBqiFIPDi8Kd1RitITVn+/weivGJxOQ9K7iThUbHn8mw+iCIxWCMaWHUD+e2us2bDNgazibs7tpmaXTjK2vAcAgDRVBnlqiJG9i8+dE0nRynF5d8Yk8pzb9Nue4J5vkMYAYQ1tcuT2Lx2gTWDDOENyDW155TCjOmO9TkkCZkTQSYYV2YPKtEV8vaD/mtFDx6uhnYgxfqz4n1eK+a1gn1BYCRSI/KMugWU1Wk1caAkAB5fx7IeLIQU6rKz0kkyisVvaPfsnTdrHdeED+jrPWs/qyeQAuFB3fIvA+jAgMBAAGjRTBDMAwGA1UdEwQFMAMBAf8wCwYDVR0PBAQDAgL0MCYGA1UdEQQfMB2GG2h0dHA6Ly9leGFtcGxlLm9yZy93ZWJpZCNtZTANBgkqhkiG9w0BAQsFAAOCAQEAdyHL0WUTIyg8iwUQchYF4iS11Z6Qd9vmxD5wudeMDBfq6tJiIDfEvl1npnPogPo55EcmWBdwQWpaiV9sltCa+Y49JoOM65i/i+PjBWD3E9h0mAdNapm0yR/BgcyY+Co8LaIFnYo/9r3KV/OE7kOIVsQ2dcOgOn0sgCiPJSInHVXLQTjJUA53wlbibEzamA+GJxHHdvh2xgi+60tU0aCY+tp8OXN6bmaOZ9zXAd9HUhMJJRbCgvCFuz1UDz+pPbMA2KoY5MAJM7BvBVJe5x7tP6QuFqjHf0iL6v4tzIRZ2cOoGo/pkUfQAQBd420mNdirWDqkO9lktMwp7uJaHEKgeCJ5CgR0ZXN0Eh8IoI0GEhl2qRSqtEY2Cr6XL2tidvN0YYb+gsq9G4isGL3giNIGIM38iNIGKhlEYXNoIFN0aWNrZXIgLSAwLjAwMSBEQVNIMiZodHRwOi8vMTkyLjE2OC4wLjEwODozMDAwL3BheW1lbnQ/aWQ9MDoBMCqAAlyRLFTXZxc64H7iEoivPI4IEHQXSgfaQ0tFzK5piIXOv1Bb/Prk40GUhJcfJjk+WAZvxLFDwDg++KcWPTaMSF9797v5tFoGUfKAE1RldXUZekcB/r7eVuyYDpbmbTQKiNIGKLUi5FBmDN+3w2nS3zSwat9/ozel+iPNyaalJ2YYY2GcWnmtMVSAER2drCviPngYiY0bXDSx3t6/qyMTXLbAJo6J2NJr2+UeDXMsnBmq76x6+XFvA4vu7LKZf/86W+dgUgsiHW9GDDS+Xizm9qzaTbMukRHwfdFUxbUMcucz/Oltq17YxiXeBWIuWJ9AXdkzaMmko201pYltiQvQxO8="

var passed = 0, failed = 0
func check(_ name: String, _ cond: Bool) {
    if cond { passed += 1; print("  PASS  \(name)") } else { failed += 1; print("  FAIL  \(name)") }
}

let fixture = Data(base64Encoded: B64)!
let req = PaymentRequest(fixture)!
let d = req.details

print("L1 — codec / messages")
check("decode pkiType == x509+sha256", req.pkiType == "x509+sha256")
check("decode version == 1", req.version == 1)
check("decode signature is 256 bytes (RSA-2048)", req.signature?.count == 256)
check("decode network == test", d.network == "test")
check("decode 1 output of 100000 duffs (0.001 DASH)", d.outputs.count == 1 && d.outputs.first?.amount == 100000)
check("decode P2PKH output script (25 bytes)", d.outputs.first?.script.count == 25)
check("decode memo", d.memo == "Dash Sticker - 0.001 DASH")
check("ROUND-TRIP IDENTITY: encoded() == original bytes", req.encoded() == fixture)
check("empty-sig field emitted as 2a 00", req.encoded(signature: Data()).suffix(2) == Data([0x2a, 0x00]))
let out = PaymentOutput(amount: 5, script: Data([0xaa]))
check("Output golden bytes (08 05 12 01 aa)", out.encoded() == Data([0x08, 0x05, 0x12, 0x01, 0xaa]))
var varintOK = true
for v: UInt64 in [0, 1, 127, 128, 300, 16384, UInt64.max] {
    var w = ProtoWriter(); w.appendVarInt(v)
    var r = ProtoReader(w.data); if r.readVarInt() != v { varintOK = false }
}
check("varint round-trip (incl. UInt64.max)", varintOK)

// Hostile / corrupt wire input must never trap (Int(UInt64) overflow or out-of-range slice).
// Oversized length-delimited field: field 4 (details), wire type 2, declared length > Int.max.
var malformedW = ProtoWriter()
malformedW.appendVarInt(UInt64(4 << 3 | 2)) // key: field 4, wire type 2 (length-delimited)
malformedW.appendVarInt(UInt64.max)         // hostile declared length
var malformed = malformedW.data
malformed.append(0xAA)                       // far fewer bytes than declared
var malformedR = ProtoReader(malformed)
let malformedField = malformedR.readField()
check("L1 oversized length-delim returns nil, no crash", malformedField?.data == nil && malformedR.isAtEnd)

// Oversized field key/tag must not trap (raw key > Int.max before the fix).
var keyW = ProtoWriter(); keyW.appendVarInt(UInt64.max)
var keyR = ProtoReader(keyW.data)
_ = keyR.readField() // reaching the next line without trapping is the assertion
check("L1 oversized field key does not crash", true)

// End-to-end: a PaymentRequest whose details (field 4) declare an oversized length decodes to
// nil (serializedDetails never set) instead of crashing.
check("L1 PaymentRequest(maliciousLength) is nil, no crash", PaymentRequest(malformed) == nil)

print("\nL2 — verifier (crypto)")
let leaf = SecCertificateCreateWithData(nil, X509Certificates(req.pkiData!).certificates[0] as CFData)!
var trust: SecTrust?; SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &trust)
let pub = SecTrustCopyKey(trust!)!
var e1: Unmanaged<CFError>?
let sigOK = SecKeyVerifySignature(pub, .rsaSignatureMessagePKCS1v15SHA256, req.encoded(signature: Data()) as CFData, req.signature! as CFData, &e1)
check("REAL SIGNATURE verifies over empty-sig re-encode", sigOK)
var t2: SecTrust?; SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &t2); SecTrustSetAnchorCertificates(t2!, [leaf] as CFArray)
var e2: CFError?
check("chain validates when anchored (→ valid in-app w/ cert installed)", SecTrustEvaluateWithError(t2!, &e2))
let v = PaymentRequestVerifier().verify(req)
check("verifier extracts commonName 'Dash Sticker Shop'", v.commonName == "Dash Sticker Shop")
check("verifier rejects untrusted self-signed (CI)", v.isValid == false && (v.errorMessage?.contains("certificate") ?? false))

print("\nL2 — verifier (expiry / unsigned)")
let p2pkh = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0), count: 20) + [0x88, 0xac])
func unsigned(_ exp: UInt64) -> PaymentRequest {
    PaymentRequest(pkiType: "none", serializedDetails: PaymentDetails(network: "test", outputs: [PaymentOutput(amount: 100000, script: p2pkh)], expires: exp).encoded())
}
let vp = PaymentRequestVerifier().verify(unsigned(1))
check("past-expiry rejected ('Request expired')", vp.isValid == false && vp.errorMessage == "Request expired")
let vf = PaymentRequestVerifier().verify(unsigned(UInt64(Date().timeIntervalSince1970) + 3600))
check("unsigned + future expiry is valid (not secure)", vf.isValid && !vf.isSecure)

print("\nL4 — script ↔ address codec")
// The fixture's real P2PKH output: 25-byte script, testnet. Independent oracle = the
// address the bip70-dash server / DashSync produce for it.
let fixtureScript = d.outputs.first!.script
let fixtureAddress = ScriptAddressCodec.address(forScript: fixtureScript, network: .testnet)
check("fixture P2PKH script → known testnet address", fixtureAddress == "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr")
check("testnet P2PKH address starts with 'y'", fixtureAddress?.first == "y")
if let fixtureAddress {
    check("ROUND-TRIP: address → scriptPubKey == original script",
          ScriptAddressCodec.scriptPubKey(forAddress: fixtureAddress, network: .testnet) == fixtureScript)
}

// Mainnet P2PKH round-trip with a synthetic hash160 (1..20).
let h20 = Data((1...20).map { UInt8($0) })
let mainP2PKH = Data([0x76, 0xa9, 0x14]) + h20 + Data([0x88, 0xac])
let mainAddr = ScriptAddressCodec.address(forScript: mainP2PKH, network: .mainnet)
check("mainnet P2PKH address starts with 'X'", mainAddr?.first == "X")
if let mainAddr {
    check("mainnet P2PKH round-trip", ScriptAddressCodec.scriptPubKey(forAddress: mainAddr, network: .mainnet) == mainP2PKH)
}

// P2SH round-trip (testnet + mainnet).
let p2sh = Data([0xa9, 0x14]) + h20 + Data([0x87])
let p2shTestAddr = ScriptAddressCodec.address(forScript: p2sh, network: .testnet)
let p2shMainAddr = ScriptAddressCodec.address(forScript: p2sh, network: .mainnet)
check("P2SH testnet round-trip", p2shTestAddr.flatMap { ScriptAddressCodec.scriptPubKey(forAddress: $0, network: .testnet) } == p2sh)
check("P2SH mainnet round-trip", p2shMainAddr.flatMap { ScriptAddressCodec.scriptPubKey(forAddress: $0, network: .mainnet) } == p2sh)
check("mainnet P2SH address starts with '7'", p2shMainAddr?.first == "7")

// Non-standard scripts → nil.
let opReturn = Data([0x6a, 0x04, 0xde, 0xad, 0xbe, 0xef])
let p2pk = Data([0x21]) + Data(repeating: 0x02, count: 33) + Data([0xac])
let truncated = Data([0x76, 0xa9, 0x14] + Array(repeating: UInt8(0), count: 19) + [0x88, 0xac]) // 24 bytes
check("OP_RETURN → nil", ScriptAddressCodec.address(forScript: opReturn, network: .testnet) == nil)
check("bare P2PK → nil", ScriptAddressCodec.address(forScript: p2pk, network: .testnet) == nil)
check("truncated P2PKH → nil", ScriptAddressCodec.address(forScript: truncated, network: .testnet) == nil)

// Cross-network version byte is rejected on decode.
check("mainnet-decoding a testnet address → nil",
      fixtureAddress.flatMap { ScriptAddressCodec.scriptPubKey(forAddress: $0, network: .mainnet) } == nil)
// Corrupted checksum → nil.
check("corrupted address → nil", ScriptAddressCodec.scriptPubKey(forAddress: "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLX", network: .testnet) == nil)

// resolveOutputs.
let twoGood = [PaymentOutput(amount: 100000, script: fixtureScript), PaymentOutput(amount: 200000, script: mainP2PKH)]
if let resolved = try? ScriptAddressCodec.resolveOutputs(twoGood, network: .testnet) {
    check("resolveOutputs maps & preserves order", resolved.count == 2 && resolved[0].amount == 100000 && resolved[1].amount == 200000)
} else {
    check("resolveOutputs maps & preserves order", false)
}
func resolveThrows(_ outputs: [PaymentOutput], _ expected: BIP70Error) -> Bool {
    do { _ = try ScriptAddressCodec.resolveOutputs(outputs, network: .testnet); return false }
    catch let error as BIP70Error { return error == expected }
    catch { return false }
}
check("one bad output → .nonStandardScript",
      resolveThrows([PaymentOutput(amount: 1, script: fixtureScript), PaymentOutput(amount: 2, script: opReturn)], .nonStandardScript))
check("nil amount → .malformedRequest",
      resolveThrows([PaymentOutput(amount: nil, script: fixtureScript)], .malformedRequest))

// ---- L5 fakes + async helpers ----

final class FakeTransport: PaymentProtocolTransporting {
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
final class FakeWallet: WalletSending {
    var prepared = PreparedSend(txData: Data([0xde, 0xad, 0xbe, 0xef]), fee: 226,
                                txHashDisplay: Data((0..<32).map { UInt8($0) }))
    var calls: [String] = []
    var lastRecipients: [(address: String, amountDuffs: UInt64)] = []
    var buildErrorsRemaining = 0 // throw from build this many times before succeeding (pre-spend failure)
    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend {
        calls.append("build")
        if buildErrorsRemaining > 0 { buildErrorsRemaining -= 1; throw BIP70Error.walletNotReady }
        lastRecipients = recipients; return prepared
    }
    func broadcast(_ p: PreparedSend) async throws -> String {
        calls.append("broadcast"); return p.txHashDisplay.map { String(format: "%02x", $0) }.joined()
    }
}
final class FakeReceive: ReceiveAddressProviding {
    var address: String? = "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr"
    func receiveAddress() -> String? { address }
}
final class FakeAuth: SendAuthorizing {
    var error: Error?
    private(set) var authorized = false
    func authorize() async throws { if let e = error { throw e }; authorized = true }
}

func runSync<T>(_ body: @escaping () async throws -> T) -> Result<T, Error> {
    let sem = DispatchSemaphore(value: 0)
    var out: Result<T, Error>!
    Task { do { out = .success(try await body()) } catch { out = .failure(error) }; sem.signal() }
    sem.wait()
    return out
}
func threwBIP70<T>(_ r: Result<T, Error>, _ expected: BIP70Error) -> Bool {
    if case .failure(let e) = r, let b = e as? BIP70Error { return b == expected }
    return false
}
func value<T>(_ r: Result<T, Error>) -> T? { if case .success(let v) = r { return v } ; return nil }

let futureExpiry = UInt64(Date().timeIntervalSince1970) + 3600
func unsignedRequest(network: String? = "test", outputs: [PaymentOutput]? = nil,
                     paymentURL: String? = "http://h/pay", expires: UInt64 = futureExpiry,
                     merchantData: Data? = Data([0x01, 0x02, 0x03])) -> PaymentRequest {
    let outs = outputs ?? [PaymentOutput(amount: 100000, script: fixtureScript)]
    let details = PaymentDetails(network: network, outputs: outs, expires: expires,
                                 memo: "Test memo", paymentURL: paymentURL, merchantData: merchantData)
    return PaymentRequest(pkiType: "none", serializedDetails: details.encoded())
}
func makeService(_ transport: FakeTransport, _ wallet: FakeWallet,
                 receive: FakeReceive = FakeReceive(), auth: FakeAuth = FakeAuth(),
                 allowUntrusted: Bool = true) -> BIP70PaymentService {
    BIP70PaymentService(transport: transport, verifier: PaymentRequestVerifier(), wallet: wallet,
                        receiveAddress: receive, auth: auth, allowUntrustedUnsigned: allowUntrusted)
}
let anyURL = URL(string: "http://h/pr")!

print("\nL5 — orchestrator (fakes)")

// Spend-safety: prepare alone must not build/broadcast.
do {
    let w = FakeWallet(); let svc = makeService(FakeTransport(unsignedRequest()), w)
    _ = runSync { try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet) }
    check("prepare builds/spends nothing (calls empty)", w.calls.isEmpty)
}

// Call order build → broadcast → post.
do {
    let w = FakeWallet(); let t = FakeTransport(unsignedRequest()); t.onPost = { w.calls.append("post") }
    let svc = makeService(t, w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        return try await svc.confirmAndSend(c)
    }
    check("confirmAndSend order == [build, broadcast, post]", w.calls == ["build", "broadcast", "post"])
    check("POST carries the prepared signed bytes", t.postedPayment?.transactions == [w.prepared.txData])
    check("ack memo surfaced", value(r)?.ackMemo == "thanks")
}

// Idempotency: a second confirmAndSend on the SAME Confirmation is rejected (no second spend).
do {
    let w = FakeWallet(); let t = FakeTransport(unsignedRequest()); t.onPost = { w.calls.append("post") }
    let svc = makeService(t, w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        _ = try await svc.confirmAndSend(c)       // first send succeeds
        return try await svc.confirmAndSend(c)    // second must be rejected
    }
    check("second confirmAndSend on same Confirmation → .alreadySent", threwBIP70(r, .alreadySent))
    check("no second build/broadcast after .alreadySent", w.calls.filter { $0 == "build" }.count == 1 && w.calls.filter { $0 == "broadcast" }.count == 1)
}

// Retry: a pre-spend (build) failure releases the single-use claim so the SAME Confirmation retries.
do {
    let w = FakeWallet(); w.buildErrorsRemaining = 1
    let t = FakeTransport(unsignedRequest()); t.onPost = { w.calls.append("post") }
    let svc = makeService(t, w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        _ = try? await svc.confirmAndSend(c)      // first build throws → guard reset, nothing spent
        return try await svc.confirmAndSend(c)    // retry on same Confirmation now succeeds
    }
    check("retry after pre-spend build failure succeeds (guard reset)", value(r) != nil)
    check("two build attempts, exactly one broadcast", w.calls.filter { $0 == "build" }.count == 2 && w.calls.filter { $0 == "broadcast" }.count == 1)
}

// Multi-output passthrough + order.
do {
    let w = FakeWallet()
    let outs = [PaymentOutput(amount: 100000, script: fixtureScript), PaymentOutput(amount: 200000, script: p2sh)]
    let svc = makeService(FakeTransport(unsignedRequest(outputs: outs)), w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        _ = try await svc.confirmAndSend(c); return c
    }
    let c = value(r)
    check("multi-output: 2 recipients, order preserved, amount 300000",
          c?.recipients.count == 2 && c?.recipients.first?.amount == 100000 && c?.amount == 300000)
    check("wallet got both recipients [100000, 200000]", w.lastRecipients.map { $0.amountDuffs } == [100000, 200000])
}

// Network mismatch (test request, mainnet active) → throws, no build.
do {
    let w = FakeWallet(); let svc = makeService(FakeTransport(unsignedRequest(network: "test")), w)
    let r = runSync { try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .mainnet) }
    check("network mismatch → .networkMismatch(test); no build",
          threwBIP70(r, .networkMismatch(requested: "test")) && w.calls.isEmpty)
}

// nil network → no check (uses active network).
do {
    let svc = makeService(FakeTransport(unsignedRequest(network: nil)), FakeWallet())
    let r = runSync { try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet) }
    check("nil network accepted (no mismatch)", value(r)?.recipients.first?.address == "ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr")
}

// Expiry (unsigned, past) → .expired.
do {
    let svc = makeService(FakeTransport(unsignedRequest(expires: 1)), FakeWallet())
    let r = runSync { try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet) }
    check("past expiry → .expired", threwBIP70(r, .expired))
}

// Send-time expiry re-check → .expired, no broadcast.
do {
    let w = FakeWallet()
    let expires = UInt64(Date().timeIntervalSince1970) + 30
    let svc = makeService(FakeTransport(unsignedRequest(expires: expires)), w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        return try await svc.confirmAndSend(c, now: Date(timeIntervalSince1970: Double(expires) + 100))
    }
    check("send-time expiry → .expired; nothing broadcast", threwBIP70(r, .expired) && !w.calls.contains("broadcast"))
}

// Auth cancel → .authCancelled; nothing built.
do {
    let w = FakeWallet(); let auth = FakeAuth(); auth.error = BIP70Error.authCancelled
    let svc = makeService(FakeTransport(unsignedRequest()), w, auth: auth)
    let r = runSync { try await svc.confirmAndSendHeadless(from: anyURL, scheme: "dash", network: .testnet) }
    check("auth cancel → .authCancelled; no build", threwBIP70(r, .authCancelled) && w.calls.isEmpty)
}

// Soft POST failure after broadcast → no throw, ackMemo nil, money moved.
do {
    let w = FakeWallet(); let t = FakeTransport(unsignedRequest()); t.postShouldThrow = .unexpectedResponse(host: "h")
    let svc = makeService(t, w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        return try await svc.confirmAndSend(c)
    }
    check("soft POST fail: succeeds, ackMemo nil, broadcast happened",
          value(r) != nil && value(r)?.ackMemo == nil && w.calls.contains("broadcast"))
}

// Unsigned + no paymentURL → no missingPaymentURL gate (not secure); no POST.
do {
    let w = FakeWallet()
    let svc = makeService(FakeTransport(unsignedRequest(paymentURL: nil)), w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        return try await svc.confirmAndSend(c)
    }
    check("unsigned, no paymentURL: sends, no POST", value(r) != nil && w.calls == ["build", "broadcast"])
}

// refund_to from own receive address → single P2PKH for the full amount.
do {
    let w = FakeWallet(); let t = FakeTransport(unsignedRequest()); let receive = FakeReceive()
    let svc = makeService(t, w, receive: receive)
    _ = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        return try await svc.confirmAndSend(c)
    }
    let refund = t.postedPayment?.refundTo
    let expectedScript = ScriptAddressCodec.scriptPubKey(forAddress: receive.address!, network: .testnet)
    check("refund_to: 1 P2PKH of own address for full amount",
          refund?.count == 1 && refund?.first?.script == expectedScript && refund?.first?.amount == 100000)
    check("Payment merchantData passthrough + memo nil",
          t.postedPayment?.merchantData == Data([0x01, 0x02, 0x03]) && t.postedPayment?.memo == nil)
}

// nil receive address → empty refund_to; still succeeds.
do {
    let t = FakeTransport(unsignedRequest()); let receive = FakeReceive(); receive.address = nil
    let svc = makeService(t, FakeWallet(), receive: receive)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet)
        return try await svc.confirmAndSend(c)
    }
    check("nil receive → empty refund_to; send ok", value(r) != nil && (t.postedPayment?.refundTo.isEmpty ?? false))
}

// Untrusted-cert flag: unsigned blocked when disallowed, allowed when permitted.
do {
    let blocked = makeService(FakeTransport(unsignedRequest()), FakeWallet(), allowUntrusted: false)
    let rb = runSync { try await blocked.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet) }
    let allowed = makeService(FakeTransport(unsignedRequest()), FakeWallet(), allowUntrusted: true)
    let ra = runSync { try await allowed.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet) }
    check("allowUntrustedUnsigned=false blocks unsigned", threwBIP70(rb, .untrustedCertificate(detail: "Unsigned request")))
    check("allowUntrustedUnsigned=true permits unsigned", value(ra) != nil)
}

// Callback URL format.
do {
    let w = FakeWallet()
    let svc = makeService(FakeTransport(unsignedRequest()), w)
    let r = runSync {
        let c = try await svc.prepareForConfirmation(from: anyURL, scheme: "dash", network: .testnet, callbackScheme: "ctx")
        return try await svc.confirmAndSend(c)
    }
    let hex = w.prepared.txHashDisplay.map { String(format: "%02x", $0) }.joined()
    check("callback URL format",
          value(r)?.callbackURL?.absoluteString == "ctx://callback=payack&address=ybt3gVM6cM9WprG7bRTMst1YR2GnAbWGLr&txid=\(hex)")
}

print("\nL5 — BIP70URI")
do {
    let uri = BIP70URI("pay:Xabc?amount=0.001&r=http%3A%2F%2Fh%2Fpr&sender=ctx")
    check("pay:→dash, r/sender/amount parsed",
          uri?.scheme == "dash" && uri?.isBIP70 == true && uri?.r?.absoluteString == "http://h/pr"
              && uri?.callbackScheme == "ctx" && uri?.amount == 100000 && uri?.address == "Xabc")
}
check("address-less dash:?r= is BIP70 with nil address", {
    let u = BIP70URI("dash:?r=http%3A%2F%2Fh%2Fpr"); return u?.isBIP70 == true && u?.address == nil
}())
check("plain dash: address (no r) is not BIP70; amount→duffs", {
    let u = BIP70URI("dash:Xabc?amount=1.5"); return u?.isBIP70 == false && u?.amount == 150000000
}())
check("non-payment scheme → nil", BIP70URI("http://foo") == nil)

print("\n==== \(passed) passed, \(failed) failed ====")
exit(failed == 0 ? 0 : 1)

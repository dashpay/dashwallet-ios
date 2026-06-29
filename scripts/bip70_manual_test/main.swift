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

print("\n==== \(passed) passed, \(failed) failed ====")
exit(failed == 0 ? 0 : 1)

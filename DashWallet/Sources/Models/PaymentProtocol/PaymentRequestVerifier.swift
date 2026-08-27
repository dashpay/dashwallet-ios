//
//  PaymentRequestVerifier.swift
//  DashWallet
//
//  BIP70 payment-protocol — X.509 / PKI verification (Layer 2).
//
//  Validates a `PaymentRequest`'s merchant signature and certificate chain, reproducing
//  DashSync's `-[DSPaymentProtocolRequest isValid]` (DSPaymentProtocol.m:453-532) with two
//  modernisations: `SecKeyVerifySignature` instead of the deprecated `SecKeyRawVerify`, and
//  `SecTrustCopyKey` instead of `SecTrustCopyPublicKey`.
//
//  Trust is evaluated against the system trust store (basic X.509 policy, no hostname /
//  revocation checks — BIP70 signs the request payload, not the transport). The signature is
//  verified over the request re-encoded with an empty-but-present signature field, which is
//  byte-exact with what the merchant signed (proven against the test server in BIP70_TESTING.md).
//
//  Layer rule: Foundation + Security only. No networking, no chain/network knowledge (the
//  network-name check lives in the service), no UIKit, no SDK types.
//

import Foundation
import Security

extension PaymentRequestVerifier {
    /// Outcome of verifying a `PaymentRequest`.
    struct Verdict {
        /// True only when the certificate chain is trusted AND the signature verifies AND the
        /// request has not expired. For `pki_type == "none"` (unsigned), true unless expired.
        let isValid: Bool
        /// Merchant display name: cert subject summary for signed requests; for unsigned
        /// requests, the Dash extension reads `pki_data` as a UTF-8 name.
        let commonName: String?
        let pkiType: String
        /// Human-readable reason when `isValid == false`.
        let errorMessage: String?

        /// Whether the request carries a real PKI signature (vs unsigned `pki_type == "none"`).
        var isSecure: Bool { isValid && pkiType != "none" }
    }
}

struct PaymentRequestVerifier {

    func verify(_ request: PaymentRequest, now: Date = Date()) -> Verdict {
        let pkiType = request.pkiType
        var commonName: String?
        var errorMessage: String?
        var isValid = true

        if pkiType != "none" {
            let certDataList = request.pkiData.map { X509Certificates($0).certificates } ?? []
            let certs = certDataList.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }

            if let leaf = certs.first {
                commonName = SecCertificateCopySubjectSummary(leaf) as String?
            }

            // Build + evaluate the chain against the system trust store (basic X.509).
            var trust: SecTrust?
            let policy = SecPolicyCreateBasicX509()
            let createStatus = SecTrustCreateWithCertificates(certs as CFArray, policy, &trust)

            var trustError: CFError?
            let trusted = (createStatus == errSecSuccess && trust != nil)
                ? SecTrustEvaluateWithError(trust!, &trustError)
                : false

            if !trusted {
                var message = certs.isEmpty ? "Missing certificate" : "Untrusted certificate"
                if let detail = (trustError as Error?)?.localizedDescription {
                    message += " - \(detail)"
                }
                errorMessage = message
                isValid = false
            }

            // Verify the signature with the leaf public key (works even if trust failed, matching
            // the reference). A signature failure overrides the trust error message.
            switch verifySignature(request: request, pkiType: pkiType, trust: trust) {
            case .valid:
                break
            case .invalid:
                errorMessage = "Invalid signature"
                isValid = false
            case .unsupported:
                errorMessage = "Unsupported signature type"
                isValid = false
            }
        } else {
            // pki_type == "none": no verification. Dash extension — if pki_data carries a cert
            // entry, treat its bytes as a UTF-8 merchant name.
            if let pkiData = request.pkiData, !pkiData.isEmpty,
               let nameBytes = X509Certificates(pkiData).certificates.first {
                commonName = String(data: nameBytes, encoding: .utf8)
            }
        }

        // Expiry (applies to signed and unsigned alike).
        if isValid {
            let expires = request.details.expires
            if expires >= 1, now.timeIntervalSince1970 > Double(expires) {
                errorMessage = "Request expired"
                isValid = false
            }
        }

        return Verdict(isValid: isValid, commonName: commonName, pkiType: pkiType, errorMessage: errorMessage)
    }

    // MARK: - Signature

    private enum SignatureResult { case valid, invalid, unsupported }

    private func verifySignature(request: PaymentRequest, pkiType: String, trust: SecTrust?) -> SignatureResult {
        let algorithm: SecKeyAlgorithm
        switch pkiType {
        case "x509+sha256": algorithm = .rsaSignatureMessagePKCS1v15SHA256
        case "x509+sha1": algorithm = .rsaSignatureMessagePKCS1v15SHA1
        default: return .unsupported
        }
        guard let trust, let publicKey = SecTrustCopyKey(trust) else { return .unsupported }
        guard let signature = request.signature, !signature.isEmpty else { return .invalid }
        guard SecKeyIsAlgorithmSupported(publicKey, .verify, algorithm) else { return .unsupported }

        // Signed bytes = request re-encoded with the signature field present but zero-length.
        let signedBytes = request.encoded(signature: Data())
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(publicKey, algorithm, signedBytes as CFData, signature as CFData, &error)
        return ok ? .valid : .invalid
    }
}

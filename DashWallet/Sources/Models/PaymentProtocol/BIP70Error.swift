//
//  BIP70Error.swift
//  DashWallet
//
//  Shared error taxonomy for the app-side BIP70 protocol stack. Kept as a dependency-free
//  leaf (Foundation only) so every layer (L3 transport, L4 script codec, L5 service) can
//  throw it without inverting the inward dependency direction. The L6 adapter maps these to
//  user-facing localized titles/messages.
//

import Foundation

/// Why a signed payment request failed X.509 verification. It carries no text, so
/// `BIP70Error` equality does not depend on the language; `BIP70Error.errorDescription`
/// turns it into the localized sentence.
enum BIP70CertificateFailure: Equatable {
    /// The request names an X.509 PKI type but carries no certificate.
    case missingCertificate
    /// The certificate chain is not trusted by the system trust store.
    case untrustedChain
    /// The merchant signature does not verify with the leaf certificate's key.
    case invalidSignature
    /// The PKI type or the leaf key's algorithm is not one the verifier supports.
    case unsupportedSignatureType
}

enum BIP70Error: Error, Equatable {
    /// The payment-request / payment URL was missing or unparseable.
    case badURL
    /// https was required and a URL on the way was not https: the request URL, a BIP73
    /// uri-list target, the `payment_url`, or an HTTP redirect from any of them.
    case insecureTransport
    /// HTTP failure: non-2xx status, missing/non-HTTP response, or wrong content type.
    case unexpectedResponse(host: String?)
    /// Response body exceeded the 50 KB BIP70 cap.
    case payloadTooLarge
    /// The fetched bytes were not a decodable `PaymentRequest`.
    case malformedRequest
    /// The merchant's response was not a decodable `PaymentACK`.
    case malformedACK
    /// `PaymentDetails.network` did not match the wallet's active network (checked in L5).
    case networkMismatch(requested: String)
    /// The request's `expires` time has passed.
    case expired
    /// X.509 chain/signature verification failed for a signed request.
    case untrustedCertificate(BIP70CertificateFailure)
    /// An unsigned request while the policy allows only signed ones.
    case unsignedRequest
    /// An output used a scriptPubKey we can't send to (not P2PKH/P2SH).
    case nonStandardScript
    /// A signed merchant request without a `payment_url` to POST the Payment back to.
    case missingPaymentURL
    /// The merchant rejected / did not acknowledge the Payment.
    case ackRejected
    /// The SwiftDashSDK wallet isn't bound yet (no funded wallet to build from).
    case walletNotReady
    /// The user cancelled the PIN/biometric prompt.
    case authCancelled
    /// A second send was attempted on a `Confirmation` that has already been (or is being) sent.
    case alreadySent
    /// The Payment was posted but no acknowledgement came back. The merchant may or may not
    /// have received the signed bytes — BIP70 cannot tell those apart — so this carries the
    /// app-computed display-order tx hash: if the merchant did receive them it can broadcast
    /// independently, and the caller needs a handle on the spend it may have just made.
    case paymentNotAcknowledged(txHashDisplay: Data, reason: String)
    /// The transaction was submitted but the network returned no positive acceptance verdict
    /// within the SDK's wait window. The bytes may already be propagating — and the merchant
    /// holds a copy it can broadcast itself — so this is deliberately distinct from a
    /// rejection: it carries the app-computed display-order tx hash so callers can record the
    /// spend instead of discarding it. Never retry the same send on this error.
    case broadcastOutcomeUnknown(txHashDisplay: Data, reason: String)
    /// The merchant acknowledged the Payment, then the broadcast threw something other than a `BIP70Error`, or the
    /// request had expired by the time the acknowledgement came back, so the wallet did not broadcast.
    /// The merchant holds the signed bytes and can broadcast them itself, so the spend is committed
    /// whatever the error says. Carries the app-computed display-order tx hash and the underlying
    /// error's description. Never retry the same send on this error.
    case failedAfterAcknowledgement(txHashDisplay: Data, reason: String)
}

extension BIP70Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badURL:
            return String(localized: "Invalid payment request URL.", comment: "BIP70 payment error")
        case .insecureTransport:
            return String(localized: "This payment request does not use a secure connection.", comment: "Payment request refused")
        case let .unexpectedResponse(host):
            guard let host else {
                return String(localized: "Unexpected response from the payment server.", comment: "BIP70 payment error")
            }
            return String(localized: "Unexpected response from \(host).", comment: "BIP70 payment error: the payment server's host name")
        case .payloadTooLarge:
            return String(localized: "The payment request is too large.", comment: "BIP70 payment error")
        case .malformedRequest:
            return String(localized: "The payment request could not be read.", comment: "BIP70 payment error")
        case .malformedACK:
            return String(localized: "The payment acknowledgement could not be read.", comment: "BIP70 payment error")
        case let .networkMismatch(requested):
            return String(localized: "Requested network \"\(requested)\" is not currently in use.", comment: "BIP70 payment error: the network name the request asks for")
        case .expired:
            return String(localized: "This payment request has expired.", comment: "BIP70 payment error")
        case let .untrustedCertificate(failure):
            let reason: String
            switch failure {
            case .untrustedChain:
                return String(localized: "Untrusted certificate.", comment: "BIP70 payment error")
            case .missingCertificate:
                reason = String(localized: "Missing certificate", comment: "BIP70 payment error: why the certificate is not trusted")
            case .invalidSignature:
                reason = String(localized: "Invalid signature", comment: "BIP70 payment error: why the certificate is not trusted")
            case .unsupportedSignatureType:
                reason = String(localized: "Unsupported signature type",
                                           comment: "BIP70 payment error: why the certificate is not trusted")
            }
            return Self.untrustedCertificateText(reason)
        case .unsignedRequest:
            return Self.untrustedCertificateText(
                String(localized: "Unsigned request", comment: "BIP70 payment error: why the certificate is not trusted"))
        case .nonStandardScript:
            return String(localized: "This payment request uses an unsupported output type.", comment: "BIP70 payment error")
        case .missingPaymentURL:
            return String(localized: "The payment request is missing a payment URL.", comment: "BIP70 payment error")
        case .ackRejected:
            return String(localized: "The merchant did not acknowledge the payment.", comment: "BIP70 payment error")
        case .walletNotReady:
            return String(localized: "The wallet isn't ready yet. Please try again in a moment.", comment: "BIP70 payment error")
        case .authCancelled:
            return String(localized: "Authentication was cancelled.", comment: "BIP70 payment error")
        case .alreadySent:
            return String(localized: "This payment is already being processed.", comment: "BIP70 payment error")
        case .paymentNotAcknowledged:
            return String(localized: "The merchant did not confirm receiving the payment.", comment: "BIP70 payment error")
        case .broadcastOutcomeUnknown:
            return String(localized: "Your payment was sent, but the network has not confirmed it yet.",
                                     comment: "BIP70 payment error")
        case .failedAfterAcknowledgement:
            return Self.acknowledgedPaymentMessage
        }
    }

    /// What a payment the merchant acknowledged shows when its broadcast failed or its request expired after the POST.
    static var acknowledgedPaymentMessage: String {
        String(localized: "The merchant received your payment, so it may still complete. Check your transactions before you pay again.",
                          comment: "BIP70 payment error: the merchant acknowledged the payment, the wallet did not finish it")
    }

    /// "Untrusted certificate - <reason>." from the text lists.
    private static func untrustedCertificateText(_ reason: String) -> String {
        String(localized: "Untrusted certificate - \(reason).", comment: "BIP70 payment error: why the certificate is not trusted")
    }
}

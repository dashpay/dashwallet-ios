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

enum BIP70Error: Error, Equatable {
    /// The payment-request / payment URL was missing or unparseable.
    case badURL
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
    case untrustedCertificate(detail: String?)
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
}

extension BIP70Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid payment request URL."
        case let .unexpectedResponse(host): return "Unexpected response from \(host ?? "the payment server")."
        case .payloadTooLarge: return "The payment request is too large."
        case .malformedRequest: return "The payment request could not be read."
        case .malformedACK: return "The payment acknowledgement could not be read."
        case let .networkMismatch(requested): return "Requested network \"\(requested)\" is not currently in use."
        case .expired: return "This payment request has expired."
        case let .untrustedCertificate(detail): return "Untrusted certificate\(detail.map { " - \($0)" } ?? "")."
        case .nonStandardScript: return "This payment request uses an unsupported output type."
        case .missingPaymentURL: return "The payment request is missing a payment URL."
        case .ackRejected: return "The merchant did not acknowledge the payment."
        case .walletNotReady: return "The wallet isn't ready yet. Please try again in a moment."
        case .authCancelled: return "Authentication was cancelled."
        }
    }
}

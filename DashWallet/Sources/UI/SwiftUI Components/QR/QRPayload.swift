//
//  QRPayload.swift
//  DashWallet
//
//  One classification for every QR payload family the app understands,
//  so each scanner recognizes content that belongs to another flow
//  instead of dead-ending on it.
//

import Foundation

/// The parse-level meaning of a scanned QR string.
enum QRPayload {
    /// A Dash payment intent: `dash:`/`pay:` URI, bare address, or a
    /// BIP70/73 request URL (`rURL` set). Carries the app-side parse.
    case payment(ParsedPaymentURI)
    #if DASHPAY
    /// `dashpay://user?id=…&username=…` — another user's contact QR.
    case dashPayUser(DashPayUserLink)
    /// Any accepted invitation transport (`dashpay://invite`, applink,
    /// OneLink). Carries the original URL; the claim flow re-normalizes.
    case invitation(URL)
    #endif
    /// Anything else — plain text, foreign-chain addresses, unknown URIs.
    case text(String)

    /// Classification runs strict-to-loose: the DashPay recognizers are
    /// exact-shape parsers that reject everything else, so they go first;
    /// the payment parser accepts loosely (bare addresses, request URLs);
    /// whatever remains is plain text. `dashwallet://` deeplink actions
    /// (scanqr, x-callback request) are deliberately NOT recognized here —
    /// as camera input they are nonsensical or hostile, and `pay`-style
    /// deeplinks already normalize through the payment parser.
    static func classify(_ scanned: String) -> QRPayload {
        let trimmed = scanned.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DASHPAY
        if let link = DashPayUserLink.parse(trimmed) {
            return .dashPayUser(link)
        }
        if DWInvitationLinkNormalizer.normalize(trimmed) != nil, let url = URL(string: trimmed) {
            return .invitation(url)
        }
        #endif

        let parsed = ParsedPaymentURI.parse(paymentString: trimmed)
        if parsed.isValidDashPaymentIntent || parsed.rURL != nil {
            return .payment(parsed)
        }
        return .text(trimmed)
    }
}

/// A finished scan: what the scanner hands back after validation (and,
/// for BIP70/73 payment requests, after the fetch/verify round-trip).
enum QRScanResult {
    case payment(DWPaymentInput)
    #if DASHPAY
    case dashPayUser(DashPayUserLink)
    case invitation(URL)
    #endif
    /// Raw captured string — only produced by `.addressInput` scanners.
    case text(String)
}

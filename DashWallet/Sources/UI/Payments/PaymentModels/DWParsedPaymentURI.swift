//
//  DWParsedPaymentURI.swift
//  DashWallet
//
//  Immutable @objc record of one parsed payment string plus validity verdicts computed against
//  the app's current network (`WalletEnvironment`). The interactive ObjC payment flow (QR scan,
//  pasteboard/NFC, deeplink) reads THIS for every routing/validity decision; its send-side
//  projection is `DWPaymentIntent` — see `DWPaymentInput.attachParsedURI:`.
//
//  Parsing/validation live here and in the pure `BIP70URI` value type; this class only bridges to
//  ObjC and pins the address verdict to the current network so the ObjC sites stop threading a
//  `DSChain` for it.
//

import Foundation
import SwiftDashSDK

// MARK: - DashAddressClassifier

/// Decode a destination string into what it actually is on the wire. Lives
/// here (nonisolated) rather than on `SendViewModel` because the QR scan
/// pipeline classifies on its capture queue; `SendViewModel.classify`
/// forwards to this.
enum DashAddressClassifier {
    enum Kind: Equatable {
        case core
        case platform
        /// Carries the recipient's raw 43-byte Orchard payload so confirm
        /// flows don't re-decode the bech32m.
        case shielded(raw43: Data)
    }

    /// - Base58Check L1 address (network-checked) → `.core`
    /// - bech32m HRP `dash`/`tdash` (current network), 21-byte payload with a
    ///   DIP-0018 wire type byte (0xb0 P2PKH / 0x80 P2SH) → `.platform`
    /// - bech32m, 44-byte payload `0x10` + 43 raw Orchard bytes → `.shielded`
    /// Anything else (wrong-network HRP included) → nil.
    static func classify(_ text: String) -> Kind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.isValidDashAddressForCurrentNetwork {
            return .core
        }

        guard let decoded = Bech32m.decode(trimmed.lowercased()) else { return nil }
        // Mainnet HRP only on mainnet — devnet parses with the testnet HRP.
        let expectedHrp = Bech32m.platformHrp(mainnet: WalletEnvironment.isMainnet)
        guard decoded.hrp == expectedHrp else { return nil }

        if decoded.data.count == 21,
           decoded.data[0] == 0xb0 || decoded.data[0] == 0x80 {
            return .platform
        }
        // DIP-0018 shielded display form: 0x10 type byte + 43 raw Orchard
        // bytes (the encoding `PaymentsLandingViewModel.reloadShieldedAddress`
        // produces for our own address).
        if decoded.data.count == 44, decoded.data[0] == 0x10 {
            return .shielded(raw43: decoded.data.subdata(in: 1..<44))
        }
        return nil
    }
}

@objc(DWParsedPaymentURI)
final class ParsedPaymentURI: NSObject {
    /// The trimmed input, verbatim.
    @objc let rawString: String
    /// "dash"/"bitcoin" for an explicit URI, "http"/"https" for a BIP73 URL, nil when unparseable.
    @objc let scheme: String?
    /// Percent-decoded address (or a bare key string) — UNVALIDATED; consult
    /// `isAddressValidForCurrentNetwork`. nil for `dash:?r=…` and unparseable inputs.
    @objc let address: String?
    /// Amount in duffs; 0 when absent or invalid.
    @objc let amount: UInt64
    /// An amount was given but is not payable (empty, unreadable, negative, above the supply). The
    /// address alone is then not a payment: paying it would drop the amount the payer asked for.
    @objc let hasInvalidAmount: Bool
    @objc let label: String?
    @objc let message: String?
    /// The BIP72 `r=` URL, or the whole BIP73 URL. nil when absent/unparseable — call sites fetch
    /// only when this is non-nil (the coordinator takes a non-optional `URL`).
    @objc let rURL: URL?
    /// The request was given as `req-r`, or more than once: only the merchant's request may be
    /// paid, never the embedded address in its place. Without a usable `rURL` nothing is payable.
    @objc let requiresRequest: Bool
    /// The amount was given as `req-amount`: an invoice, never an address to fill in alone.
    @objc let requiresAmount: Bool
    /// A `req-` parameter the wallet doesn't understand: per BIP21 nothing in the URI is payable.
    @objc let hasUnsupportedRequirement: Bool
    /// `sender=` x-callback-url scheme.
    @objc let callbackScheme: String?
    /// `user=` DashPay username (value carry only; DashPay deferred to C10).
    @objc let dashpayUsername: String?
    /// `currency=` requested fiat code.
    @objc let fiatCurrencyCode: String?
    /// `local=` requested fiat amount; 0 when absent.
    @objc let fiatAmount: Float
    /// false for bare schemeless inputs (implicit dash) — drives the invalid-QR error copy.
    @objc let hasExplicitScheme: Bool
    /// `String.isValidDashAddressForCurrentNetwork`, computed at parse time.
    /// Core (base58) only — the BIP70-fallback path still keys on this.
    @objc let isAddressValidForCurrentNetwork: Bool
    /// True when `address` is payable in ANY form this wallet supports on
    /// the current network: base58 Core, DIP-0018 bech32m Platform, or
    /// shielded. The QR scanner's accept gate.
    @objc let isAddressPayableForCurrentNetwork: Bool
    /// True when the address is a bech32m Platform/Shielded destination that
    /// may be paid on its own — those can't ride the classic L1 payment
    /// processor, so scan entry points route them into the Send screen
    /// instead. A link that refuses its address alone stays with the
    /// processor, which says why.
    @objc let requiresSendScreenRouting: Bool

    /// A link whose address may not fill a form by itself: a requirement the
    /// wallet cannot meet, an unpayable amount, or a merchant request it must
    /// fetch.
    @objc var refusesAddressAlone: Bool {
        hasUnsupportedRequirement || hasInvalidAmount || requiresRequest
    }

    /// Mirrors `DSPaymentRequest.isValidAsNonDashpayPaymentRequest` (dash-only arm; the `bitcoin:`
    /// arms are compiled out under `SHAPESHIFT_ENABLED`, undefined in this app), widened to accept
    /// every payable address form (bech32m Platform/Shielded included).
    @objc var isValidDashPaymentIntent: Bool {
        scheme == "dash" && !hasUnsupportedRequirement
            && ((isAddressPayableForCurrentNetwork && !hasInvalidAmount && !requiresRequest) || rURL != nil)
    }

    /// A plain https payment-request URL read whole (BIP73), the one form without a `dash:`
    /// scheme whose request the wallet fetches. Cleartext is not: nothing would vouch for the
    /// request it returns.
    @objc var isWholeRequestURL: Bool {
        scheme == "https" && rURL.map(PaymentProtocolTransport.isSecure) == true
    }

    /// Whether copied text mentions a payment link (`dash:`, `pay:`, `dashwallet:`, `bitcoin:`). Such
    /// text is a payment, not prose: no address is picked out of it, since part of a link would
    /// pay without what the rest of it required.
    @objc(textMentionsPaymentLink:)
    static func textMentionsPaymentLink(_ text: String) -> Bool {
        text.range(of: #"(?i)(?:dashwallet:|dash:|bitcoin:|pay:\S)"#, options: .regularExpression) != nil
    }

    /// The payment link copied text is, read whole: whitespace, trailing sentence punctuation and
    /// one enclosing pair of brackets or quotes aside. nil when the text is anything more.
    @objc(soleLinkIn:)
    static func soleLink(in text: String) -> String? {
        var link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = link.unicodeScalars.last, trailingPunctuation.contains(last) { link.removeLast() }
        if let (open, close) = enclosingPairs.first(where: { link.count > 2 && link.hasPrefix($0.0) && link.hasSuffix($0.1) }) {
            link = String(link.dropFirst(open.count).dropLast(close.count))
        }
        guard link.range(of: #"^(?i)(?:dashwallet|dash|pay):\S+$"#, options: .regularExpression) != nil
        else { return nil }
        return link
    }

    private static let enclosingPairs = [("(", ")"), ("<", ">"), ("[", "]"), ("{", "}"),
                                         ("\"", "\""), ("'", "'"), ("`", "`")]
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")

    /// A merchant request the wallet fetches: one in a `dash:` URI it can pay, or a whole https
    /// URL. Another currency's `r=` is that currency's request, never fetched as Dash's.
    @objc var isFetchableDashRequest: Bool {
        rURL != nil && (isValidDashPaymentIntent || isWholeRequestURL)
    }

    private init(rawString: String,
                 scheme: String?,
                 address: String?,
                 amount: UInt64,
                 hasInvalidAmount: Bool,
                 label: String?,
                 message: String?,
                 rURL: URL?,
                 requiresRequest: Bool,
                 requiresAmount: Bool,
                 hasUnsupportedRequirement: Bool,
                 callbackScheme: String?,
                 dashpayUsername: String?,
                 fiatCurrencyCode: String?,
                 fiatAmount: Float,
                 hasExplicitScheme: Bool,
                 isAddressValidForCurrentNetwork: Bool,
                 isAddressPayableForCurrentNetwork: Bool,
                 requiresSendScreenRouting: Bool) {
        self.rawString = rawString
        self.scheme = scheme
        self.address = address
        self.amount = amount
        self.hasInvalidAmount = hasInvalidAmount
        self.label = label
        self.message = message
        self.rURL = rURL
        self.requiresRequest = requiresRequest
        self.requiresAmount = requiresAmount
        self.hasUnsupportedRequirement = hasUnsupportedRequirement
        self.callbackScheme = callbackScheme
        self.dashpayUsername = dashpayUsername
        self.fiatCurrencyCode = fiatCurrencyCode
        self.fiatAmount = fiatAmount
        self.hasExplicitScheme = hasExplicitScheme
        self.isAddressValidForCurrentNetwork = isAddressValidForCurrentNetwork
        self.isAddressPayableForCurrentNetwork = isAddressPayableForCurrentNetwork
        self.requiresSendScreenRouting = requiresSendScreenRouting
        super.init()
    }

    /// Parse any interactive payment string. **Total** — an unparseable input yields a
    /// rawString-only box with false verdicts (mirroring `DSPaymentRequest requestWithString:`,
    /// which always returns an object), so ObjC nil-messaging needs no special cases.
    @objc(parsePaymentString:)
    static func parse(paymentString raw: String) -> ParsedPaymentURI {
        parse(paymentString: raw, honorsCallback: false)
    }

    /// A link another app opened: its `sender` is called back after the payment, so a required
    /// one is met. Anything the wallet read itself (a scan, a paste, an NFC tag) calls no app back,
    /// so `req-sender` there is a requirement the wallet cannot meet.
    @objc(parseOpenedLinkString:)
    static func parse(openedLink raw: String) -> ParsedPaymentURI {
        parse(paymentString: raw, honorsCallback: true)
    }

    private static func parse(paymentString raw: String, honorsCallback: Bool) -> ParsedPaymentURI {
        let paymentString: String?
        switch deepLinkPaymentString(for: raw) {
        case .notAWrapper: paymentString = raw
        case .refused: paymentString = nil
        case .rewritten(let rewritten): paymentString = rewritten
        }
        guard let paymentString, let uri = BIP70URI(paymentString: paymentString) else {
            return ParsedPaymentURI(rawString: raw, scheme: nil, address: nil, amount: 0,
                                    hasInvalidAmount: false, label: nil, message: nil, rURL: nil, requiresRequest: false,
                                    requiresAmount: false,
                                    hasUnsupportedRequirement: false,
                                    callbackScheme: nil,
                                    dashpayUsername: nil, fiatCurrencyCode: nil, fiatAmount: 0,
                                    hasExplicitScheme: false, isAddressValidForCurrentNetwork: false,
                                    isAddressPayableForCurrentNetwork: false,
                                    requiresSendScreenRouting: false)
        }

        let addressValid = uri.address?.isValidDashAddressForCurrentNetwork ?? false
        let classified = uri.address.flatMap(DashAddressClassifier.classify)
        let isBech32Destination = !addressValid && classified != nil
        let hasUnsupportedRequirement = uri.hasUnsupportedRequirement
            || (!honorsCallback && uri.requiredFields.contains("sender"))

        return ParsedPaymentURI(rawString: raw,
                                scheme: uri.scheme,
                                address: uri.address,
                                amount: uri.amount ?? 0,
                                hasInvalidAmount: uri.hasInvalidAmount,
                                label: uri.label,
                                message: uri.message,
                                rURL: uri.r,
                                requiresRequest: uri.requiredFields.contains("r"),
                                requiresAmount: uri.requiredFields.contains("amount"),
                                hasUnsupportedRequirement: hasUnsupportedRequirement,
                                callbackScheme: uri.callbackScheme,
                                dashpayUsername: uri.dashpayUsername,
                                fiatCurrencyCode: uri.fiatCurrencyCode,
                                fiatAmount: uri.fiatAmount ?? 0,
                                hasExplicitScheme: uri.kind != .bareAddress,
                                isAddressValidForCurrentNetwork: addressValid,
                                isAddressPayableForCurrentNetwork: addressValid || classified != nil,
                                requiresSendScreenRouting: isBech32Destination && !hasUnsupportedRequirement
                                    && !uri.hasInvalidAmount && !uri.requiredFields.contains("r"))
    }

    /// The `dash:` URI that `DWURLParser`, the deep-link router, rewrites a `dashwallet://pay=…`
    /// link to. Read raw, `pay=<address>` would be taken for the address. A deep link is rewritten
    /// before it gets here, so this is a link the wallet read itself (a scan, a paste, an NFC tag):
    /// it keeps the address and the link's own parameters and loses `sender`, since no app asked
    /// for the payment. A pay link the router refused stays refused; anything else that is not a
    /// pay link (the plain `dashwallet:<address>` alias, which `BIP70URI` reads) is read as is.
    private static func deepLinkPaymentString(for raw: String) -> DeepLinkPayment {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = "dashwallet:"
        guard link.lowercased().hasPrefix(scheme) else { return .notAWrapper }
        if let url = URL(string: link), let paymentURL = DWURLParser.paymentURL(forScannedLink: url) {
            return .rewritten(paymentURL.absoluteString)
        }
        // Only the bare alias (`dashwallet:<address>`) is read as is. Any other form the router
        // did not turn into a payment, a `//` link it refused or could not even parse among them,
        // is refused here too, never reread.
        return link.dropFirst(scheme.count).hasPrefix("/") ? .refused : .notAWrapper
    }

    private enum DeepLinkPayment {
        case notAWrapper
        case refused
        case rewritten(String)
    }

    /// The fetch-failed fallback: a copy without the BIP70 request URL (was the
    /// `request.r = nil` mutation). `isValidDashPaymentIntent` then collapses to address validity.
    @objc(uriByClearingRequestURL)
    func byClearingRequestURL() -> ParsedPaymentURI {
        ParsedPaymentURI(rawString: rawString,
                         scheme: scheme,
                         address: address,
                         amount: amount,
                         hasInvalidAmount: hasInvalidAmount,
                         label: label,
                         message: message,
                         rURL: nil,
                         requiresRequest: requiresRequest,
                         requiresAmount: requiresAmount,
                         hasUnsupportedRequirement: hasUnsupportedRequirement,
                         callbackScheme: callbackScheme,
                         dashpayUsername: dashpayUsername,
                         fiatCurrencyCode: fiatCurrencyCode,
                         fiatAmount: fiatAmount,
                         hasExplicitScheme: hasExplicitScheme,
                         isAddressValidForCurrentNetwork: isAddressValidForCurrentNetwork,
                         isAddressPayableForCurrentNetwork: isAddressPayableForCurrentNetwork,
                         requiresSendScreenRouting: requiresSendScreenRouting)
    }
}

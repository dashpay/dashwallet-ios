//
//  BIP70URI.swift
//  DashWallet
//
//  BIP70 payment-protocol — `dash:`/BIP72 URI parser (Layer 5).
//
//  Replaces DashSync's `DSPaymentRequest` URI parsing: `init?(_:)` is the strict URI form the
//  BIP70 orchestrator consumes (notably the BIP72 `r=` request URL and the `?sender=` callback
//  scheme); `init?(paymentString:)` is the wider payment-string form the interactive entries
//  (QR / pasteboard / NFC / deeplink) consume — it additionally classifies bare address/key
//  candidates and plain http(s) BIP73 request URLs. It does NOT fetch and does NOT validate
//  addresses (that's the caller's job, against the current network).
//
//  Pure: Foundation only. Mirrors `DWPaymentInputBuilder.m` / `DSPaymentRequest.m`:
//  `pay:` → `dash:` normalization, `dashwallet:`/`bitcoin:` accepted, percent-decoded query.
//

import Foundation

struct BIP70URI {
    /// How the input classified. `.paymentURI` = explicit `dash:`/`bitcoin:` URI; `.bareAddress` =
    /// schemeless candidate (implicit dash — an address or key string, unvalidated here);
    /// `.bip73URL` = a plain http(s) payment-request URL scanned/pasted whole (BIP73).
    enum Kind {
        case paymentURI
        case bareAddress
        case bip73URL
    }

    let kind: Kind
    /// Normalized payment scheme token: "dash" (default) or "bitcoin"; "http"/"https" for BIP73.
    /// Drives L3 content types.
    let scheme: String
    /// Fallback / plain-send address (BIP21/BIP72 carry it before the `?`). nil for `dash:?r=…`.
    let address: String?
    /// `?amount=` parsed from decimal DASH to duffs. Authoritative amount for a BIP70 send still
    /// comes from the signed `PaymentDetails`; this is for the plain-send fallback / UI hints.
    let amount: UInt64?
    let label: String?
    let message: String?
    /// `?r=` BIP72 payment-request URL — the BIP70 trigger. For `.bip73URL` it's the input itself.
    let r: URL?
    /// `?sender=` x-callback-url scheme to open after a successful send.
    let callbackScheme: String?
    /// `?user=` DashPay username. Parse-side value carry only — DashPay flows are deferred (C10).
    let dashpayUsername: String?
    /// `?currency=` requested fiat code (our own receive screen emits it alongside `local=`).
    let fiatCurrencyCode: String?
    /// `?local=` requested fiat amount. `NSString.floatValue` semantics for `DSPaymentRequest`
    /// parity (unparseable → 0). nil when the param is absent.
    let fiatAmount: Float?
    /// Keys carrying the `req-` prefix (params the request demands; amount immutability etc.).
    let requiredFields: Set<String>

    /// true ⇒ BIP70 protocol flow (fetch `r`); false ⇒ plain BIP21 address send.
    var isBIP70: Bool { r != nil }

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }

        // Scheme normalization (pay: → dash:).
        switch trimmed[..<colon].lowercased() {
        case "pay", "dash", "dashwallet": scheme = "dash"
        case "bitcoin": scheme = "bitcoin"
        default: return nil
        }
        kind = .paymentURI

        // Strip the scheme + optional "//", then split the address from the query.
        var rest = String(trimmed[trimmed.index(after: colon)...])
        if rest.hasPrefix("//") { rest = String(rest.dropFirst(2)) }

        let addressPart: String
        let queryPart: String?
        if let q = rest.firstIndex(of: "?") {
            addressPart = String(rest[..<q])
            queryPart = String(rest[rest.index(after: q)...])
        } else {
            addressPart = rest
            queryPart = nil
        }
        address = addressPart.isEmpty ? nil : (addressPart.removingPercentEncoding ?? addressPart)

        // Parse the query string.
        var amount: UInt64?
        var label: String?
        var message: String?
        var r: URL?
        var callbackScheme: String?
        var dashpayUsername: String?
        var fiatCurrencyCode: String?
        var fiatAmount: Float?
        var requiredFields: Set<String> = []

        for pair in queryPart?.split(separator: "&") ?? [] {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = kv.first else { continue }
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""

            if key.hasPrefix("req-") { requiredFields.insert(String(key.dropFirst(4))) }

            switch key {
            case "amount", "req-amount": amount = Self.duffs(fromDecimalDash: value)
            case "label", "req-label": label = value
            case "message", "req-message": message = value
            case "r", "req-r": r = URL(string: value)
            case "sender", "req-sender": callbackScheme = value
            case "user", "req-user": dashpayUsername = value
            case "currency", "req-currency": fiatCurrencyCode = value
            case "local", "req-local": fiatAmount = (value as NSString).floatValue
            default: break
            }
        }

        self.amount = amount
        self.label = label
        self.message = message
        self.r = r
        self.callbackScheme = callbackScheme
        self.dashpayUsername = dashpayUsername
        self.fiatCurrencyCode = fiatCurrencyCode
        self.fiatAmount = fiatAmount
        self.requiredFields = requiredFields
    }

    /// Payment-string parse for the interactive entries (QR / pasteboard / NFC / deeplink).
    /// Accepts everything `init?(_:)` does, plus schemeless candidates (implicit dash — bare
    /// addresses and WIF/BIP38 key strings, still zero validation here) and plain http(s) BIP73
    /// request URLs. nil for empty strings and unknown colon schemes (`mailto:` etc.) — unlike
    /// `DSPaymentRequest`, which stuffed every unknown scheme into `r` and let a doomed fetch
    /// produce the failure.
    init?(paymentString raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let colon = trimmed.firstIndex(of: ":") else {
            self.init(bareAddressCandidate: trimmed)
            return
        }
        if let uri = BIP70URI(trimmed) {
            self = uri
            return
        }
        // BIP73: a plain http(s) payment-request URL. Interior spaces get the same %20
        // courtesy DSPaymentRequest applied to the whole string (DSPaymentRequest.m:94-96).
        let scheme = trimmed[..<colon].lowercased()
        guard scheme == "http" || scheme == "https",
              let url = URL(string: trimmed.replacingOccurrences(of: " ", with: "%20")) else { return nil }
        self.init(bip73URL: url, scheme: String(scheme))
    }

    private init(bareAddressCandidate: String) {
        kind = .bareAddress
        scheme = "dash"
        address = bareAddressCandidate
        amount = nil
        label = nil
        message = nil
        r = nil
        callbackScheme = nil
        dashpayUsername = nil
        fiatCurrencyCode = nil
        fiatAmount = nil
        requiredFields = []
    }

    private init(bip73URL url: URL, scheme: String) {
        kind = .bip73URL
        self.scheme = scheme
        address = nil
        amount = nil
        label = nil
        message = nil
        r = url
        callbackScheme = nil
        dashpayUsername = nil
        fiatCurrencyCode = nil
        fiatAmount = nil
        requiredFields = []
    }

    /// Decimal DASH string → duffs (1 DASH = 100_000_000 duffs), via `Decimal` to avoid binary
    /// floating-point error, rounding **up** to the next duff for sub-duff remainders
    /// (`DSPaymentRequest.m:146` `NSRoundUp` parity). nil for an unparseable or negative amount.
    private static func duffs(fromDecimalDash value: String) -> UInt64? {
        guard !value.isEmpty, let dash = Decimal(string: value), dash >= 0 else { return nil }
        return NSDecimalNumber(decimal: dash * Decimal(100_000_000))
            .rounding(accordingToBehavior: roundUpToDuff).uint64Value
    }

    private static let roundUpToDuff = NSDecimalNumberHandler(roundingMode: .up,
                                                              scale: 0,
                                                              raiseOnExactness: false,
                                                              raiseOnOverflow: false,
                                                              raiseOnUnderflow: false,
                                                              raiseOnDivideByZero: false)
}

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
    /// true when `amount=` (or `req-amount=`) is present but empty, not a plain decimal as a whole, beyond `UInt64`
    /// duffs, or given more than once with different values: `amount` is nil then too, and a reader that rejects such
    /// a link tells the two apart here. The same amount given twice is that amount.
    let hasInvalidAmount: Bool
    let label: String?
    let message: String?
    /// `?r=` BIP72 payment-request URL — the BIP70 trigger. For `.bip73URL` it's the input itself.
    let r: URL?
    /// How many different payment requests the `r=` / `req-r=` fields name, whether or not their value parsed as a
    /// URL: a reader that refuses a link with a payment request, or with more than one, counts them here, not `r`. The
    /// same value given twice (`r` and `req-r` alike) is one request.
    let paymentRequestCount: Int
    /// `?sender=` x-callback-url scheme to open after a successful send. nil when `sender` and `req-sender` differ.
    let callbackScheme: String?
    /// true when `sender=` / `req-sender=` are given more than once with different values (compared without regard
    /// to case, as URL schemes are): which app to call back is open, so a reader that honors the callback rejects the
    /// link.
    let hasConflictingCallback: Bool
    /// true when `label=` / `req-label=` or `message=` / `req-message=` give different values and one of them is
    /// required: which text the link requires is open, so a reader rejects the link.
    let hasConflictingRequiredText: Bool
    /// true when the query cannot be read whole: a line break or tab sits in it, or a field name holds a space. The
    /// link was broken across lines or words, and a field after the break (`req-r=` among them) would be read as part
    /// of another or dropped, so a reader rejects the link.
    let hasMalformedQuery: Bool
    /// `?user=` DashPay username. Parse-side value carry only — DashPay flows are deferred (C10).
    let dashpayUsername: String?
    /// `?currency=` requested fiat code (our own receive screen emits it alongside `local=`).
    let fiatCurrencyCode: String?
    /// `?local=` requested fiat amount. `NSString.floatValue` semantics for `DSPaymentRequest`
    /// parity (unparseable → 0). nil when the param is absent.
    let fiatAmount: Float?
    /// Keys carrying the `req-` prefix (params the request demands; amount immutability etc.).
    let requiredFields: Set<String>

    /// Where a payment's amount comes from, when the link's terms can be honored.
    enum AmountSource: Equatable {
        /// The link's own amount (or none).
        case link
        /// The link's optional amount is malformed and its one payment request can be fetched: the merchant's
        /// request sets the amount, so the request is required and the link's address is never paid instead.
        case paymentRequest
    }

    /// The one judgement of a link's terms that every reader paying it makes (the Send flow, the scanner and deep
    /// links, DashSpend); nil when the link leaves what it asks open: two different callbacks, a required label or
    /// message given twice differently, a query broken across lines or words, more than one payment request, or a
    /// malformed or contradictory amount that no payment request can replace. A reader adds only its own rules on
    /// top (which `req-` fields it keeps, whether it honors a callback).
    var amountSource: AmountSource? {
        guard !hasConflictingCallback, !hasConflictingRequiredText, !hasMalformedQuery,
              paymentRequestCount <= 1 else { return nil }
        guard hasInvalidAmount else { return .link }
        guard fetchableRequestURL != nil, !requiredFields.contains("amount") else { return nil }
        return .paymentRequest
    }

    /// `r` when it is the link's only payment request and an http(s) URL with a host, the only form a payment
    /// request is fetched from.
    var fetchableRequestURL: URL? {
        guard paymentRequestCount == 1 else { return nil }
        return r.flatMap(Self.fetchableRequestURL)
    }

    /// `url` when it is an http(s) URL with a host.
    static func fetchableRequestURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// true ⇒ BIP70 protocol flow (fetch `r`); false ⇒ plain BIP21 address send.
    var isBIP70: Bool { r != nil }

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }

        // Scheme normalization (pay: → dash:). `dashwallet:` is only the plain `dash:` alias here;
        // the `dashwallet://pay=` deep-link form is not parsed (`pay=` stays in the address) —
        // see `ParsedPaymentURI.deepLinkPaymentString`.
        switch trimmed[..<colon].lowercased() {
        case "pay", "dash", "dashwallet": scheme = "dash"
        case "bitcoin": scheme = "bitcoin"
        default: return nil
        }
        kind = .paymentURI

        // Strip the scheme + optional "//", then split the address from the query.
        var rest = String(trimmed[trimmed.index(after: colon)...])
        if rest.hasPrefix("//") { rest = String(rest.dropFirst(2)) }

        // BIP21 introduces the query with `?`, but wallets and payment pages in
        // the wild also emit `dash:<address>&amount=…`. Splitting only on `?`
        // left the whole tail inside the address, which then failed validation
        // and the scan was rejected outright rather than losing just the amount.
        // Accept whichever separator comes first; `&` is already the pair
        // separator below, so a leading one yields the same key/value list.
        let addressPart: String
        let queryPart: String?
        if let q = rest.firstIndex(where: { $0 == "?" || $0 == "&" }) {
            addressPart = String(rest[..<q])
            queryPart = String(rest[rest.index(after: q)...])
        } else {
            addressPart = rest
            queryPart = nil
        }
        address = addressPart.isEmpty ? nil : (addressPart.removingPercentEncoding ?? addressPart)

        // Parse the query string.
        var amount: UInt64?
        var hasInvalidAmount = false
        var hasAmount = false
        var label: String?
        var message: String?
        var r: URL?
        var paymentRequestValues: Set<String> = []
        var callbackValue: String?
        // The first callback's spelling for the comparison, made once: a repeat is compared with it, never the first
        // value normalized again, and nothing is compared after the first conflict.
        var normalizedCallback: String?
        var hasConflictingCallback = false
        var textValues: [String: Set<String>] = [:]
        var requiredTextFields: Set<String> = []
        var hasMalformedQuery = queryPart?.contains(where: { $0.isNewline || $0 == "\t" }) ?? false
        var dashpayUsername: String?
        var fiatCurrencyCode: String?
        var fiatAmount: Float?
        var requiredFields: Set<String> = []

        for pair in queryPart?.split(separator: "&") ?? [] {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = kv.first else { continue }
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            // Checked decoded, as the field is read: `req%20r` is a broken `req-r` as much as `req r` is.
            if key.contains(where: \.isWhitespace) { hasMalformedQuery = true }

            if key.hasPrefix("req-") { requiredFields.insert(String(key.dropFirst(4))) }

            switch key {
            case "amount", "req-amount":
                // A second, different amount, either spelling, leaves which one the link means open; a payment page
                // that repeats the link's own amount still means that amount.
                let parsed = Self.duffs(fromDecimalDash: value)
                if !hasAmount {
                    amount = parsed
                    hasInvalidAmount = parsed == nil
                } else if parsed == nil || parsed != amount {
                    amount = nil
                    hasInvalidAmount = true
                }
                hasAmount = true
            case "label", "req-label", "message", "req-message":
                let name = key.hasPrefix("req-") ? String(key.dropFirst(4)) : key
                if key.hasPrefix("req-") { requiredTextFields.insert(name) }
                textValues[name, default: []].insert(value)
                if name == "label" { label = value } else { message = value }
            case "r", "req-r":
                r = URL(string: value)
                paymentRequestValues.insert(value)
            case "sender", "req-sender":
                guard !hasConflictingCallback else { break }
                if let normalizedCallback {
                    if value.lowercased() != normalizedCallback { hasConflictingCallback = true }
                } else {
                    callbackValue = value
                    normalizedCallback = value.lowercased()
                }
            case "user", "req-user": dashpayUsername = value
            case "currency", "req-currency": fiatCurrencyCode = value
            case "local", "req-local": fiatAmount = (value as NSString).floatValue
            default: break
            }
        }

        self.amount = amount
        self.hasInvalidAmount = hasInvalidAmount
        self.label = label
        self.message = message
        self.r = r
        self.paymentRequestCount = paymentRequestValues.count
        // Not a scheme an app can own → no callback; the rest of the link still stands.
        self.callbackScheme = hasConflictingCallback ? nil : CallbackScheme.validated(callbackValue)
        self.hasConflictingCallback = hasConflictingCallback
        // Any two different values of a field one of whose spellings is required, in whatever order they came.
        self.hasConflictingRequiredText = requiredTextFields.contains { (textValues[$0]?.count ?? 0) > 1 }
        self.hasMalformedQuery = hasMalformedQuery
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
        hasInvalidAmount = false
        label = nil
        message = nil
        r = nil
        paymentRequestCount = 0
        callbackScheme = nil
        hasConflictingCallback = false
        hasConflictingRequiredText = false
        hasMalformedQuery = false
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
        hasInvalidAmount = false
        label = nil
        message = nil
        r = url
        paymentRequestCount = 1
        callbackScheme = nil
        hasConflictingCallback = false
        hasConflictingRequiredText = false
        hasMalformedQuery = false
        dashpayUsername = nil
        fiatCurrencyCode = nil
        fiatAmount = nil
        requiredFields = []
    }

    /// Decimal DASH string → duffs (1 DASH = 100_000_000 duffs), via `Decimal` to avoid binary
    /// floating-point error, rounding **up** to the next duff for sub-duff remainders
    /// (`DSPaymentRequest.m:146` `NSRoundUp` parity). nil unless the whole value is a decimal number (digits with at
    /// most one `.`, optionally an exponent as `DSPaymentRequest` took it; `Decimal(string:)` alone takes a numeric
    /// prefix of `1abc` or `1.2.3`), and for one whose duffs do not fit `UInt64` (`uint64Value` would return an
    /// arbitrary value for it, and a product past `Decimal`'s range is NaN, which compares below any bound). The value
    /// is bounded in length and its pattern has no overlapping repetitions, so a crafted amount is refused in linear
    /// time.
    private static func duffs(fromDecimalDash value: String) -> UInt64? {
        guard value.utf8.count <= maxAmountLength,
              value.wholeMatch(of: /(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/) != nil,
              let dash = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let duffs = NSDecimalNumber(decimal: dash * Decimal(100_000_000)).rounding(accordingToBehavior: roundUpToDuff)
        guard !duffs.decimalValue.isNaN,
              duffs.compare(NSDecimalNumber(value: UInt64.max)) != .orderedDescending else { return nil }
        return duffs.uint64Value
    }

    /// Longer than any amount a wallet writes: `UInt64.max` duffs is 21 characters as DASH.
    private static let maxAmountLength = 64

    private static let roundUpToDuff = NSDecimalNumberHandler(roundingMode: .up,
                                                              scale: 0,
                                                              raiseOnExactness: false,
                                                              raiseOnOverflow: false,
                                                              raiseOnUnderflow: false,
                                                              raiseOnDivideByZero: false)
}

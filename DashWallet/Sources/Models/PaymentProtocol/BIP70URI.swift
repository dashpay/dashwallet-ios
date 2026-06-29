//
//  BIP70URI.swift
//  DashWallet
//
//  BIP70 payment-protocol — `dash:`/BIP72 URI parser (Layer 5).
//
//  Replaces DashSync's `DSPaymentRequest` URI parsing for the BIP70 entry: it extracts the
//  fields the orchestrator needs (notably the BIP72 `r=` request URL and the `?sender=`
//  callback scheme) and hands a typed value to `BIP70PaymentService`. It does NOT fetch.
//
//  Pure: Foundation only. Mirrors `DWPaymentInputBuilder.m` / `DSPaymentRequest.m`:
//  `pay:` → `dash:` normalization, `dashwallet:`/`bitcoin:` accepted, percent-decoded query.
//

import Foundation

struct BIP70URI {
    /// Normalized payment scheme token: "dash" (default) or "bitcoin". Drives L3 content types.
    let scheme: String
    /// Fallback / plain-send address (BIP21/BIP72 carry it before the `?`). nil for `dash:?r=…`.
    let address: String?
    /// `?amount=` parsed from decimal DASH to duffs. Authoritative amount for a BIP70 send still
    /// comes from the signed `PaymentDetails`; this is for the plain-send fallback / UI hints.
    let amount: UInt64?
    let label: String?
    let message: String?
    /// `?r=` BIP72 payment-request URL — the BIP70 trigger.
    let r: URL?
    /// `?sender=` x-callback-url scheme to open after a successful send.
    let callbackScheme: String?
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
            case "sender": callbackScheme = value
            default: break
            }
        }

        self.amount = amount
        self.label = label
        self.message = message
        self.r = r
        self.callbackScheme = callbackScheme
        self.requiredFields = requiredFields
    }

    /// Decimal DASH string → duffs (1 DASH = 100_000_000 duffs), via `Decimal` to avoid binary
    /// floating-point error. nil for an unparseable amount.
    private static func duffs(fromDecimalDash value: String) -> UInt64? {
        guard !value.isEmpty, let dash = Decimal(string: value), dash >= 0 else { return nil }
        let duffs = NSDecimalNumber(decimal: dash * Decimal(100_000_000))
        return duffs.uint64Value
    }
}

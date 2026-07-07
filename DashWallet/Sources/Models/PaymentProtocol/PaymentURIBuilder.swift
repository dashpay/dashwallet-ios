//
//  PaymentURIBuilder.swift
//  DashWallet
//
//  App-side `dash:` (BIP21) URI serializer — the inverse of `BIP70URI` and the drop-in
//  replacement for DashSync's `DSPaymentRequest` `string`/`data`/`url` getters on the RECEIVE
//  side (QR display + share). Byte-for-byte parity with `DSPaymentRequest.m:171-220`: same param
//  order, same percent-encoding rules (label/message/r/currency encoded; amount/local/user raw),
//  same locale-independent amount formatting (`NSDecimalNumber.stringValue`, trailing zeros
//  dropped). `sender=`/callbackScheme is intentionally NOT emitted — DashSync parses it but never
//  serializes it.
//
//  Foundation only (no SDK / no network) so the swiftc harness can golden-test the output.
//  Address validity is the caller's concern (the receive address comes from the SDK).
//

import Foundation

@objc(DWPaymentURIBuilder)
final class PaymentURIBuilder: NSObject {
    @objc let address: String
    /// Amount in duffs; 0 ⇒ omitted.
    @objc let amount: UInt64
    @objc let label: String?
    @objc let message: String?
    /// BIP72 `r=` request URL.
    @objc let requestURL: URL?
    /// `currency=` requested fiat code.
    @objc let fiatCurrencyCode: String?
    /// `local=` requested fiat amount; > 0 (and a currency code present) ⇒ emitted.
    @objc let fiatAmount: Float
    /// `user=` DashPay username.
    @objc let dashpayUsername: String?

    @objc init(address: String,
               amount: UInt64,
               label: String?,
               message: String?,
               requestURL: URL?,
               fiatCurrencyCode: String?,
               fiatAmount: Float,
               dashpayUsername: String?) {
        self.address = address
        self.amount = amount
        self.label = label
        self.message = message
        self.requestURL = requestURL
        self.fiatCurrencyCode = fiatCurrencyCode
        self.fiatAmount = fiatAmount
        self.dashpayUsername = dashpayUsername
        super.init()
    }

    @objc convenience init(address: String) {
        self.init(address: address, amount: 0, label: nil, message: nil, requestURL: nil,
                  fiatCurrencyCode: nil, fiatAmount: 0, dashpayUsername: nil)
    }

    @objc convenience init(address: String, amount: UInt64) {
        self.init(address: address, amount: amount, label: nil, message: nil, requestURL: nil,
                  fiatCurrencyCode: nil, fiatAmount: 0, dashpayUsername: nil)
    }

    /// The `dash:<address>?…` URI. Mirrors `DSPaymentRequest.string`.
    @objc var string: String {
        var params: [String] = []

        // amount / local / user are appended RAW (URL-safe); label / message / r / currency are
        // percent-encoded — exactly as DSPaymentRequest.m does.
        if amount > 0 {
            params.append("amount=" + Self.dashString(fromDuffs: amount))
        }
        if let label, !label.isEmpty {
            params.append("label=" + Self.encoded(label))
        }
        if let message, !message.isEmpty {
            params.append("message=" + Self.encoded(message))
        }
        if let r = requestURL?.absoluteString, !r.isEmpty {
            params.append("r=" + Self.encoded(r))
        }
        if let fiatCurrencyCode, !fiatCurrencyCode.isEmpty {
            params.append("currency=" + Self.encoded(fiatCurrencyCode))
            if fiatAmount > 0 {
                params.append(String(format: "local=%.02f", Double(fiatAmount)))
            }
        }
        if let dashpayUsername, !dashpayUsername.isEmpty {
            params.append("user=" + dashpayUsername)
        }

        var uri = "dash:" + address
        if !params.isEmpty {
            uri += "?" + params.joined(separator: "&")
        }
        return uri
    }

    @objc var data: Data { Data(string.utf8) }

    @objc var url: URL? { URL(string: string) }

    /// Duffs → decimal DASH string, locale-independent (`.` separator), trailing zeros dropped —
    /// `NSDecimalNumber.stringValue` parity with `DSPaymentRequest.m:182-184`.
    /// 25_000_000 → "0.25", 100_000_000 → "1", 1 → "0.00000001".
    private static func dashString(fromDuffs duffs: UInt64) -> String {
        NSDecimalNumber(decimal: Decimal(duffs)).multiplying(byPowerOf10: -8).stringValue
    }

    /// Percent-encode with `urlQueryAllowed` minus `&=` (DSPaymentRequest.m:176-178).
    private static func encoded(_ value: String) -> String {
        var charset = CharacterSet.urlQueryAllowed
        charset.remove(charactersIn: "&=")
        return value.addingPercentEncoding(withAllowedCharacters: charset) ?? value
    }
}

//
//  DWParsedPaymentURI.swift
//  DashWallet
//
//  Immutable @objc record of one parsed payment string plus validity verdicts computed against
//  the app's current network (`WalletEnvironment`). The interactive ObjC payment flow (QR scan,
//  pasteboard/NFC, deeplink) reads THIS for every routing/validity decision; the `DSPaymentRequest`
//  it travels with (`DWPaymentInput.request`) is a write-only courier that only feeds DashSync's
//  protocol-request conversion, the sweep path, and the `userDetails` reconstruction — see
//  `DWPaymentInput.attachParsedURI:` (C8 step 2; the conversion is step 4).
//
//  Parsing/validation live here and in the pure `BIP70URI` value type; this class only bridges to
//  ObjC and pins the address verdict to the current network so the ObjC sites stop threading a
//  `DSChain` for it.
//

import Foundation

@objc(DWParsedPaymentURI)
final class ParsedPaymentURI: NSObject {
    /// The trimmed input, verbatim.
    @objc let rawString: String
    /// "dash"/"bitcoin" for an explicit URI, "http"/"https" for a BIP73 URL, nil when unparseable.
    @objc let scheme: String?
    /// Percent-decoded address (or a bare key string) — UNVALIDATED; consult
    /// `isAddressValidForCurrentNetwork`. nil for `dash:?r=…` and unparseable inputs.
    @objc let address: String?
    /// Amount in duffs; 0 when absent.
    @objc let amount: UInt64
    @objc let label: String?
    @objc let message: String?
    /// The BIP72 `r=` URL, or the whole BIP73 URL. nil when absent/unparseable — call sites fetch
    /// only when this is non-nil (the coordinator takes a non-optional `URL`).
    @objc let rURL: URL?
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
    @objc let isAddressValidForCurrentNetwork: Bool

    /// Mirrors `DSPaymentRequest.isValidAsNonDashpayPaymentRequest` (dash-only arm; the `bitcoin:`
    /// arms are compiled out under `SHAPESHIFT_ENABLED`, undefined in this app).
    @objc var isValidDashPaymentIntent: Bool {
        scheme == "dash" && (isAddressValidForCurrentNetwork || rURL != nil)
    }

    private init(rawString: String,
                 scheme: String?,
                 address: String?,
                 amount: UInt64,
                 label: String?,
                 message: String?,
                 rURL: URL?,
                 callbackScheme: String?,
                 dashpayUsername: String?,
                 fiatCurrencyCode: String?,
                 fiatAmount: Float,
                 hasExplicitScheme: Bool,
                 isAddressValidForCurrentNetwork: Bool) {
        self.rawString = rawString
        self.scheme = scheme
        self.address = address
        self.amount = amount
        self.label = label
        self.message = message
        self.rURL = rURL
        self.callbackScheme = callbackScheme
        self.dashpayUsername = dashpayUsername
        self.fiatCurrencyCode = fiatCurrencyCode
        self.fiatAmount = fiatAmount
        self.hasExplicitScheme = hasExplicitScheme
        self.isAddressValidForCurrentNetwork = isAddressValidForCurrentNetwork
        super.init()
    }

    /// Parse any interactive payment string. **Total** — an unparseable input yields a
    /// rawString-only box with false verdicts (mirroring `DSPaymentRequest requestWithString:`,
    /// which always returns an object), so ObjC nil-messaging needs no special cases.
    @objc(parsePaymentString:)
    static func parse(paymentString raw: String) -> ParsedPaymentURI {
        guard let uri = BIP70URI(paymentString: raw) else {
            return ParsedPaymentURI(rawString: raw, scheme: nil, address: nil, amount: 0,
                                    label: nil, message: nil, rURL: nil, callbackScheme: nil,
                                    dashpayUsername: nil, fiatCurrencyCode: nil, fiatAmount: 0,
                                    hasExplicitScheme: false, isAddressValidForCurrentNetwork: false)
        }

        let addressValid = uri.address?.isValidDashAddressForCurrentNetwork ?? false

        return ParsedPaymentURI(rawString: raw,
                                scheme: uri.scheme,
                                address: uri.address,
                                amount: uri.amount ?? 0,
                                label: uri.label,
                                message: uri.message,
                                rURL: uri.r,
                                callbackScheme: uri.callbackScheme,
                                dashpayUsername: uri.dashpayUsername,
                                fiatCurrencyCode: uri.fiatCurrencyCode,
                                fiatAmount: uri.fiatAmount ?? 0,
                                hasExplicitScheme: uri.kind != .bareAddress,
                                isAddressValidForCurrentNetwork: addressValid)
    }

    /// The fetch-failed fallback: a copy without the BIP70 request URL (was the
    /// `request.r = nil` mutation). `isValidDashPaymentIntent` then collapses to address validity.
    @objc(uriByClearingRequestURL)
    func byClearingRequestURL() -> ParsedPaymentURI {
        ParsedPaymentURI(rawString: rawString,
                         scheme: scheme,
                         address: address,
                         amount: amount,
                         label: label,
                         message: message,
                         rURL: nil,
                         callbackScheme: callbackScheme,
                         dashpayUsername: dashpayUsername,
                         fiatCurrencyCode: fiatCurrencyCode,
                         fiatAmount: fiatAmount,
                         hasExplicitScheme: hasExplicitScheme,
                         isAddressValidForCurrentNetwork: isAddressValidForCurrentNetwork)
    }
}

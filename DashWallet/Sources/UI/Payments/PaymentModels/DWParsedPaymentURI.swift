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
    /// Core (base58) only — the BIP70-fallback path still keys on this.
    @objc let isAddressValidForCurrentNetwork: Bool
    /// True when `address` is payable in ANY form this wallet supports on
    /// the current network: base58 Core, DIP-0018 bech32m Platform, or
    /// shielded. The QR scanner's accept gate.
    @objc let isAddressPayableForCurrentNetwork: Bool
    /// True when the address is a bech32m Platform/Shielded destination —
    /// those can't ride the classic L1 payment processor, so scan entry
    /// points route them into the Send screen instead.
    @objc let requiresSendScreenRouting: Bool

    /// Mirrors `DSPaymentRequest.isValidAsNonDashpayPaymentRequest` (dash-only arm; the `bitcoin:`
    /// arms are compiled out under `SHAPESHIFT_ENABLED`, undefined in this app), widened to accept
    /// every payable address form (bech32m Platform/Shielded included).
    @objc var isValidDashPaymentIntent: Bool {
        scheme == "dash" && (isAddressPayableForCurrentNetwork || rURL != nil)
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
                 isAddressValidForCurrentNetwork: Bool,
                 isAddressPayableForCurrentNetwork: Bool,
                 requiresSendScreenRouting: Bool) {
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
        self.isAddressPayableForCurrentNetwork = isAddressPayableForCurrentNetwork
        self.requiresSendScreenRouting = requiresSendScreenRouting
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
                                    hasExplicitScheme: false, isAddressValidForCurrentNetwork: false,
                                    isAddressPayableForCurrentNetwork: false,
                                    requiresSendScreenRouting: false)
        }

        let addressValid = uri.address?.isValidDashAddressForCurrentNetwork ?? false
        let classified = uri.address.flatMap(DashAddressClassifier.classify)
        let isBech32Destination = !addressValid && classified != nil

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
                                isAddressValidForCurrentNetwork: addressValid,
                                isAddressPayableForCurrentNetwork: addressValid || classified != nil,
                                requiresSendScreenRouting: isBech32Destination)
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
                         isAddressValidForCurrentNetwork: isAddressValidForCurrentNetwork,
                         isAddressPayableForCurrentNetwork: isAddressPayableForCurrentNetwork,
                         requiresSendScreenRouting: requiresSendScreenRouting)
    }
}

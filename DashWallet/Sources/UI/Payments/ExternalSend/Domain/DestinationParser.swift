//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Turns text into a `Destination` for a network, judging by the whole text and by format only:
/// no wallet, SDK service, network or UI is involved.
enum DestinationParser {
    private static let identityIDByteCount = 32
    /// The longest Base58 text a destination can have: an Identity ID (32 bytes) is at most 44 characters, a Core
    /// address (25 bytes with its checksum) at most 35. Base58 decoding is quadratic in the input length, so a longer
    /// word is refused before it is decoded.
    private static let maxBase58Length = 44

    /// A dash: link's `sender` is kept only when `openedByApp`: a link the wallet read itself (a scan, a paste, the
    /// Address field) names no app, so none is called back after the payment (docs/adr/0007).
    static func parse(_ text: String, network: WalletEnvironment.NetworkKind,
                      openedByApp: Bool = false) -> Result<Destination, DestinationParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalid) }

        guard trimmed.contains(":") else { return address(trimmed, network: network) }
        guard let link = BIP70URI(trimmed), link.scheme == "dash" else { return .failure(.invalid) }
        return parse(link: link, network: network, openedByApp: openedByApp)
    }

    /// What the clipboard offers: the whole text when the parser accepts it; otherwise the first word that is a bare
    /// destination, and only when no word of the text holds a part of a payment link. A link's terms may be spread
    /// over words or lines around it, so a link is never cut out of surrounding text, and neither is its address.
    static func find(in text: String, network: WalletEnvironment.NetworkKind) -> Destination? {
        if case .success(let destination) = parse(text, network: network) { return destination }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        guard !words.contains(where: holdsPartOfALink) else { return nil }
        for word in words {
            if case .success(let destination) = parse(word, network: network) { return destination }
        }
        return nil
    }

    private static let paymentSchemes = ["dash:", "pay:", "dashwallet:", "bitcoin:"]

    /// Text that starts with a payment scheme (`dash:`, `pay:`, `dashwallet:`, `bitcoin:`), alone or with the rest
    /// of a link after it. Prose such as `Address:` does not.
    static func startsWithPaymentScheme(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return paymentSchemes.contains(where: lowercased.hasPrefix)
    }

    /// A word that may be a piece of a payment link: it names a payment scheme anywhere (`"dash:X`, `(pay:`), or it
    /// starts a link's query (`?amount=1`, `&req-amount=1`). A `key=value` word alone is prose (`ref=42`).
    private static func holdsPartOfALink(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        return paymentSchemes.contains(where: lowercased.contains) || word.first == "?" || word.first == "&"
    }

    // MARK: - dash: links

    private static func parse(link: BIP70URI, network: WalletEnvironment.NetworkKind,
                              openedByApp: Bool) -> Result<Destination, DestinationParseError> {
        // The link's terms are judged once, as every reader judges them (`BIP70URI.amountSource`). On top, a field
        // the flow cannot honor invalidates the whole link: paying it without that field would pay something other
        // than what the link asks (BIP21 for `req-*`). A required field counts only when the destination keeps it: a
        // required request only when it can be fetched, a required callback only when it is made (another app opened
        // the link with a valid scheme; a Platform, Shielded or Identity link refuses it below). When the merchant's
        // request sets the amount, the request is required: the link's own address is never paid with an amount the
        // link did not state.
        let requestURL = link.fetchableRequestURL
        let callbackScheme = openedByApp ? link.callbackScheme : nil
        let requiresCallback = link.requiredFields.contains("sender")
        guard let amountSource = link.amountSource else { return .failure(.invalid) }
        let requiresRequest = link.requiredFields.contains("r") || amountSource == .paymentRequest
        guard link.requiredFields.isSubset(of: keptRequiredFields),
              !link.requiredFields.contains("r") || requestURL != nil,
              !requiresCallback || callbackScheme != nil else { return .failure(.invalid) }

        guard let linkAddress = link.address else {
            // `dash:?r=…`: a merchant request, the address comes with the fetched request.
            guard let requestURL else { return .failure(.invalid) }
            return .success(Destination(type: .paymentRequest, text: "", amountDuffs: link.amount,
                                        label: link.label, message: link.message, paymentRequestURL: requestURL,
                                        isPaymentRequestRequired: requiresRequest, callbackScheme: callbackScheme,
                                        isCallbackRequired: requiresCallback))
        }

        return address(linkAddress, network: network).flatMap { destination in
            switch destination.type {
            case .coreAddress:
                return .success(Destination(type: .coreAddress, text: destination.text,
                                            isScriptForm: destination.isScriptForm, amountDuffs: link.amount,
                                            label: link.label, message: link.message, paymentRequestURL: requestURL,
                                            isPaymentRequestRequired: requiresRequest, callbackScheme: callbackScheme,
                                            isCallbackRequired: requiresCallback))
            case .platformAddress, .shieldedAddress, .identityID:
                // Receive's payment request on Platform, Shielded or Identity: the address or the bare Identity ID,
                // then `amount=` in DASH, with the link's label and message as a Core link keeps them. A payment
                // request is a Core merchant's: paying this address instead would skip its verification, so a link
                // that carries one is refused, whether or not its URL parses.
                guard link.paymentRequestCount == 0, !requiresCallback else { return .failure(.invalid) }
                return .success(Destination(type: destination.type, text: destination.text,
                                            isScriptForm: destination.isScriptForm, amountDuffs: link.amount,
                                            label: link.label, message: link.message))
            case .paymentRequest:
                return .failure(.invalid)
            }
        }
    }

    /// The `req-` fields a `Destination` keeps: the amount, label, message, calling app, and the payment request.
    /// `user`, `currency` and `local` are parsed but not carried, so a link that requires one cannot be honored.
    private static let keptRequiredFields: Set<String> = ["amount", "label", "message", "sender", "r"]

    /// `url` when it is an http(s) URL with a host, the only form a payment request is fetched from.
    static func paymentRequestURL(_ url: URL) -> URL? {
        BIP70URI.fetchableRequestURL(url)
    }

    // MARK: - Bare addresses

    private static func address(_ text: String,
                                network: WalletEnvironment.NetworkKind) -> Result<Destination, DestinationParseError> {
        let isBase58Length = text.utf8.count <= maxBase58Length
        if isBase58Length, let decoded = ScriptAddressCodec.decodeAddress(text) {
            guard let form = PaymentNetworkResolver.token(for: network).addressForm(forVersion: decoded.version) else {
                // Another Dash network's version is that network's address; a version no Dash network uses (another
                // coin's address) is not a Dash address at all.
                let isAnotherDashNetwork = WalletEnvironment.NetworkKind.allCases.contains {
                    PaymentNetworkResolver.token(for: $0).addressForm(forVersion: decoded.version) != nil
                }
                return .failure(isAnotherDashNetwork ? .wrongNetwork : .invalid)
            }
            return .success(Destination(type: .coreAddress, text: text, isScriptForm: form == .scriptHash))
        }

        if let decoded = DashAddressClassifier.decodeBech32m(text) {
            guard decoded.isMainnet == (network == .mainnet) else { return .failure(.wrongNetwork) }
            switch decoded.form {
            case .platform(let isScript, _):
                return .success(Destination(type: .platformAddress, text: text, isScriptForm: isScript))
            case .shielded:
                return .success(Destination(type: .shieldedAddress, text: text))
            }
        }

        if isBase58Length, ScriptAddressCodec.base58Decode(text)?.count == identityIDByteCount {
            return .success(Destination(type: .identityID, text: text))
        }
        return .failure(.invalid)
    }
}

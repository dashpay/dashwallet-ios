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

    /// The first destination the parser accepts in the text (whole text first, then each word), or nil.
    static func find(in text: String, network: WalletEnvironment.NetworkKind) -> Destination? {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for candidate in [text] + words {
            if case .success(let destination) = parse(candidate, network: network) { return destination }
        }
        return nil
    }

    // MARK: - dash: links

    private static func parse(link: BIP70URI, network: WalletEnvironment.NetworkKind,
                              openedByApp: Bool) -> Result<Destination, DestinationParseError> {
        let requestURL = link.r.flatMap(paymentRequestURL)
        let callbackScheme = openedByApp ? link.callbackScheme : nil

        guard let linkAddress = link.address else {
            // `dash:?r=…`: a merchant request, the address comes with the fetched request.
            guard let requestURL else { return .failure(.invalid) }
            return .success(Destination(type: .paymentRequest, text: "", amountDuffs: link.amount,
                                        label: link.label, message: link.message, paymentRequestURL: requestURL,
                                        callbackScheme: callbackScheme))
        }

        return address(linkAddress, network: network).flatMap { destination in
            switch destination.type {
            case .coreAddress:
                return .success(Destination(type: .coreAddress, text: destination.text,
                                            isScriptForm: destination.isScriptForm, amountDuffs: link.amount,
                                            label: link.label, message: link.message, paymentRequestURL: requestURL,
                                            callbackScheme: callbackScheme))
            case .platformAddress, .shieldedAddress, .identityID:
                // Receive's payment request on Platform, Shielded or Identity: the address or the bare Identity ID,
                // then `amount=` in DASH, with the link's label and message as a Core link keeps them. A request URL
                // is a Core payment request's, so none is kept.
                return .success(Destination(type: destination.type, text: destination.text,
                                            isScriptForm: destination.isScriptForm, amountDuffs: link.amount,
                                            label: link.label, message: link.message))
            case .paymentRequest:
                return .failure(.invalid)
            }
        }
    }

    /// `url` when it is an http(s) URL with a host, the only form a payment request is fetched from.
    static func paymentRequestURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    // MARK: - Bare addresses

    private static func address(_ text: String,
                                network: WalletEnvironment.NetworkKind) -> Result<Destination, DestinationParseError> {
        let isBase58Length = text.utf8.count <= maxBase58Length
        if isBase58Length, let decoded = ScriptAddressCodec.decodeAddress(text) {
            guard let form = PaymentNetworkResolver.token(for: network).addressForm(forVersion: decoded.version) else {
                return .failure(.wrongNetwork)
            }
            return .success(Destination(type: .coreAddress, text: text, isScriptForm: form == .scriptHash))
        }

        if let decoded = DashAddressClassifier.decodeBech32m(text) {
            guard decoded.isMainnet == (network == .mainnet) else { return .failure(.wrongNetwork) }
            switch decoded.form {
            case .platform(let isScript):
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

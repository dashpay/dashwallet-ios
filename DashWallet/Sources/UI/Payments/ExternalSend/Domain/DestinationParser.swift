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

    /// The first word of the text the parser accepts, or nil. A word that may be part of a link split by a space or
    /// a line break is not offered, since the part left out may be what invalidates the link:
    /// - a word ending in `&`, `?` or `=`, or followed by a word starting with `?` or `&`;
    /// - a link (a word with a colon, or the word after a payment scheme alone, as in `dash: <address>`) that a later
    ///   word on its own line continues (it starts with `?` or holds `=` or `&`), however many words its query value
    ///   spans, or that the first word of the next line continues.
    /// A continuing word elsewhere in the text (another line, after an unrelated one) does not hide a link.
    static func find(in text: String, network: WalletEnvironment.NetworkKind) -> Destination? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
        let words = lines.enumerated().flatMap { line, words in words.map { (text: $0, line: line) } }
        var lastContinuationOnLine: [Int: Int] = [:]
        for (index, word) in words.enumerated() where continuesLink(word.text) { lastContinuationOnLine[word.line] = index }
        for (index, word) in words.enumerated() {
            guard case .success(let destination) = parse(word.text, network: network) else { continue }
            let next = index + 1 < words.count ? words[index + 1] : nil
            if let last = word.text.last, "&?=".contains(last) { continue }
            if let next, next.text.hasPrefix("?") || next.text.hasPrefix("&") { continue }
            let isLinkPart = word.text.contains(":") || (index > 0 && isSchemeAlone(words[index - 1].text))
            if isLinkPart {
                if let last = lastContinuationOnLine[word.line], last > index { continue }
                if let next, next.line != word.line, continuesLink(next.text) { continue }
            }
            return destination
        }
        return nil
    }

    /// `dash:`, `pay:`, `dashwallet:` or `bitcoin:` with nothing after it: the head of a link split from its address.
    /// Prose such as `Address:` is not one.
    private static func isSchemeAlone(_ word: String) -> Bool {
        ["dash:", "pay:", "dashwallet:", "bitcoin:"].contains(word.lowercased())
    }

    private static func continuesLink(_ word: String) -> Bool {
        word.hasPrefix("?") || word.contains("=") || word.contains("&")
    }

    // MARK: - dash: links

    private static func parse(link: BIP70URI, network: WalletEnvironment.NetworkKind,
                              openedByApp: Bool) -> Result<Destination, DestinationParseError> {
        // A field the flow cannot honor invalidates the whole link: paying it without that field would pay
        // something other than what the link asks (BIP21 for `req-*`). A required field counts only when the
        // destination keeps it: a required request only when it can be fetched, a required callback only when it
        // is made (another app opened the link with a valid scheme; a Platform, Shielded or Identity link refuses it
        // below). A link with more than one payment request, or with two different callbacks, leaves which one it
        // means open, as does a required label or message given twice with different values; a query broken across
        // lines or words cannot be read whole. A malformed optional amount beside a payment request that can be
        // fetched leaves the amount to the merchant's request, which is then required: the link's own address is
        // never paid with an amount the link did not state.
        let requestURL = link.r.flatMap(paymentRequestURL)
        let callbackScheme = openedByApp ? link.callbackScheme : nil
        let requiresCallback = link.requiredFields.contains("sender")
        let amountFromRequest = link.hasInvalidAmount && requestURL != nil && !link.requiredFields.contains("amount")
        let requiresRequest = link.requiredFields.contains("r") || amountFromRequest
        guard !link.hasInvalidAmount || amountFromRequest, link.paymentRequestFieldCount <= 1,
              !link.hasConflictingCallback, !link.hasConflictingRequiredText, !link.hasMalformedQuery,
              link.requiredFields.isSubset(of: keptRequiredFields),
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
                guard link.paymentRequestFieldCount == 0, !requiresCallback else { return .failure(.invalid) }
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

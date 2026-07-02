//
//  RefundAddressViewModel.swift
//  DashWallet
//
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

import Combine
import Foundation
import UIKit

@MainActor
final class RefundAddressViewModel: ObservableObject {
    let coin: MayaCryptoCurrency

    @Published var addressText: String = ""
    @Published var hasClipboardCandidate: Bool = false
    @Published var clipboardContent: String?
    @Published private(set) var shouldShowAddressValidationError: Bool = false

    var addressLabel: String {
        String(format: NSLocalizedString("%@ refund address", comment: "Dash DEX"), coin.code)
    }

    var subtitle: String {
        let chainLabel = MayaCryptoCurrency.chainDisplayName(coin.chain)
        return String(
            format: NSLocalizedString(
                "If the swap fails, your %@ will be returned to this address. Make sure it's a %@ address on the %@ network, from a wallet you control. Your swap can't be processed without a refund address.",
                comment: "Dash DEX"
            ),
            coin.code,
            coin.code,
            chainLabel
        )
    }

    var placeholderText: String {
        NSLocalizedString("Enter refund address", comment: "Dash DEX")
    }

    var isContinueEnabled: Bool {
        !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var showAddressError: Bool {
        shouldShowAddressValidationError && !isAddressValid
    }

    var addressValidationErrorMessage: String? {
        guard showAddressError else { return nil }
        let chainLabel = MayaCryptoCurrency.chainDisplayName(coin.chain)
        return String(
            format: NSLocalizedString(
                "Enter a valid %@ address. %@ here is on %@, so an Ethereum (0x…) address won’t work.",
                comment: "Swap"
            ),
            chainLabel,
            coin.code,
            chainLabel
        )
    }

    init(coin: MayaCryptoCurrency) {
        self.coin = coin
    }

    func refreshClipboardAddress() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif

        let hasCandidate = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs

        guard hasRevealedClipboard else {
            hasClipboardCandidate = hasCandidate
            clipboardContent = nil
            return
        }

        clipboardContent = validClipboardAddress()
        hasClipboardCandidate = clipboardContent != nil
    }

    func setAddress(_ address: String) {
        addressText = Self.extractAddressFromURI(address)
        clearValidationError()
    }

    func pasteFromClipboard() {
        if !hasRevealedClipboard {
            hasRevealedClipboard = true
            refreshClipboardAddress()
        }
        guard let content = currentClipboardContent() else { return }
        addressText = Self.extractAddressFromURI(content)
        clearValidationError()
    }

    func onAddressChanged() {
        clearValidationError()
    }

    func attemptContinue() -> String? {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Self.extractAddressFromURI(trimmed)
        guard !candidate.isEmpty else { return nil }

        shouldShowAddressValidationError = true
        guard MayaAddressValidator.isValid(address: candidate, for: coin) else { return nil }
        return candidate
    }

    private var isAddressValid: Bool {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Self.extractAddressFromURI(trimmed)
        guard !candidate.isEmpty else { return false }
        return MayaAddressValidator.isValid(address: candidate, for: coin)
    }

    private func clearValidationError() {
        shouldShowAddressValidationError = false
    }

    private func currentClipboardContent() -> String? {
        let rawContent = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        guard let rawContent else { return nil }
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validClipboardAddress() -> String? {
        guard let raw = currentClipboardContent() else { return nil }
        let address = Self.extractAddressFromURI(raw)
        guard !address.isEmpty,
              address.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return raw
    }

    private var hasRevealedClipboard = false

    // TODO: de-dup with EnterAddressViewModel once both screens share the same helper.
    private static func extractAddressFromURI(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") else {
            return trimmed
        }

        guard let colonIndex = trimmed.firstIndex(of: ":") else {
            return trimmed
        }

        let scheme = trimmed[..<colonIndex]
        let knownSchemes: Set<String> = ["bitcoin", "ethereum", "kujira", "thorchain", "dash"]
        guard knownSchemes.contains(scheme.lowercased()) else {
            return trimmed
        }

        var address = String(trimmed[trimmed.index(after: colonIndex)...])

        if let atIndex = address.firstIndex(of: "@") {
            address = String(address[..<atIndex])
        }

        if let queryIndex = address.firstIndex(of: "?") {
            address = String(address[..<queryIndex])
        }

        return address
    }
}

//
//  EnterAddressViewModel.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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
import SwiftUI
import UIKit

@MainActor
class EnterAddressViewModel: ObservableObject {
    let coin: MayaCryptoCurrency

    @Published var addressText: String = ""
    @Published var errorMessage: String?
    @Published var hasClipboardContent: Bool = false
    @Published var revealedClipboardContent: String?

    var placeholderText: String {
        String(format: NSLocalizedString("%@ address", comment: "Maya"), coin.code)
    }

    var isAddressValid: Bool {
        !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isClipboardRevealed: Bool {
        revealedClipboardContent != nil
    }

    init(coin: MayaCryptoCurrency) {
        self.coin = coin
    }

    func checkClipboard() {
        hasClipboardContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
    }

    func revealClipboard() {
        // Read clipboard content (triggers iOS paste permission banner on first access),
        // then set the published property so the view re-renders with content ready.
        // Animate the transition to prevent flash during system banner dismissal.
        let content = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        withAnimation(.easeInOut(duration: 0.2)) {
            revealedClipboardContent = content
        }
    }

    func pasteFromClipboard() {
        guard let content = revealedClipboardContent else { return }
        addressText = extractAddressFromURI(content)
        errorMessage = nil
    }

    func setAddress(_ address: String) {
        addressText = extractAddressFromURI(address)
        errorMessage = nil
    }

    // MARK: - Private

    /// Strips recognized crypto URI schemes and query parameters, returning the bare address.
    /// For example, `bitcoin:1abc...?amount=0.1` becomes `1abc...`.
    private func extractAddressFromURI(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip http/https URLs — they're not crypto addresses
        guard !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") else {
            return trimmed
        }

        // Check for scheme:address pattern
        guard let colonIndex = trimmed.firstIndex(of: ":") else {
            return trimmed
        }

        let scheme = trimmed[..<colonIndex]
        let knownSchemes: Set<String> = ["bitcoin", "ethereum", "kujira", "thorchain", "dash"]
        guard knownSchemes.contains(scheme.lowercased()) else {
            return trimmed
        }

        var address = String(trimmed[trimmed.index(after: colonIndex)...])

        // Strip EIP-681 chain ID (@chainId)
        if let atIndex = address.firstIndex(of: "@") {
            address = String(address[..<atIndex])
        }

        // Strip query parameters
        if let queryIndex = address.firstIndex(of: "?") {
            address = String(address[..<queryIndex])
        }

        return address
    }
}

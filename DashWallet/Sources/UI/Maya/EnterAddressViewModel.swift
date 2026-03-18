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

    // MARK: - Address Sources

    @Published var upholdState: AddressSourceState = .loggedOut
    @Published var coinbaseState: AddressSourceState = .loggedOut

    // MARK: - Clipboard (two-step: detect → reveal → paste)

    @Published var hasClipboardContent: Bool = false
    @Published var revealedClipboardContent: String?

    var isClipboardRevealed: Bool {
        revealedClipboardContent != nil
    }

    private let addressProvider = MayaExchangeAddressProvider()
    private var upholdAddress: String?
    private var coinbaseAddress: String?

    var placeholderText: String {
        String(format: NSLocalizedString("%@ address", comment: "Maya"), coin.code)
    }

    var isAddressValid: Bool {
        !addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The currency code to look up on exchanges.
    /// Uses the coin code directly — exchanges manage their own currency listings.
    /// If the exchange doesn't support the currency, the UI shows "Not available".
    private var exchangeCurrencyCode: String {
        coin.code
    }

    init(coin: MayaCryptoCurrency) {
        self.coin = coin
    }

    // MARK: - Load Address Sources

    func loadAddressSources() {
        loadUpholdState()
        loadCoinbaseState()
        checkClipboard()
    }

    private func loadUpholdState() {
        guard addressProvider.isUpholdAuthorized else {
            upholdState = .loggedOut
            return
        }

        upholdState = .loading

        Task {
            let address = await addressProvider.fetchUpholdAddress(for: exchangeCurrencyCode)
            if let address = address {
                upholdAddress = address
                upholdState = .available(address)
            } else {
                // Re-check authorization: if the session was revoked during the fetch,
                // show "Log In" instead of "Not available".
                if !addressProvider.isUpholdAuthorized {
                    upholdState = .loggedOut
                } else {
                    upholdState = .notAvailable
                }
            }
        }
    }

    private func loadCoinbaseState() {
        guard addressProvider.isCoinbaseAuthorized else {
            coinbaseState = .loggedOut
            return
        }

        coinbaseState = .loading

        Task {
            // Uses cached address if available, otherwise creates a new one
            let address = await addressProvider.fetchCoinbaseAddress(for: exchangeCurrencyCode)
            if let address = address {
                coinbaseAddress = address
                coinbaseState = .available(address)
            } else {
                // Re-check authorization: if the session was revoked during the fetch
                // (e.g., expired token after device restart), show "Log In" instead of
                // "Not available" so the user can re-authenticate.
                if !addressProvider.isCoinbaseAuthorized {
                    coinbaseState = .loggedOut
                } else {
                    coinbaseState = .notAvailable
                }
            }
        }
    }

    // MARK: - Address Selection

    func selectUpholdAddress() {
        guard let address = upholdAddress else { return }
        addressText = address
        errorMessage = nil
    }

    func selectCoinbaseAddress() {
        guard let address = coinbaseAddress else { return }
        addressText = address
        errorMessage = nil
    }

    // MARK: - Clipboard

    func checkClipboard() {
        hasClipboardContent = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
    }

    func revealClipboard() {
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

    // MARK: - Post-Login Refresh

    func onUpholdLoginCompleted() {
        upholdState = .loading

        Task {
            // Login triggers a fresh API fetch, replacing any cached address
            let address = await addressProvider.fetchAndCacheUpholdAddress(for: exchangeCurrencyCode)
            if let address = address {
                upholdAddress = address
                upholdState = .available(address)
            } else {
                upholdState = .notAvailable
            }
        }
    }

    func onCoinbaseLoginCompleted() {
        coinbaseState = .loading

        Task {
            // Login triggers a fresh address creation (POST), replacing any cached address
            let address = await addressProvider.createAndCacheCoinbaseAddress(for: exchangeCurrencyCode)
            if let address = address {
                coinbaseAddress = address
                coinbaseState = .available(address)
            } else {
                coinbaseState = .notAvailable
            }
        }
    }

    // MARK: - QR / Manual

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

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

    // MARK: - Published State

    @Published var addressText: String = ""
    @Published var errorMessage: String?
    @Published private(set) var shouldShowAddressValidationError: Bool = false

    @Published var upholdState: AddressSourceState = .loggedOut
    @Published var coinbaseState: AddressSourceState = .loggedOut

    @Published var hasClipboardCandidate: Bool = false
    @Published var clipboardContent: String?

    // MARK: - Computed Properties

    var addressLabel: String {
        String(format: NSLocalizedString("%@ address", comment: "Maya"), coin.code)
    }

    var placeholderText: String {
        String(format: NSLocalizedString("Long press to paste", comment: "Maya"))
    }

    var isContinueEnabled: Bool {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && addressValidationErrorMessage == nil && errorMessage == nil
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

    // MARK: - Private

    private let addressProvider = MayaExchangeAddressProvider()
    private var upholdAddress: String?
    private var coinbaseAddress: String?
    /// True once the user has opted in to reading the clipboard (tapped the clipboard row).
    /// Until then we only probe pasteboard metadata so the iOS paste banner is never surfaced
    /// unexpectedly — this preserves the existing permission flow.
    private var hasRevealedClipboard = false

    // MARK: - Init

    init(coin: MayaCryptoCurrency) {
        self.coin = coin
    }

    // MARK: - Source Loading

    func loadAddressSources() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif
        loadAddressSource(.uphold)
        loadAddressSource(.coinbase)
    }

    // MARK: - Clipboard

    /// Re-reads the clipboard and refreshes the clipboard card. Safe to call repeatedly —
    /// invoke it whenever the screen reappears or the app returns to the foreground so the card
    /// never shows a stale, previously-copied address.
    func refreshClipboardAddress() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif

        let hasCandidate = UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs

        // Preserve the permission flow: before the user opts in (taps the clipboard row) we only
        // probe pasteboard metadata — never the contents — so the iOS paste banner is not
        // surfaced. This just toggles the "Show content in the clipboard" row.
        guard hasRevealedClipboard else {
            hasClipboardCandidate = hasCandidate
            clipboardContent = nil
            return
        }

        // Opted in: re-read live and gate the card on a valid address for the selected coin.
        // Recomputed on every call so a newly-copied address replaces the old one, and a
        // cleared / invalid clipboard hides the card.
        clipboardContent = validClipboardAddress()
        hasClipboardCandidate = clipboardContent != nil
    }

    func pasteFromClipboard() {
        // First tap on the clipboard row opts the user in and reads the live clipboard.
        if !hasRevealedClipboard {
            hasRevealedClipboard = true
            refreshClipboardAddress()
        }
        guard let content = clipboardContent else { return }
        addressText = extractAddressFromURI(content)
        clearValidationError()
    }

    // MARK: - Manual Input

    func setAddress(_ address: String) {
        addressText = extractAddressFromURI(address)
        clearValidationError()
    }

    func onAddressChanged() {
        clearValidationError()
    }

    // MARK: - Address Selection

    func selectUpholdAddress() { selectStoredAddress(.uphold) }
    func selectCoinbaseAddress() { selectStoredAddress(.coinbase) }

    // MARK: - Continue Action

    /// Validates the current address text. Returns the trimmed address on success, or `nil` if invalid.
    /// Validation only happens here — the error state is NOT set on text changes.
    func attemptContinue() -> String? {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard validateCurrentAddress() else { return nil }
        return trimmed
    }

    // MARK: - Post-Login Callbacks

    func onUpholdLoginCompleted() { handleLoginCompleted(.uphold) }
    func onCoinbaseLoginCompleted() { handleLoginCompleted(.coinbase) }

    // MARK: - Private: Validation

    private var isAddressValid: Bool {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return MayaAddressValidator.isValid(address: trimmed, for: coin)
    }

    @discardableResult
    private func validateCurrentAddress() -> Bool {
        shouldShowAddressValidationError = true
        return isAddressValid
    }

    private func clearValidationError() {
        shouldShowAddressValidationError = false
        errorMessage = nil
    }

    // MARK: - Private: Source Kind

    private enum AddressSourceKind { case uphold, coinbase }

    private func loadAddressSource(_ kind: AddressSourceKind) {
        guard isAuthorized(kind) else { setSourceState(.loggedOut, for: kind); return }
        setSourceState(.loading, for: kind)
        Task {
            let address = await fetchAddressForLoad(kind)
            storeAddress(address, for: kind)
            // Re-check authorization in case the session was revoked during the fetch.
            setSourceState(resolveSourceState(address: address, isStillAuthorized: isAuthorized(kind)), for: kind)
        }
    }

    private func handleLoginCompleted(_ kind: AddressSourceKind) {
        setSourceState(.loading, for: kind)
        Task {
            let address = await fetchAddressAfterLogin(kind)
            storeAddress(address, for: kind)
            setSourceState(resolveSourceState(address: address, isStillAuthorized: isAuthorized(kind)), for: kind)
        }
    }

    private func selectStoredAddress(_ kind: AddressSourceKind) {
        guard let address = storedAddress(for: kind) else { return }
        addressText = address
        clearValidationError()
    }

    private func isAuthorized(_ kind: AddressSourceKind) -> Bool {
        switch kind {
        case .uphold: return addressProvider.isUpholdAuthorized
        case .coinbase: return addressProvider.isCoinbaseAuthorized
        }
    }

    private func setSourceState(_ state: AddressSourceState, for kind: AddressSourceKind) {
        switch kind {
        case .uphold: upholdState = state
        case .coinbase: coinbaseState = state
        }
    }

    private func storeAddress(_ address: String?, for kind: AddressSourceKind) {
        switch kind {
        case .uphold: upholdAddress = address
        case .coinbase: coinbaseAddress = address
        }
    }

    private func storedAddress(for kind: AddressSourceKind) -> String? {
        switch kind {
        case .uphold: return upholdAddress
        case .coinbase: return coinbaseAddress
        }
    }

    private func fetchAddressForLoad(_ kind: AddressSourceKind) async -> String? {
        switch kind {
        case .uphold: return await addressProvider.fetchUpholdAddress(for: coin)
        case .coinbase: return await addressProvider.fetchCoinbaseAddress(for: coin)
        }
    }

    private func fetchAddressAfterLogin(_ kind: AddressSourceKind) async -> String? {
        switch kind {
        case .uphold: return await addressProvider.fetchAndCacheUpholdAddress(for: coin)
        case .coinbase: return await addressProvider.createAndCacheCoinbaseAddress(for: coin)
        }
    }

    // MARK: - Private: Source State Mapping

    /// Maps a fetch result to the appropriate `AddressSourceState`.
    /// On failure, re-checks authorization to distinguish "not available" from "session expired".
    private func resolveSourceState(address: String?, isStillAuthorized: Bool) -> AddressSourceState {
        if let address { return .available(address) }
        return isStillAuthorized ? .notAvailable : .loggedOut
    }

    // MARK: - Private: Clipboard

    /// Returns the raw clipboard string when it holds a plausible address token, otherwise nil.
    /// Reads the pasteboard contents — only call once the user has opted in.
    ///
    /// Intentionally does NOT validate against the selected coin's chain: the clipboard row is
    /// offered for any address-like content (even a wrong-chain address) and the per-chain check
    /// happens on Continue. The only gate here is a cheap "looks like an address" heuristic — a
    /// single non-empty token with no internal whitespace — so multi-line/prose clipboard isn't
    /// surfaced as a paste suggestion.
    private func validClipboardAddress() -> String? {
        guard let raw = currentClipboardContent() else { return nil }
        let address = extractAddressFromURI(raw)
        guard !address.isEmpty,
              address.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return raw
    }

    private func currentClipboardContent() -> String? {
        let rawContent = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string
        guard let rawContent else { return nil }
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Private: URI Parsing

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

//
//  SendViewModel.swift
//  DashWallet
//

import Combine
import Foundation
import SwiftDashSDK
import UIKit

@MainActor
final class SendViewModel: ObservableObject {

    @Published var network: ChainNetwork = .core
    @Published var addressText: String = ""
    @Published private(set) var clipboardSuggestion: ClipboardSuggestion? = nil

    init() {
        refreshClipboardSuggestion()

        NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshClipboardSuggestion() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshClipboardSuggestion() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    struct ClipboardSuggestion: Equatable {
        let address: String
        let network: ChainNetwork
    }

    func refreshClipboardSuggestion() {
        guard let raw = UIPasteboard.general.string else {
            clipboardSuggestion = nil
            return
        }
        clipboardSuggestion = Self.detect(in: raw)
    }

    func useClipboardSuggestion() {
        guard let suggestion = clipboardSuggestion else { return }
        addressText = suggestion.address
        network = suggestion.network
    }

    func ingestScannedInput(_ paymentInput: DWPaymentInput) {
        // Read the parse box, not the DSPaymentRequest courier (C8 step 4); `.address` is the same
        // string the courier carried, then validated for the current network below.
        if let address = paymentInput.parsedURI?.address,
           !address.isEmpty,
           address.isValidDashAddressForCurrentNetwork {
            addressText = address
            network = .core
            return
        }
        if let raw = paymentInput.userDetails, Self.looksLikePlatformAddress(raw) {
            addressText = raw
            network = .platform
        }
    }

    /// Flip the Core/Platform toggle when the entered text validates unambiguously
    /// as the *other* network. Prevents the "can't press Continue" trap when a
    /// user pastes a `tdash1…` into a Core-selected screen (or vice versa).
    func autoSelectNetworkForCurrentAddress() {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let matchesCore = trimmed.isValidDashAddressForCurrentNetwork
        let matchesPlatform = Self.looksLikePlatformAddress(trimmed)

        if matchesPlatform && !matchesCore && network != .platform {
            network = .platform
        } else if matchesCore && !matchesPlatform && network != .core {
            network = .core
        }
    }

    var canContinue: Bool {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch network {
        case .core:
            return trimmed.isValidDashAddressForCurrentNetwork
        case .platform:
            return Self.looksLikePlatformAddress(trimmed)
        }
    }

    /// Lenient Platform-address check. `Bech32m.isValidPlatformAddress` is
    /// strict about HRPs `dashevo` / `tdashevo`, but dashwallet generates
    /// addresses with HRPs `dash` / `tdash` (visible in Storage Explorer and
    /// the Receive screen). Accept any of the four platform HRPs and rely on
    /// `Bech32m.decode` for checksum validation.
    private static func looksLikePlatformAddress(_ s: String) -> Bool {
        let lower = s.lowercased()
        let hasPlatformPrefix = lower.hasPrefix("tdashevo1")
            || lower.hasPrefix("dashevo1")
            || lower.hasPrefix("tdash1")
            || lower.hasPrefix("dash1")
        guard hasPlatformPrefix else { return false }
        return Bech32m.decode(s) != nil
    }

    private static func detect(in raw: String) -> ClipboardSuggestion? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        for candidate in trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(candidate)
            if Bech32m.isValidPlatformAddress(word) {
                return ClipboardSuggestion(address: word, network: .platform)
            }
            if word.isValidDashAddressForCurrentNetwork {
                return ClipboardSuggestion(address: word, network: .core)
            }
        }
        return nil
    }
}

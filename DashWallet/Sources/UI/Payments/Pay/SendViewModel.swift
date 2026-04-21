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
        let chain = DWEnvironment.sharedInstance().currentChain
        guard let raw = UIPasteboard.general.string else {
            clipboardSuggestion = nil
            return
        }
        clipboardSuggestion = Self.detect(in: raw, chain: chain)
    }

    func useClipboardSuggestion() {
        guard let suggestion = clipboardSuggestion else { return }
        addressText = suggestion.address
        network = suggestion.network
    }

    func ingestScannedInput(_ paymentInput: DWPaymentInput) {
        let chain = DWEnvironment.sharedInstance().currentChain
        if let address = paymentInput.request?.paymentAddress,
           !address.isEmpty,
           address.isValidDashAddress(on: chain) {
            addressText = address
            network = .core
            return
        }
        if let raw = paymentInput.userDetails, Bech32m.isValidPlatformAddress(raw) {
            addressText = raw
            network = .platform
        }
    }

    var canContinue: Bool {
        switch network {
        case .core:
            let chain = DWEnvironment.sharedInstance().currentChain
            return addressText.isValidDashAddress(on: chain)
        case .platform:
            return Bech32m.isValidPlatformAddress(addressText)
        }
    }

    private static func detect(in raw: String, chain: DSChain) -> ClipboardSuggestion? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        for candidate in trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(candidate)
            if Bech32m.isValidPlatformAddress(word) {
                return ClipboardSuggestion(address: word, network: .platform)
            }
            if word.isValidDashAddress(on: chain) {
                return ClipboardSuggestion(address: word, network: .core)
            }
        }
        return nil
    }
}

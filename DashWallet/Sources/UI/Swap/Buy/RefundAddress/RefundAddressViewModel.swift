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
    let coin: SwapCryptoCurrency
    let sellAmount: String
    let swapProvider: SwapProvider
    private let networkStatus: NetworkStatusProviding
    private var cancellables = Set<AnyCancellable>()

    @Published var addressText: String = ""
    @Published var hasClipboardCandidate: Bool = false
    @Published var clipboardContent: String?
    @Published private(set) var shouldShowAddressValidationError: Bool = false
    @Published private(set) var isSubmitting: Bool = false
    @Published private(set) var orderError: String?
    @Published private(set) var isOnline: Bool

    var addressLabel: String {
        NSLocalizedString("Refund address", comment: "Dash DEX / dex_refund_address_field_label")
    }

    var subtitle: String {
        return String(
            format: NSLocalizedString(
                "If the swap fails, your %@ will be returned to this address. Make sure it's a %@ address from a wallet you control.\n\nYour swap cannot be processed without a refund address.",
                comment: "Dash DEX / dex_refund_address_description"
            ),
            coin.code,
            coin.code
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
        return String(
            format: NSLocalizedString(
                "That refund address isn't a valid %@ address.",
                comment: "Dash DEX / dex_error_invalid_refund_address"
            ),
            coin.code
        )
    }

    init(coin: SwapCryptoCurrency, sellAmount: String, swapProvider: SwapProvider, networkStatus: NetworkStatusProviding = NetworkStatusService.shared) {
        self.coin = coin
        self.sellAmount = sellAmount
        self.swapProvider = swapProvider
        self.networkStatus = networkStatus
        self.isOnline = networkStatus.isOnline
        subscribeToNetworkStatus()
    }

    private func subscribeToNetworkStatus() {
        networkStatus.statusPublisher
            .sink { [weak self] status in
                self?.isOnline = status == .online
            }
            .store(in: &cancellables)
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
        orderError = nil
    }

    /// Validates address locally, then calls `createBuyOrder`. Returns the created order on
    /// success; sets `orderError` and returns nil on failure so the view stays put.
    func submitOrder() async -> BuyOrder? {
        guard isOnline, !isSubmitting else { return nil }

        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Self.extractAddressFromURI(trimmed)

        guard !candidate.isEmpty else {
            shouldShowAddressValidationError = true
            return nil
        }

        shouldShowAddressValidationError = true
        guard SwapAddressValidator.isValid(address: candidate, for: coin) else { return nil }

        guard let destination = DWEnvironment.sharedInstance().currentAccount.receiveAddress,
              !destination.isEmpty else {
            orderError = NSLocalizedString("Unable to determine your Dash receive address.", comment: "Dash DEX")
            return nil
        }

        isSubmitting = true
        orderError = nil
        defer { isSubmitting = false }

        do {
            let order = try await swapProvider.createBuyOrder(
                sellAsset: coin.swapAsset,
                sellAmount: sellAmount,
                destination: destination,
                refundAddress: candidate
            )
            persistBuyOrder(order, dashDestination: destination)
            return order
        } catch {
            orderError = SwapKitErrorCopy.message(
                for: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                coin: coin
            )
            return nil
        }
    }

    // MARK: - Private: Order persistence

    private func persistBuyOrder(_ order: BuyOrder, dashDestination: String) {
        // Buy orders always use SwapKit (Maya doesn't support Buy).
        let swapOrder = SwapOrder(
            id: order.depositAddress,
            direction: "buy",
            service: "swapkit",
            fromAsset: coin.swapAsset,
            toAsset: "DASH",
            toAddress: dashDestination,
            depositAddress: order.depositAddress,
            expectedToAmount: "\(order.expectedDashAmount)",
            status: .notStarted
        )
        Task {
            await SwapOrdersDAOImpl.shared.create(dto: swapOrder)
        }
    }

    private var isAddressValid: Bool {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Self.extractAddressFromURI(trimmed)
        guard !candidate.isEmpty else { return false }
        return SwapAddressValidator.isValid(address: candidate, for: coin)
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

        let scheme = String(trimmed[..<colonIndex])
        guard let firstChar = scheme.first, firstChar.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }),
              scheme.count <= 30 else {
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

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

import Combine
import Foundation
import DashUIKit

// MARK: - TransferSourceItem

/// Display data for a single From/To row in the transfer screen.
/// Derived from `ConverterViewDataSource.fromItem`/`toItem` so the display
/// logic stays identical without coupling SwiftUI to the UIKit `ConverterView` types.
struct TransferSourceItem {
    let title: String
    let subtitle: String?
    /// Dash balance in duffs (10⁸ per Dash) — feeds DashUIKit `MenuItem`'s `.balance` accessory.
    let dashBalance: Int64
    let fiatBalanceFormatted: String?
    let iconAssetName: String
}

// MARK: - TransferAmountViewModelProtocol

/// The surface `TransferAmountView` binds to. Extracted so the SwiftUI view can be driven
/// by a lightweight mock in previews without constructing the real `TransferAmountModel`
/// (which needs `Coinbase.shared` / an active session / network monitoring).
@MainActor
protocol TransferAmountViewModelProtocol: ObservableObject {
    var inputValue: String { get set }
    var selectedCurrency: DashUIKit.CurrencyOption { get set }
    var fromItem: TransferSourceItem { get }
    var toItem: TransferSourceItem { get }
    var isNetworkOnline: Bool { get }
    var canContinue: Bool { get }
    var errorMessage: String? { get }
    var isProcessing: Bool { get }
    /// Formatted Dash amount the user will receive (the entered amount — the network fee is added
    /// on top and does not reduce it). `nil` when no amount is entered.
    var receiveAmount: String? { get }
    /// Fiat value of `receiveAmount`, shown after it as `… ≈ <fiat>`.
    var receiveFiat: String? { get }
    var currencyOptions: [DashUIKit.CurrencyOption] { get }

    func setInput(_ raw: String)
    func setMax()
    func switchDirection()
    func selectFiatCurrency(_ code: String)
    func transfer()
}

// MARK: - TransferAmountViewModel

@MainActor
final class TransferAmountViewModel: ObservableObject, TransferAmountViewModelProtocol {

    // MARK: Published State

    @Published var inputValue: String = ""
    @Published var selectedCurrency: DashUIKit.CurrencyOption
    @Published private(set) var direction: TransferAmountModel.TransferDirection
    @Published private(set) var fromItem: TransferSourceItem
    @Published private(set) var toItem: TransferSourceItem
    @Published private(set) var isNetworkOnline: Bool
    @Published private(set) var canContinue: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var receiveAmount: String? = nil
    @Published private(set) var receiveFiat: String? = nil

    // MARK: Callbacks (wired by the hosting controller)

    var onInitiatePayment: ((DWPaymentInput) -> Void)?
    var onRequire2FA: ((UUID) -> Void)?
    var onInvalid2FACode: (() -> Void)?
    var onTransferSucceeded: (() -> Void)?
    /// Message is the failed-status screen text.
    var onTransferFailed: ((String) -> Void)?
    var onLimitExceeded: ((Error) -> Void)?
    /// Called when the toCoinbase direction would drain the wallet below the CrowdNode minimum.
    /// The closure receives a completion block; the host must call it with `true` (proceed) or
    /// `false` (cancel).  If nil the check is skipped and transfer proceeds.
    var onNeedsLeftoverWarning: ((@escaping (Bool) -> Void) -> Void)?

    // MARK: NetworkReachabilityHandling

    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!

    // MARK: Private

    private let model: TransferAmountModel
    private var cancellables = Set<AnyCancellable>()
    private var isSwitchingCurrency = false

    // MARK: Init

    init() {
        let m = TransferAmountModel()
        model = m
        selectedCurrency = .dash
        direction = m.direction
        let items = Self.sourceItems(for: m)
        fromItem = items.from
        toItem = items.to
        isNetworkOnline = NetworkReachability.shared.networkStatus == .online

        m.delegate = self

        networkStatusDidChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.isNetworkOnline = (status == .online)
            }
        }
        startNetworkMonitoring()
        isNetworkOnline = networkStatus == .online

        observeWalletBalance()
        observeCurrencySwitch()
        observeModelAmount()
        syncCanContinue()
        syncReceiveAmount()
        syncError()
    }

    deinit {
        stopNetworkMonitoring()
    }

    // MARK: Intents

    func setInput(_ raw: String) {
        let sanitized = Self.sanitize(raw, currency: selectedCurrency)
        guard inputValue != sanitized else { return }
        inputValue = sanitized
        model.updateAmountObjects(with: sanitized.isEmpty ? "0" : sanitized)
        syncCanContinue()
    }

    func setMax() {
        model.selectAllFundsWithoutAuth()
        syncInputValueFromModel()
        syncCanContinue()
    }

    func switchDirection() {
        model.direction = (model.direction == .toWallet) ? .toCoinbase : .toWallet
        direction = model.direction
        refreshSourceItems()
        // Re-run checkAmountForErrors() under the new direction so model.error
        // reflects the new validity; without this the error banner and button
        // state diverge after a swap (review finding #1).
        model.rebuildAmounts()
        syncCanContinue()
        syncError()
        syncReceiveAmount()
    }

    func selectFiatCurrency(_ code: String) {
        guard code != model.localCurrencyCode else { return }
        model.setupCurrencyCode(code)
        if case .fiat = selectedCurrency {
            selectedCurrency = .fiat(code)
        }
        syncInputValueFromModel()
        syncCanContinue()
    }

    func transfer() {
        isProcessing = true
        if model.direction == .toCoinbase {
            performLeftoverCheck { [weak self] canProceed in
                guard canProceed, let self else {
                    self?.isProcessing = false
                    return
                }
                self.model.initializeTransfer()
            }
        } else {
            model.initializeTransfer()
        }
    }

    func continue2FA(code: String, idem: UUID) {
        model.continueTransferFromCoinbase(with: code, idem: idem)
    }

    func cancel2FA() {
        isProcessing = false
    }

    var currencyOptions: [DashUIKit.CurrencyOption] { [.dash, .fiat(model.localCurrencyCode)] }

    // MARK: Private

    private func observeWalletBalance() {
        NotificationCenter.default
            .publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncCanContinue()
                self?.refreshSourceItems()
            }
            .store(in: &cancellables)
    }

    private func observeModelAmount() {
        model.$amount
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncReceiveAmount()
                self?.syncError()
            }
            .store(in: &cancellables)
    }

    private func observeCurrencySwitch() {
        $selectedCurrency
            .dropFirst()
            .sink { [weak self] newCurrency in
                guard let self, !self.isSwitchingCurrency else { return }
                self.isSwitchingCurrency = true
                switch newCurrency {
                case .dash:
                    self.model.select(inputItem: .dash)
                case .fiat(let code):
                    self.model.select(inputItem: .custom(currencyName: code, currencyCode: code))
                case .coin:
                    break
                }
                self.syncInputValueFromModel()
                self.isSwitchingCurrency = false
            }
            .store(in: &cancellables)
    }

    private func syncInputValueFromModel() {
        let rep = model.amount?.amountInternalRepresentation ?? "0"
        inputValue = (rep == "0") ? "" : rep
    }

    private func syncCanContinue() {
        canContinue = model.isAllowedToContinue
    }

    /// The Dash amount the user will receive (+ its fiat value). The network fee is added on top of
    /// the transfer, so the received amount equals the entered amount (never reduced by the fee).
    private func syncReceiveAmount() {
        let duffs = model.amount?.plainAmount ?? 0
        guard duffs != 0 else {
            receiveAmount = nil
            receiveFiat = nil
            return
        }
        receiveAmount = "\(duffs.formattedDashAmountWithoutCurrencySymbol) DASH"
        receiveFiat = fiatString(forDuffs: duffs)
    }

    /// Fiat value of a Dash amount (duffs), mirroring `BaseAmountModel.fiatWalletBalanceFormatted`.
    private func fiatString(forDuffs duffs: UInt64) -> String? {
        guard let fiatAmount = try? Coinbase.shared.currencyExchanger
            .convertDash(amount: duffs.dashAmount, to: model.localCurrencyCode) else { return nil }
        return model.supplementaryNumberFormatter.string(from: fiatAmount as NSNumber)
    }

    /// Surfaces the model's validation error (e.g. insufficient balance) for inline display.
    private func syncError() {
        errorMessage = model.error?.localizedDescription
    }

    private func refreshSourceItems() {
        let items = Self.sourceItems(for: model)
        fromItem = items.from
        toItem = items.to
    }

    /// Builds both From/To display items, resolving each side's numeric Dash balance (duffs)
    /// by direction: the Dash-wallet side uses `model.walletBalance`, the Coinbase side uses
    /// the Coinbase Dash account balance.
    private static func sourceItems(for model: TransferAmountModel) -> (from: TransferSourceItem, to: TransferSourceItem) {
        let wallet = (duffs: Int64(clamping: model.walletBalance), fiat: model.fiatWalletBalanceFormatted)
        let coinbase = (duffs: Int64(clamping: Coinbase.shared.dashAccount?.balance ?? 0),
                        fiat: Coinbase.shared.dashAccount?.fiatBalanceFormatted ?? "")
        let from = model.direction == .toCoinbase ? wallet : coinbase
        let to = model.direction == .toCoinbase ? coinbase : wallet
        return (makeSourceItem(from: model.fromItem, dashBalance: from.duffs, fiat: from.fiat),
                makeSourceItem(from: model.toItem, dashBalance: to.duffs, fiat: to.fiat))
    }

    private func performLeftoverCheck(completion: @escaping (Bool) -> Void) {
        if CrowdNodeDefaults.shared.lastKnownBalance <= 0 {
            completion(true)
            return
        }
        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = account.maxOutputAmount
        if (model.amount?.plainAmount ?? 0) + CrowdNode.minimumLeftoverBalance > allAvailableFunds {
            if let handler = onNeedsLeftoverWarning {
                handler(completion)
            } else {
                completion(true)
            }
        } else {
            completion(true)
        }
    }

    private static func makeSourceItem(from provider: SourceViewDataProvider?, dashBalance: Int64, fiat: String) -> TransferSourceItem {
        guard let provider else {
            return TransferSourceItem(title: "", subtitle: nil, dashBalance: 0, fiatBalanceFormatted: nil, iconAssetName: "")
        }
        let assetName: String
        switch provider.image {
        case .asset(let name): assetName = name
        case .remote: assetName = "Coinbase"
        }
        return TransferSourceItem(
            title: provider.title,
            subtitle: provider.subtitle,
            dashBalance: dashBalance,
            fiatBalanceFormatted: fiat.isEmpty ? nil : fiat,
            iconAssetName: assetName
        )
    }

    // MARK: Input Sanitization

    static func sanitize(_ raw: String, currency: DashUIKit.CurrencyOption) -> String {
        guard !raw.isEmpty else { return raw }

        let separator = Locale.current.decimalSeparator ?? "."
        let maxDecimals: Int
        switch currency {
        case .fiat: maxDecimals = 2
        case .dash, .coin: maxDecimals = 8
        }

        var intPart = ""
        var decPart = ""
        var sawSeparator = false
        for ch in raw {
            if String(ch) == separator {
                sawSeparator = true
                continue
            }
            guard ch.isNumber, ch.isASCII else { continue }
            if sawSeparator {
                if decPart.count < maxDecimals { decPart.append(ch) }
            } else {
                intPart.append(ch)
            }
        }

        let normalizedInt = normalizeLeadingZeros(intPart)
        return sawSeparator ? normalizedInt + separator + decPart : normalizedInt
    }

    private static func normalizeLeadingZeros(_ s: String) -> String {
        guard !s.isEmpty else { return "0" }
        var result = s
        while result.count > 1, result.hasPrefix("0") { result.removeFirst() }
        return result
    }
}

// MARK: TransferAmountModelDelegate

@MainActor
extension TransferAmountViewModel: TransferAmountModelDelegate {
    func coinbaseUserDidChange() {
        refreshSourceItems()
        syncCanContinue()
    }

    func initiatePayment(with input: DWPaymentInput) {
        isProcessing = false
        onInitiatePayment?(input)
    }
}

// MARK: CoinbaseTransactionDelegate

extension TransferAmountViewModel {
    func transferFromCoinbaseToWalletDidSucceed() {
        isProcessing = false
        onTransferSucceeded?()
    }

    func transferFromCoinbaseToWalletDidFail(with error: Error) {
        if case Coinbase.Error.transactionFailed(let reason) = error {
            switch reason {
            case .twoFactorRequired(let idem):
                // isProcessing stays true while the host controller shows the 2FA screen
                onRequire2FA?(idem)
            case .invalidVerificationCode:
                isProcessing = false
                onInvalid2FACode?()
            case .limitExceded:
                isProcessing = false
                errorMessage = error.localizedDescription
                onLimitExceeded?(error)
            case .message(let msg):
                isProcessing = false
                onTransferFailed?(msg)
            default:
                isProcessing = false
                onTransferFailed?(reason.localizedDescription)
            }
        } else {
            isProcessing = false
            errorMessage = error.localizedDescription
        }
    }

    func transferFromCoinbaseToWalletDidCancel() {
        isProcessing = false
    }
}

// MARK: NetworkReachabilityHandling

extension TransferAmountViewModel: NetworkReachabilityHandling {}

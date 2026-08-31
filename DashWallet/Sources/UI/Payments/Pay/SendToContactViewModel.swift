//
//  SendToContactViewModel.swift
//  DashWallet
//
//  View models for the Send tab's "Send to username" flow: the
//  established-contact picker, and the amount step that spends through
//  `WalletSendService.sendToContact`.
//

#if DASHPAY

import Combine
import Foundation
import SwiftDashSDK
import UIKit

// MARK: - Picker

/// The contact list behind "Send to username".
///
/// Reads the same snapshot the contacts tab lists under "My Contacts":
/// `SwiftDashSDKContactsService.contacts` holds only ESTABLISHED (mutual)
/// pairs, already sorted by display title. Pending incoming/outgoing
/// requests are separate snapshots and are deliberately not offered here —
/// a DIP-15 payment channel only exists once the friendship is mutual.
@MainActor
final class SendToContactPickerViewModel: ObservableObject {
    @Published private(set) var contacts: [ContactItem] = []
    @Published var searchText: String = ""

    private let service = SwiftDashSDKContactsService.shared

    init() {
        // Direct assign is safe: both objects are main-actor and the service
        // publishes on main — same wiring `ContactsViewModel` uses.
        service.$contacts.assign(to: &$contacts)
    }

    /// Rebuild the service snapshot from SwiftData. The payments stack never
    /// runs the contacts tab's own refresh, so without this the picker would
    /// show whatever the last visit to that tab left behind.
    func refresh() {
        service.refresh()
    }

    /// True when there is not a single established contact — the empty state,
    /// as opposed to a search that matched nothing.
    var hasNoContacts: Bool { contacts.isEmpty }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    /// Contacts matching the search text, in the service's display-title
    /// order. Hidden contacts are included: hiding tidies the contacts tab's
    /// list, it does not say the person can no longer be paid.
    var visibleContacts: [ContactItem] {
        let trimmed = trimmedSearchText
        guard !trimmed.isEmpty else { return contacts }
        return contacts.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(trimmed)
                || ($0.username?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}

// MARK: - Amount step

/// The amount step of "Send to username".
///
/// Contact payments are Core-only. `sendDashPayPayment` derives the
/// contact's DIP-15 receive address inside Rust from the (our identity,
/// their identity) pair and funds it from the BIP44 transparent balance;
/// no address ever crosses the FFI boundary, so there is nothing for a
/// Platform or Shielded source to pay to and the step carries no From
/// picker. The Transparent balance is shown read-only, and the typed
/// amount is validated against `feeAwareMaxSendable()` — the same
/// envelope `SendViewModel.coreSpendableDuffs` and Max use, and the cap
/// `WalletSendService.sendToContact` documents for its callers (the SDK
/// charges the network fee on top of the amount).
@MainActor
final class SendToContactAmountViewModel: ObservableObject {
    let contact: ContactItem

    /// Set while `applyMaxAmountText` writes `amountText`, so that write is
    /// not mistaken for the user typing over the Max selection.
    private var isApplyingMax = false

    @Published var amountText: String = "0" {
        didSet {
            guard !isApplyingMax else { return }
            maxAmountDuffs = nil
            // A new amount is a new attempt; the previous failure described
            // an amount that is no longer on screen.
            errorMessage = nil
        }
    }

    @Published var unit: InternalTransferUnit = .dash {
        didSet {
            guard oldValue != unit else { return }
            if let maxAmountDuffs {
                isApplyingMax = true
                defer { isApplyingMax = false }
                applyMaxAmountText(maxAmountDuffs)
            } else {
                convertAmountText(from: oldValue, to: unit)
            }
        }
    }

    /// Exact duff amount selected by Max. The two-decimal fiat value is only
    /// its display representation and must never be converted back for
    /// sending.
    private var maxAmountDuffs: UInt64?

    @Published private(set) var isSending = false

    /// Inline failure from the last send attempt. A PIN cancellation never
    /// lands here — backing out of the prompt is not an error.
    @Published private(set) var errorMessage: String?

    /// Total transparent balance, for the read-only source card.
    @Published private(set) var coreBalanceDuffs: UInt64 = 0

    @Published private(set) var isChainSynced = false

    private var cancellables = Set<AnyCancellable>()

    init(contact: ContactItem) {
        self.contact = contact
        coreBalanceDuffs = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        SyncingActivityMonitor.shared.add(observer: self)
        isChainSynced = SyncingActivityMonitor.shared.state == .syncDone

        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
            .sink { [weak self] balance in
                self?.coreBalanceDuffs = balance?.total ?? 0
            }
            .store(in: &cancellables)
    }

    deinit {
        // The monitor holds observers strongly — without this the view model
        // (and its Combine pipelines) outlive the screen.
        SyncingActivityMonitor.shared.remove(observer: self)
    }

    // MARK: - Balances

    /// L1-fee-aware spendable transparent balance — the envelope Max fills and
    /// affordability is judged against. Mirrors `SendViewModel
    /// .coreSpendableDuffs`.
    var spendableDuffs: UInt64 {
        SwiftDashSDKWalletState.shared.feeAwareMaxSendable()
    }

    var coreBalanceFormatted: String {
        InternalTransferViewModel.cardBalanceString(duffs: coreBalanceDuffs)
    }

    /// User-facing name of the balance being spent — "Transparent" only in
    /// advanced mode, per `ChainNetwork.balanceName`.
    var sourceTitle: String { ChainNetwork.core.balanceName }

    // MARK: - Amount

    /// The raw numeric value the user has typed, locale comma normalised.
    private var rawTypedDecimal: Decimal {
        let sanitized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: sanitized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// DASH value of the entered amount. A Max selection answers in its exact
    /// duffs rather than through the displayed (rounded) fiat figure.
    var parsedDashAmount: Decimal {
        if let maxAmountDuffs {
            return maxAmountDuffs.dashAmount
        }
        let raw = rawTypedDecimal
        switch unit {
        case .dash:
            return raw
        case .fiat:
            guard raw > 0 else { return 0 }
            return (try? CurrencyExchanger.shared.convertToDash(amount: raw, currency: App.fiatCurrency)) ?? 0
        }
    }

    /// The amount handed to `sendToContact`, in duffs.
    var amountDuffs: UInt64 { parsedDashAmount.plainDashAmount }

    var fiatCurrencyCode: String { App.fiatCurrency }

    var isDashInputSelected: Bool { unit == .dash }

    /// What the keypad edits: the typed string, with the "0" placeholder
    /// rendered as empty so the first keystroke replaces it.
    var keypadText: String {
        get { amountText == "0" ? "" : amountText }
        set { amountText = newValue.isEmpty ? "0" : newValue }
    }

    /// DASH figure for `EnterAmountView`'s primary slot — the typed text while
    /// DASH is the input unit, the converted value otherwise.
    var dashAmountText: String {
        switch unit {
        case .dash:
            return keypadText
        case .fiat:
            guard parsedDashAmount > 0 else { return "" }
            return InternalTransferViewModel.formatTyped(parsedDashAmount, fractionDigits: 8)
        }
    }

    /// Fiat figure for `EnterAmountView`'s secondary slot. Empty while the
    /// amount is zero or the exchange rate has not arrived.
    var fiatAmountText: String {
        switch unit {
        case .dash:
            guard parsedDashAmount > 0,
                  let fiatAmount = try? CurrencyExchanger.shared.convertDash(
                      amount: parsedDashAmount,
                      to: fiatCurrencyCode)
            else { return "" }
            return InternalTransferViewModel.formatTyped(fiatAmount, fractionDigits: 2)
        case .fiat:
            return keypadText
        }
    }

    var amountCurrencyCodes: [String] { ["DASH", fiatCurrencyCode] }

    var selectedAmountCurrencyCode: String {
        isDashInputSelected ? "DASH" : fiatCurrencyCode
    }

    func toggleUnit() {
        unit = isDashInputSelected ? .fiat : .dash
    }

    func selectCurrency(_ currencyCode: String) {
        unit = currencyCode.caseInsensitiveCompare("DASH") == .orderedSame ? .dash : .fiat
    }

    /// Fee-aware Max: the largest amount that still leaves room for the
    /// network fee the SDK charges on top. Same envelope as the Core send's.
    func fillMax() {
        isApplyingMax = true
        defer { isApplyingMax = false }
        applyMaxAmountText(spendableDuffs)
    }

    /// Keep the selected Max amount exact in duffs while rendering either
    /// DASH or an approximate two-decimal fiat value.
    private func applyMaxAmountText(_ duffs: UInt64) {
        guard duffs > 0 else {
            maxAmountDuffs = nil
            amountText = "0"
            return
        }

        maxAmountDuffs = duffs
        switch unit {
        case .dash:
            amountText = duffs.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            if let fiat = try? CurrencyExchanger.shared.convertDash(
                amount: duffs.dashAmount,
                to: fiatCurrencyCode) {
                amountText = InternalTransferViewModel.formatTyped(fiat, fractionDigits: 2)
            } else {
                maxAmountDuffs = nil
                amountText = "0"
            }
        }
    }

    private func convertAmountText(from old: InternalTransferUnit, to new: InternalTransferUnit) {
        let raw = rawTypedDecimal
        guard raw > 0 else { return }
        let currency = fiatCurrencyCode
        do {
            switch (old, new) {
            case (.dash, .fiat):
                let fiat = try CurrencyExchanger.shared.convertDash(amount: raw, to: currency)
                amountText = InternalTransferViewModel.formatTyped(fiat, fractionDigits: 2)
            case (.fiat, .dash):
                let dash = try CurrencyExchanger.shared.convertToDash(amount: raw, currency: currency)
                amountText = InternalTransferViewModel.formatTyped(dash, fractionDigits: 8)
            default:
                break
            }
        } catch {
            // Rate fetch failed — leave `amountText` as-is so the user can re-type.
        }
    }

    // MARK: - Validation

    /// A restored wallet's first historical sync blocks every transparent
    /// spend, and a contact payment is one — `sendToContact` throws on it
    /// (`ensureInitialRestoreSyncCompleted`). Gate the button instead of
    /// letting the user reach a failure the screen never warned about.
    var isBlockedBySync: Bool {
        WalletSendService.isBlockedByInitialRestoreSync(
            isResyncingWallet: DWGlobalOptions.sharedInstance().isResyncingWallet,
            isChainSynced: isChainSynced)
    }

    /// Being established is not the same as being payable: the SDK can fail
    /// permanently to build the contact's DIP-15 external account, and every
    /// send on that channel would then fail. The picker says so on the row;
    /// this is the backstop for the step itself.
    var isPaymentChannelBroken: Bool { contact.paymentChannelBroken }

    /// Inline explanation for an amount that cannot be sent. Quiet until the
    /// user types something.
    var amountValidationMessage: String? {
        guard amountDuffs > 0 else { return nil }
        return TransferSpendAmountPolicy.insufficientBalanceMessage(
            balanceName: sourceTitle,
            requestedDuffs: amountDuffs,
            spendableDuffs: spendableDuffs)
    }

    var canSend: Bool {
        guard !isSending, !isBlockedBySync, !isPaymentChannelBroken else { return false }
        let duffs = amountDuffs
        return duffs > 0 && duffs <= spendableDuffs
    }

    // MARK: - Send

    /// Run the pay-to-contact spend. `sendToContact` owns the spend-auth gate
    /// and broadcasts atomically — there is no prepare/confirm split on this
    /// path, so the Send tap is the confirmation.
    ///
    /// - Returns: the broadcast transaction's wire-order txid on success;
    ///   `nil` when it failed or the user cancelled the PIN prompt. A
    ///   cancellation leaves `errorMessage` clear.
    func send() async -> Data? {
        guard canSend else { return nil }
        let duffs = amountDuffs
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let (txid, _) = try await WalletSendService.shared.sendToContact(
                contactIdentityId: contact.contactIdentityId,
                amount: duffs)
            // Project the freshly recorded Sent entry to SwiftData right away
            // — the entry lives only in Rust memory until a projection runs,
            // and an app kill before one would lose it permanently (the SDK
            // cannot re-derive sent history).
            SwiftDashSDKContactsService.shared.refreshPaymentsProjection()
            return txid
        } catch {
            let nsError = error as NSError
            if !WalletSendService.isAuthenticationCancelledError(nsError) {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }
}

// MARK: - SyncingActivityMonitorObserver

extension SendToContactAmountViewModel: SyncingActivityMonitorObserver {
    nonisolated func syncingActivityMonitorProgressDidChange(_ progress: Double) {}

    nonisolated func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State,
                                                          state: SyncingActivityMonitor.State) {
        Task { @MainActor in
            self.isChainSynced = state == .syncDone
        }
    }
}

#endif

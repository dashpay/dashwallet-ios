//
//  PayContactViewModel.swift
//  DashWallet
//
//  Amount parsing, the sendable cap, and the send itself for paying a
//  DashPay contact.
//

import Combine
import SwiftUI

@MainActor
final class PayContactViewModel: ObservableObject {

    let contact: ContactItem

    @Published var amountText = ""
    @Published private(set) var isSending = false
    @Published private(set) var sentTxid: Data? = nil
    /// Exact network fee (duffs) of the broadcast transaction.
    @Published private(set) var sentFeeDuffs: UInt64? = nil
    /// Duffs actually broadcast, captured at send time.
    ///
    /// The confirmation must state what was paid, not what was typed. Echoing
    /// `amountText` back made any gap between the two — a locale separator, a
    /// stray character, precision the parser drops — render as a truthful-looking
    /// "sent" line for an amount that never left the wallet.
    @Published private(set) var sentAmountDuffs: UInt64? = nil
    @Published var errorMessage: String? = nil

    // MARK: - Dependencies

    /// All `nil` in previews. These are the singletons the screen must not
    /// wake from a canvas — the send service in particular reaches the PIN
    /// gate and the wallet.
    private let walletState: SwiftDashSDKWalletState?
    private let sendService: WalletSendService?
    private let contactsService: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    init(
        contact: ContactItem,
        walletState: SwiftDashSDKWalletState? = .shared,
        sendService: WalletSendService? = .shared,
        contactsService: SwiftDashSDKContactsService? = .shared
    ) {
        self.contact = contact
        self.walletState = walletState
        self.sendService = sendService
        self.contactsService = contactsService
        // The cap moves with the balance, and `maxSendable` is read during
        // layout, so the view has to be told when it changes.
        walletState?.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Amounts

    var maxSendable: UInt64 {
        walletState?.feeAwareMaxSendable() ?? 0
    }

    /// Entered DASH amount in duffs, or nil when unparseable, zero,
    /// or above the sendable cap. The cap check runs in `Decimal`
    /// space BEFORE the `UInt64` conversion — `NSDecimalNumber`'s
    /// `uint64Value` wraps modulo 2^64, so an overflowing input
    /// (e.g. 2^64 + 1 duffs) would otherwise alias to a tiny value
    /// that passes the range check and sends the wrong amount.
    var parsedDuffs: UInt64? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let dash = Decimal(string: normalized), dash > 0 else { return nil }
        let duffsDecimal = dash * Decimal(100_000_000)
        guard duffsDecimal <= Decimal(maxSendable) else { return nil }
        let duffs = NSDecimalNumber(decimal: duffsDecimal).uint64Value
        guard duffs > 0 else { return nil }
        return duffs
    }

    var fiatAmountText: String {
        guard let duffs = parsedDuffs else { return "" }
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return CurrencyExchanger.shared.fiatAmountString(for: dash)
    }

    /// Plain DASH rendering of a duff amount — used for the Max fill and the
    /// confirmation lines, both of which must show what the wallet computed.
    static func dashString(duffs: UInt64) -> String {
        let dash = Decimal(duffs) / Decimal(100_000_000)
        return "\(dash)"
    }

    func fillWithMax() {
        amountText = Self.dashString(duffs: maxSendable)
    }

    // MARK: - Pay

    func pay() {
        guard let sendService, let duffs = parsedDuffs, !isSending else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let (txid, feeDuffs) = try await sendService.sendToContact(
                    contactIdentityId: contact.contactIdentityId,
                    amount: duffs)
                sentTxid = txid
                sentFeeDuffs = feeDuffs
                sentAmountDuffs = duffs
                // Project the freshly recorded Sent entry to SwiftData
                // right away — the entry lives only in Rust memory
                // until a projection runs, and an app kill before one
                // would lose it permanently (the SDK cannot re-derive
                // sent history; learned the hard way 2026-07-08).
                contactsService?.refreshPaymentsProjection()
            } catch {
                let nsError = error as NSError
                if !WalletSendService.isAuthenticationCancelledError(nsError) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#if DEBUG

extension PayContactViewModel {
    /// Preview seed: no wallet state, no send service. `maxSendable` is 0
    /// without one, so `parsedDuffs` stays nil and the Pay button renders
    /// disabled — pass `sent:` to see the confirmation instead.
    static func preview(
        contact: ContactItem = .preview(title: "briantest63a"),
        amountText: String = "",
        sent: (txid: Data, amount: UInt64, fee: UInt64)? = nil
    ) -> PayContactViewModel {
        let model = PayContactViewModel(
            contact: contact, walletState: nil, sendService: nil, contactsService: nil)
        model.amountText = amountText
        if let sent {
            model.sentTxid = sent.txid
            model.sentAmountDuffs = sent.amount
            model.sentFeeDuffs = sent.fee
        }
        return model
    }
}

#endif

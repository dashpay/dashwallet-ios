//
//  ContactActivityViewModel.swift
//  DashWallet
//
//  Payment history with one contact, for the activity card.
//

import Combine
import SwiftDashSDK
import SwiftUI

@MainActor
final class ContactActivityViewModel: ObservableObject {

    /// One day's payments, newest day first. Grouped here rather than in the
    /// card so the view has nothing to compute — and so the day heading is
    /// derived once per load instead of per row.
    struct DayGroup: Identifiable {
        /// `DWDateFormatter.dateOnly` output — "Today", "Yesterday", or the
        /// date. Unique per day, which is what makes it usable as the id.
        let id: String
        let date: Date
        let payments: [SwiftDashSDKContactsService.ContactPayment]
    }

    @Published private(set) var groups: [DayGroup] = []
    /// Payment id → the wallet transaction behind it. A payment missing from
    /// this map has no local transaction to open, which is why the row's tap
    /// is offered per payment and not for the whole list.
    @Published private(set) var resolvedByTxid: [String: Transaction] = [:]
    /// Direction filter, shared with the home list's dialog. Only `.sent` and
    /// `.received` can ever match a contact payment; the rest are carried so
    /// the same `TransactionFilterDialog` binding fits.
    @Published var selectedFilters: Set<TransactionFilterCategory> =
        Set(TransactionFilterCategory.allCases) {
        didSet { groups = Self.grouped(allPayments.filter(matches)) }
    }

    /// True when this contact has any payments at all, regardless of the
    /// filter. The card keys its own presence on this rather than on
    /// ``groups``: a filter that hides every row must not take the filter
    /// control away with them.
    var hasAnyPayments: Bool { !allPayments.isEmpty }

    /// Everything loaded, before filtering — the source ``groups`` is
    /// recomputed from whenever the selection changes.
    private var allPayments: [SwiftDashSDKContactsService.ContactPayment] = []
    private let contactIdentityId: Data
    /// `nil` only in previews. Building the contacts service is not free —
    /// its initializer does real work — so a canvas must not reach it.
    private let service: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    init(contactIdentityId: Data, service: SwiftDashSDKContactsService? = .shared) {
        self.contactIdentityId = contactIdentityId
        self.service = service
        guard let service else { return }
        // A payment landing while the sheet is open republishes the contact
        // rows; reload from that rather than polling.
        service.$contacts
            .sink { [weak self] _ in self?.load() }
            .store(in: &cancellables)
    }

    func onAppear() {
        service?.refreshPaymentsProjection()
        load()
    }

    /// Main-thread SwiftData reads — a handful of rows, well under a frame
    /// each. Kept synchronous so the card never renders an empty list it is
    /// about to replace.
    private func load() {
        guard let service else { return }
        let rows = service.payments(with: contactIdentityId)
        var resolved: [String: Transaction] = [:]
        for payment in rows {
            if let wire = payment.txidWire,
               let tx = SwiftDashSDKWalletSource.fetch(txid: wire) {
                resolved[payment.id] = tx
            }
        }
        allPayments = rows
        groups = Self.grouped(rows.filter(matches))
        resolvedByTxid = resolved
    }

    /// A contact payment is only ever sent or received, so the other
    /// categories the dialog can carry cannot match one.
    private func matches(_ payment: SwiftDashSDKContactsService.ContactPayment) -> Bool {
        switch payment.direction {
        case .sent: selectedFilters.contains(.sent)
        case .received: selectedFilters.contains(.received)
        }
    }

    /// Split into days the way the home transaction list does — same
    /// `DWDateFormatter.dateOnly` key, so "Today" and "Yesterday" read
    /// identically in both places.
    ///
    /// `rows` arrives newest first and the order is preserved, so the groups
    /// come out newest first too without a second sort.
    static func grouped(
        _ rows: [SwiftDashSDKContactsService.ContactPayment]
    ) -> [DayGroup] {
        var order: [String] = []
        var byDay: [String: [SwiftDashSDKContactsService.ContactPayment]] = [:]
        for payment in rows {
            let key = DWDateFormatter.sharedInstance.dateOnly(from: payment.date)
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(payment)
        }
        return order.compactMap { key in
            guard let payments = byDay[key], let first = payments.first else { return nil }
            return DayGroup(id: key, date: first.date, payments: payments)
        }
    }
}

#if DEBUG

extension ContactActivityViewModel {
    /// Preview seed: no contacts service, so nothing loads or syncs.
    /// `resolvedByTxid` stays empty — a wallet transaction cannot be
    /// fabricated app-side, so preview rows are never tappable. Payments are
    /// passed flat and grouped by the same code the live path uses.
    static func preview(
        payments: [SwiftDashSDKContactsService.ContactPayment] = []
    ) -> ContactActivityViewModel {
        let model = ContactActivityViewModel(
            contactIdentityId: Data("preview".utf8), service: nil)
        model.allPayments = payments
        model.groups = grouped(payments)
        return model
    }
}

extension SwiftDashSDKContactsService.ContactPayment {
    static func preview(
        txid: String = "5b3f2c9a",
        amountDuffs: UInt64 = 125_000_000,
        direction: DashPayPaymentDirection = .sent,
        memo: String? = nil,
        daysAgo: Int = 0,
        fiatString: String? = "$4.21"
    ) -> Self {
        .init(
            txid: txid,
            amountDuffs: amountDuffs,
            direction: direction,
            memo: memo,
            date: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            fiatString: fiatString)
    }
}

#endif

//
//  ContactActivityViewModel.swift
//  DashWallet
//
//  What has happened with one contact — payments and the requests that
//  created the relationship — for the activity card.
//

import Combine
import SwiftDashSDK
import SwiftUI

@MainActor
final class ContactActivityViewModel: ObservableObject {

    /// A moment in the relationship that is not a payment. Derived from the
    /// contact's per-direction request timestamps, which is the only record
    /// of it there is.
    struct RelationshipEvent: Identifiable {
        enum Kind {
            /// We asked them.
            case requestSent
            /// They asked us.
            case requestReceived
            /// We reciprocated theirs, completing the friendship.
            case weAccepted
            /// They reciprocated ours.
            case theyAccepted
        }

        let kind: Kind
        let date: Date
        /// Their name, for the copy that mentions them.
        let counterparty: String
        var id: String { "\(kind)-\(date.timeIntervalSince1970)" }
    }

    /// One entry in the list. Payments and relationship events interleave
    /// strictly by time, so the card reads as a single history rather than
    /// two lists stacked on each other.
    enum Entry: Identifiable {
        case payment(SwiftDashSDKContactsService.ContactPayment)
        case event(RelationshipEvent)

        var id: String {
            switch self {
            case let .payment(payment): "payment-\(payment.id)"
            case let .event(event): "event-\(event.id)"
            }
        }

        var date: Date {
            switch self {
            case let .payment(payment): payment.date
            case let .event(event): event.date
            }
        }
    }

    /// One day's entries, newest day first. Grouped here rather than in the
    /// card so the view has nothing to compute — and so the day heading is
    /// derived once per load instead of per row.
    typealias DayGroup = DayGrouping.Day<Entry>

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
        didSet { regroup() }
    }

    /// True when this contact has any history at all, regardless of the
    /// filter. The card keys its own presence on this rather than on
    /// ``groups``: a filter that hides every row must not take the filter
    /// control away with them.
    var hasAnyActivity: Bool { !allPayments.isEmpty || !events.isEmpty }

    /// Everything loaded, before filtering — what ``groups`` is recomputed
    /// from whenever the selection changes.
    private var allPayments: [SwiftDashSDKContactsService.ContactPayment] = []
    private var events: [RelationshipEvent] = []
    private let contactIdentityId: Data
    /// `nil` only in previews. Building the contacts service is not free —
    /// its initializer does real work — so a canvas must not reach it.
    private let service: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    init(contactIdentityId: Data, service: SwiftDashSDKContactsService? = .shared) {
        self.contactIdentityId = contactIdentityId
        self.service = service
        guard let service else { return }
        // `service.refresh()` reassigns `contacts` on every (debounced)
        // `NSManagedObjectContextDidSave` — and that notification fires for
        // ANY SwiftData save, not just DashPay ones (a chain sync writing
        // ordinary transaction rows posts the same Core Data notification
        // SwiftData relies on). So while this sheet is open during an active
        // sync, `$contacts` can emit every ~300ms, almost always with a
        // byte-identical array, and every emission used to re-run this
        // view's whole load path.
        //
        // Two separate subscriptions, not one pipeline, because the two
        // things that can actually make this card stale change through
        // disjoint channels and need different treatment — chaining them
        // (e.g. `removeDuplicates()` then `throttle()`) would make the first
        // filter swallow everything the second one exists to catch:
        //  - a relationship/profile/alias change for THIS contact shows up
        //    in its `ContactItem` (Equatable), so mapping down to just that
        //    slice and `removeDuplicates()`-ing it reacts immediately to a
        //    real change while dropping every no-op tick for free — this
        //    alone kills the sync storm, since the request/profile rows
        //    `ContactItem` is built from don't change on an unrelated save.
        //  - a payment landing does NOT change `ContactItem` at all —
        //    payments live in a table `refresh()` never reads — so the dedup
        //    subscription above would never see it, and content-based dedup
        //    on the raw `contacts` array wouldn't either. Instead of trying
        //    to detect that case by content, `throttle(latest: true)` on the
        //    unfiltered publisher bounds *how often* a reload can run, so it
        //    can never permanently miss one. `refreshPaymentsProjection()` —
        //    the thing that actually adds a payment row — is itself
        //    throttled inside `refresh()` to at most once a minute, so a few
        //    seconds of added latency here is not a regression against what
        //    was already possible.
        service.$contacts
            .map { [contactIdentityId] contacts in
                contacts.first { $0.contactIdentityId == contactIdentityId }
            }
            .removeDuplicates()
            .sink { [weak self] _ in self?.load() }
            .store(in: &cancellables)

        service.$contacts
            .throttle(for: .seconds(3), scheduler: DispatchQueue.main, latest: true)
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
        // One context, one fetch for every payment's transaction — `fetch(txid:)`
        // opens a fresh `ModelContext` per call, which turned into 50 contexts
        // for 50 payments before this batch entry point existed.
        let wireByPaymentId = Dictionary(
            rows.compactMap { row -> (String, Data)? in row.txidWire.map { (row.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        let txByWireTxid = SwiftDashSDKWalletSource.fetch(txids: wireByPaymentId.values)
        var resolved: [String: Transaction] = [:]
        for (paymentId, wire) in wireByPaymentId {
            if let tx = txByWireTxid[wire] {
                resolved[paymentId] = tx
            }
        }
        allPayments = rows
        events = Self.relationshipEvents(
            for: service.contactItem(for: contactIdentityId))
        resolvedByTxid = resolved
        regroup()
    }

    private func regroup() {
        let entries = allPayments.filter(matches).map(Entry.payment)
            + events.map(Entry.event)
        groups = Self.grouped(entries)
    }

    /// A contact payment is only ever sent or received, so the other
    /// categories the dialog can carry cannot match one. Relationship events
    /// are not transactions and are never filtered out — the filter is about
    /// which payments to show.
    private func matches(_ payment: SwiftDashSDKContactsService.ContactPayment) -> Bool {
        switch payment.direction {
        case .sent: selectedFilters.contains(.sent)
        case .received: selectedFilters.contains(.received)
        }
    }

    // MARK: - Relationship history

    /// Reconstruct how the relationship came about from the contact's two
    /// request timestamps.
    ///
    /// DIP-15 has no separate "accept" document — accepting is sending your
    /// own contact request back — so the pair of timestamps is the whole
    /// record: the earlier one is the request, the later one the
    /// reciprocation. `ContactItem` states the same rule for `createdAt`.
    ///
    /// Ignoring a sender leaves nothing to show. It is local-only and drops
    /// the incoming request row outright (SDK `ignoreContactSender`), so
    /// there is no artifact to build an entry from — and an ignored sender is
    /// not a contact whose sheet can be opened anyway.
    static func relationshipEvents(for contact: ContactItem?) -> [RelationshipEvent] {
        guard let contact else { return [] }
        let name = contact.displayTitle

        switch contact.relationship {
        case .outgoing:
            return contact.outgoingCreatedAt.map {
                [RelationshipEvent(kind: .requestSent, date: $0, counterparty: name)]
            } ?? []

        case .incoming:
            return contact.incomingCreatedAt.map {
                [RelationshipEvent(kind: .requestReceived, date: $0, counterparty: name)]
            } ?? []

        case .established:
            guard let outgoing = contact.outgoingCreatedAt,
                  let incoming = contact.incomingCreatedAt else {
                // One row synced and the other hasn't yet. Show the half we
                // hold as a plain request rather than guessing who accepted.
                return [
                    contact.outgoingCreatedAt.map {
                        RelationshipEvent(kind: .requestSent, date: $0, counterparty: name)
                    },
                    contact.incomingCreatedAt.map {
                        RelationshipEvent(kind: .requestReceived, date: $0, counterparty: name)
                    },
                ].compactMap { $0 }
            }

            if outgoing <= incoming {
                return [
                    RelationshipEvent(kind: .requestSent, date: outgoing, counterparty: name),
                    RelationshipEvent(kind: .theyAccepted, date: incoming, counterparty: name),
                ]
            }
            return [
                RelationshipEvent(kind: .requestReceived, date: incoming, counterparty: name),
                RelationshipEvent(kind: .weAccepted, date: outgoing, counterparty: name),
            ]
        }
    }

    // MARK: - Grouping

    /// Split into days the way the home transaction list does — same
    /// `DWDateFormatter.dateOnly` key, so "Today" and "Yesterday" read
    /// identically in both places.
    static func grouped(_ entries: [Entry]) -> [DayGroup] {
        DayGrouping.byDay(entries) { $0.date }
    }
}

#if DEBUG

extension ContactActivityViewModel {
    /// Preview seed: no contacts service, so nothing loads or syncs.
    /// `resolvedByTxid` stays empty — a wallet transaction cannot be
    /// fabricated app-side, so preview rows are never tappable. Payments and
    /// events are passed flat and grouped by the same code the live path uses.
    static func preview(
        payments: [SwiftDashSDKContactsService.ContactPayment] = [],
        events: [RelationshipEvent] = []
    ) -> ContactActivityViewModel {
        let model = ContactActivityViewModel(
            contactIdentityId: Data("preview".utf8), service: nil)
        model.allPayments = payments
        model.events = events
        model.groups = grouped(payments.map(Entry.payment) + events.map(Entry.event))
        return model
    }
}

extension ContactActivityViewModel.RelationshipEvent {
    static func preview(
        kind: Kind,
        daysAgo: Int = 0,
        counterparty: String = "briantest63a"
    ) -> Self {
        .init(
            kind: kind,
            date: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            counterparty: counterparty)
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

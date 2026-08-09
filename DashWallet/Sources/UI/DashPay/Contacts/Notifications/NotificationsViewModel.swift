//
//  NotificationsViewModel.swift
//  DashWallet
//
//  Turns the contacts snapshots into the notification feed: every request
//  sent, received and accepted, split into days.
//

import Combine
import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {

    // MARK: - Feed

    /// One relationship event, paired with the contact it belongs to. The
    /// event itself carries no identity — this feed mixes people, so it needs
    /// the avatar and the row actions that only ``ContactItem`` provides.
    struct Event: Identifiable {
        struct ID: Hashable {
            let contactIdentityId: Data
            let kind: ContactActivityViewModel.RelationshipEvent.Kind
        }

        let item: ContactItem
        let event: ContactActivityViewModel.RelationshipEvent
        /// Newer than the read marker captured on entry.
        let isUnread: Bool

        var id: ID {
            ID(contactIdentityId: item.contactIdentityId, kind: event.kind)
        }

        var date: Date { event.date }
    }

    @Published private(set) var days: [DayGrouping.Day<Event>] = []
    /// Contact ids with an in-flight accept/ignore, mirrored from the
    /// contacts view model so rows can disable themselves.
    @Published private(set) var processingIds: Set<Data> = []
    @Published var errorMessage: String? = nil

    var isEmpty: Bool { days.isEmpty }

    // MARK: - Dependencies

    /// `nil` only in previews, which seed the feed directly. Every method
    /// that would reach the contacts service is a no-op in that state
    /// rather than constructing one — `SwiftDashSDKContactsService.shared`
    /// does real work in its initializer and must not be woken by a canvas.
    private(set) var contacts: ContactsViewModel?
    private let service: SwiftDashSDKContactsService?
    private let readMarker: () -> Date
    private var cancellables: Set<AnyCancellable> = []

    /// Read-state captured once at screen entry so rows don't change under
    /// the user while they are looking at them; the marker itself only
    /// advances on exit (``onDisappear()``).
    private var lastViewedAtEntry: Date = .distantPast

    convenience init() {
        self.init(
            contacts: ContactsViewModel(),
            service: .shared,
            readMarker: {
                DWGlobalOptions.sharedInstance().mostRecentViewedNotificationDate ?? .distantPast
            })
    }

    init(
        contacts: ContactsViewModel?,
        service: SwiftDashSDKContactsService?,
        readMarker: @escaping () -> Date
    ) {
        self.contacts = contacts
        self.service = service
        self.readMarker = readMarker

        guard let contacts else { return }
        // Any change to the three snapshots re-derives the feed. Mirrored
        // rather than read through, so the view observes one object.
        contacts.$contacts.map { _ in () }
            .merge(with: contacts.$incomingRequests.map { _ in () },
                   contacts.$outgoingRequests.map { _ in () })
            .sink { [weak self] in self?.rebuild() }
            .store(in: &cancellables)
        contacts.$processingIds.assign(to: &$processingIds)
        contacts.$errorMessage.assign(to: &$errorMessage)
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard let contacts else { return }
        lastViewedAtEntry = readMarker()
        contacts.refresh()
        rebuild()
    }

    func onDisappear() {
        service?.markNotificationsViewed()
    }

    func syncNow() async {
        await contacts?.syncNow()
    }

    // MARK: - Row actions

    func accept(_ item: ContactItem) { contacts?.accept(item) }
    func ignore(_ item: ContactItem) { contacts?.ignore(item) }
    func resolveUsernameIfNeeded(_ item: ContactItem) { contacts?.resolveUsernameIfNeeded(item) }

    // MARK: - Derivation

    /// Built from the same `relationshipEvents(for:)` the contact activity
    /// card reads, so a request cannot be described one way here and another
    /// way there — the rule for who reciprocated used to be written out in
    /// both places.
    ///
    /// That derivation returns the whole history of a pair, so an established
    /// contact contributes two entries (the request and its acceptance) where
    /// this feed previously showed only the acceptance. Both are things that
    /// happened, and the feed is grouped by day now, so they land where they
    /// belong instead of collapsing onto one date.
    private func rebuild() {
        guard let contacts else { return }
        let items = contacts.contacts + contacts.incomingRequests + contacts.outgoingRequests

        let events = items.flatMap { item in
            ContactActivityViewModel.relationshipEvents(for: item).map { event in
                Event(item: item, event: event, isUnread: event.date > lastViewedAtEntry)
            }
        }
        days = DayGrouping.byDay(events) { $0.date }
    }
}

#if DEBUG

extension NotificationsViewModel {
    /// Preview seed: a fixed feed with no contacts view model behind it, so
    /// nothing here touches the SDK.
    static func preview(events: [Event] = []) -> NotificationsViewModel {
        let model = NotificationsViewModel(
            contacts: nil, service: nil, readMarker: { .distantPast })
        model.days = DayGrouping.byDay(events) { $0.date }
        return model
    }
}

extension NotificationsViewModel.Event {
    /// `relationship` is explicit rather than derived from `kind`: an
    /// established contact contributes a `.requestSent` event too, and that
    /// row must not render the pending marker a still-open request gets.
    static func preview(
        title: String,
        kind: ContactActivityViewModel.RelationshipEvent.Kind,
        relationship: ContactRelationship = .established,
        daysAgo: Int = 0,
        isUnread: Bool = false
    ) -> Self {
        .init(
            item: .preview(title: title, relationship: relationship),
            event: .preview(kind: kind, daysAgo: daysAgo, counterparty: title),
            isUnread: isUnread)
    }
}

#endif

//
//  NotificationsViewModel.swift
//  DashWallet
//
//  Turns the contacts snapshots into the notification feed: one event per
//  incoming request, sent request, and established contact, split into
//  "New" and "Earlier" against the read marker.
//

import Combine
import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {

    // MARK: - Feed

    enum EventKind: Hashable {
        /// Pending incoming request — actionable.
        case incomingRequest
        /// Pending outgoing request we sent — awaiting their acceptance.
        case sentRequest
        /// Established because they reciprocated our request.
        case theyAccepted
        /// Established because we accepted their request.
        case weAccepted
    }

    struct Event: Identifiable {
        struct ID: Hashable {
            let contactIdentityId: Data
            let kind: EventKind
        }

        let item: ContactItem
        let kind: EventKind
        var id: ID {
            ID(contactIdentityId: item.contactIdentityId, kind: kind)
        }

        var date: Date { item.createdAt }
    }

    @Published private(set) var newEvents: [Event] = []
    @Published private(set) var earlierEvents: [Event] = []
    /// Contact ids with an in-flight accept/ignore, mirrored from the
    /// contacts view model so rows can disable themselves.
    @Published private(set) var processingIds: Set<Data> = []
    @Published var errorMessage: String? = nil

    var isEmpty: Bool { newEvents.isEmpty && earlierEvents.isEmpty }

    // MARK: - Dependencies

    /// `nil` only in previews, which seed the feed directly. Every method
    /// that would reach the contacts service is a no-op in that state
    /// rather than constructing one — `SwiftDashSDKContactsService.shared`
    /// does real work in its initializer and must not be woken by a canvas.
    private let contacts: ContactsViewModel?
    private let service: SwiftDashSDKContactsService?
    private let readMarker: () -> Date
    private var cancellables: Set<AnyCancellable> = []

    /// Read-state captured once at screen entry so rows don't jump between
    /// sections while the user is looking at them; the marker itself only
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

    private func rebuild() {
        guard let contacts else { return }
        let requests = contacts.incomingRequests.map { Event(item: $0, kind: .incomingRequest) }
        let sent = contacts.outgoingRequests.map { Event(item: $0, kind: .sentRequest) }
        let established = contacts.contacts.map { item -> Event in
            // The newer direction row is the reciprocation.
            let incoming = item.incomingCreatedAt ?? .distantPast
            let outgoing = item.outgoingCreatedAt ?? .distantPast
            return Event(item: item, kind: incoming >= outgoing ? .theyAccepted : .weAccepted)
        }
        let all = (requests + sent + established).sorted { $0.date > $1.date }
        newEvents = all.filter { $0.date > lastViewedAtEntry }
        earlierEvents = all.filter { $0.date <= lastViewedAtEntry }
    }
}

#if DEBUG

extension NotificationsViewModel {
    /// Preview seed: a fixed feed with no contacts view model behind it, so
    /// nothing here touches the SDK.
    static func preview(new: [Event] = [], earlier: [Event] = []) -> NotificationsViewModel {
        let model = NotificationsViewModel(
            contacts: nil, service: nil, readMarker: { .distantPast })
        model.newEvents = new
        model.earlierEvents = earlier
        return model
    }
}

#endif

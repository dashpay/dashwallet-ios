//
//  ContactsViewModel.swift
//  DashWallet
//
//  State for the contacts list: established contacts and incoming requests.
//

import Combine
import SwiftUI
import DashUIKit

// MARK: - ContactsViewModel

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [ContactItem] = []
    @Published var incomingRequests: [ContactItem] = []
    @Published var outgoingRequests: [ContactItem] = []

    /// Contact ids with an in-flight accept/ignore so their buttons
    /// disable instead of double-submitting.
    @Published var processingIds: Set<Data> = []
    @Published var errorMessage: String? = nil

    /// `nil` only in previews. The contacts service does real work in its
    /// initializer, so a canvas must not construct one.
    private let service: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    init(service: SwiftDashSDKContactsService? = .shared) {
        self.service = service
        self.search = AddContactViewModel(service: service)

        // One field drives both lists: the local filter reads `filterText`
        // directly, the network list needs it pushed into the search model,
        // which owns the debounce.
        $filterText
            .sink { [weak self] text in
                guard let self else { return }
                self.search.query = text
                self.search.scheduleSearch()
            }
            .store(in: &cancellables)
        // The search model is a separate observable; re-emit so one
        // `@StateObject` in the view covers both lists.
        search.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        guard let service else { return }
        // Republish the service snapshots. Direct assign is safe:
        // both objects are main-actor and the service publishes on main.
        service.$contacts.assign(to: &$contacts)
        service.$incomingRequests.assign(to: &$incomingRequests)
        service.$outgoingRequests.assign(to: &$outgoingRequests)
    }

    /// "My contacts" is a mutual friendship or a request waiting on us. A
    /// request *we* sent is not one yet — that person still belongs to the
    /// network list, where the search shows them as already requested.
    var isEmpty: Bool {
        contacts.isEmpty && incomingRequests.isEmpty
    }

    /// Whether the "my contacts" card has any row left after filtering.
    /// Distinct from ``isEmpty``: a wallet with contacts still shows nothing
    /// here when the search matches none of them. Hidden contacts don't
    /// count — they live in the network card.
    var hasVisibleContacts: Bool {
        !filteredIncoming.isEmpty || !filteredContacts.isEmpty
    }

    // MARK: - Search

    /// The DPNS search shown under the local list once the user types.
    /// Reuses the add-contact machinery — its debounce, per-row eligibility
    /// and send/accept handling — rather than repeating it here.
    let search: AddContactViewModel

    /// The list's search text. Lives here rather than in the view because the
    /// sections below are derived from it, and it also drives ``search``.
    @Published var filterText = ""

    /// The network list only exists while the user is searching; an empty
    /// field means "just my contacts".
    var showsNetworkResults: Bool {
        !filterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Filtering (local, over the already-materialized snapshots)

    var filteredContacts: [ContactItem] { contacts.filter { !$0.isHidden && matches($0) } }
    var filteredHidden: [ContactItem] { contacts.filter { $0.isHidden && matches($0) } }
    var filteredIncoming: [ContactItem] { incomingRequests.filter(matches) }
    // No `filteredOutgoing`: a request we sent is not one of our contacts.
    // Those identities surface in the network list instead, where the search
    // marks them `.alreadyRequested`.

    func entries(
        _ items: [ContactItem],
        section: ContactListEntry.Section
    ) -> [ContactListEntry] {
        items.map { ContactListEntry(item: $0, section: section) }
    }

    private func matches(_ item: ContactItem) -> Bool {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return item.displayTitle.localizedCaseInsensitiveContains(trimmed)
            || (item.username?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }

    func refresh() {
        service?.refresh()
    }

    func syncNow() async {
        await service?.syncNow()
    }

    func accept(_ item: ContactItem) {
        runAction(on: item) { service in
            try await service.acceptContactRequest(from: item.contactIdentityId)
        }
    }

    func ignore(_ item: ContactItem) {
        runAction(on: item) { service in
            try await service.ignoreSender(item.contactIdentityId)
        }
    }

    /// Lazy reverse-DPNS naming for rows that synced in with only an
    /// identity id (incoming requests from strangers).
    func resolveUsernameIfNeeded(_ item: ContactItem) {
        guard item.username == nil else { return }
        Task { _ = await service?.resolveUsername(for: item.contactIdentityId) }
    }

    private func runAction(
        on item: ContactItem,
        _ operation: @escaping (SwiftDashSDKContactsService) async throws -> Void
    ) {
        guard let service, !processingIds.contains(item.contactIdentityId) else { return }
        processingIds.insert(item.contactIdentityId)
        Task {
            defer { processingIds.remove(item.contactIdentityId) }
            do {
                try await operation(service)
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt — not an error state.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG

extension ContactsViewModel {
    /// Preview seed: fixed rows, no contacts service behind them.
    static func preview(
        contacts: [ContactItem] = [],
        incoming: [ContactItem] = [],
        outgoing: [ContactItem] = [],
        filterText: String = ""
    ) -> ContactsViewModel {
        let model = ContactsViewModel(service: nil)
        model.contacts = contacts
        model.incomingRequests = incoming
        model.outgoingRequests = outgoing
        model.filterText = filterText
        return model
    }
}

#endif

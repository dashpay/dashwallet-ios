//
//  AddContactViewModel.swift
//  DashWallet
//
//  Username search, per-row eligibility, and the send/accept actions
//  behind the add-contact screen.
//

import Combine
import SwiftDashSDK
import SwiftUI

@MainActor
final class AddContactViewModel: ObservableObject {

    /// How an existing relationship collides with a search hit, so the row
    /// and the preview sheet render the state-appropriate CTA from the same
    /// classification.
    enum Collision {
        case none
        case established
        case alreadyRequested
        case theyAskedUs
        case isSelf
        /// Identity lacks the DashPay-contract encryption/decryption
        /// keys a contact request needs (pre-DashPay identities).
        case missingDashPayKeys
        /// They asked us and we muted them. Their incoming row is gone, so
        /// this is the only thing standing between "someone whose request is
        /// still live on Platform" and "a stranger" — and the two need
        /// opposite actions: answer the existing request, not send a new one.
        case ignoredSender
    }

    // MARK: - Published state

    @Published var query = ""
    @Published private(set) var results: [DpnsSearchResult] = []
    @Published private(set) var isSearching = false
    /// Identity ids with an in-flight send/accept, so a row can't submit twice.
    @Published private(set) var sendingIds: Set<Data> = []
    /// identityId → can receive a contact request (has enabled DashPay
    /// ENCRYPTION + DECRYPTION keys). Absent = unknown (eligibility query
    /// unavailable) — the row stays actionable and the send path surfaces
    /// the real error.
    @Published private(set) var eligibilityById: [Data: Bool] = [:]
    /// Identity ids whose eligibility query is still running. A row in this
    /// set renders no action at all: showing "Request" first and replacing it
    /// with "Can't receive contact requests" a moment later told the user the
    /// opposite of the truth in between.
    @Published private(set) var eligibilityPending: Set<Data> = []
    @Published var errorMessage: String? = nil
    @Published private(set) var sentToast = false

    // MARK: - Dependencies

    /// `nil` only in previews. Building the contacts service is not free —
    /// its initializer does real work — so a canvas must not reach it.
    private let service: SwiftDashSDKContactsService?
    private var cancellables: Set<AnyCancellable> = []

    /// Snapshots mirrored from the service so ``collision(for:)`` is a pure
    /// read and the view re-renders when the relationship changes.
    private var contacts: [ContactItem] = []
    private var incomingRequests: [ContactItem] = []
    private var outgoingRequests: [ContactItem] = []
    private var ignoredSenderIds: Set<Data> = []

    /// identityIds with an in-flight eligibility query, so a row that
    /// re-appears doesn't fire a second one.
    private var eligibilityInFlight: Set<Data> = []
    private var searchTask: Task<Void, Never>? = nil

    init(service: SwiftDashSDKContactsService? = .shared) {
        self.service = service
        guard let service else { return }
        service.$contacts.sink { [weak self] in self?.contacts = $0; self?.objectWillChange.send() }
            .store(in: &cancellables)
        service.$incomingRequests.sink { [weak self] in self?.incomingRequests = $0; self?.objectWillChange.send() }
            .store(in: &cancellables)
        service.$outgoingRequests.sink { [weak self] in self?.outgoingRequests = $0; self?.objectWillChange.send() }
            .store(in: &cancellables)
        service.$ignoredSenderIds.sink { [weak self] in self?.ignoredSenderIds = $0; self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Reads

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    func contactItem(for identityId: Data) -> ContactItem? {
        service?.contactItem(for: identityId)
    }

    func collision(for result: DpnsSearchResult) -> Collision {
        if let ownId = DWCurrentUserIdentityInfo.shared.identityId,
           ownId == result.identityId {
            return .isSelf
        }
        if contacts.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .established
        }
        if outgoingRequests.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .alreadyRequested
        }
        if incomingRequests.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .theyAskedUs
        }
        // Checked before eligibility: a muted sender's own keys are beside
        // the point, and this must not fall through to `.none`.
        if ignoredSenderIds.contains(result.identityId) {
            return .ignoredSender
        }
        if eligibilityById[result.identityId] == false {
            return .missingDashPayKeys
        }
        return .none
    }

    // MARK: - Search

    func scheduleSearch() {
        searchTask?.cancel()
        let prefix = trimmedQuery
        guard prefix.count >= 1, let service else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            // Debounce keystrokes; canceled by the next query change.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                // limit 0 → the SDK's default cap (100), matching the legacy
                // global search's page size. Eligibility is resolved lazily
                // per visible row so a large result set doesn't fan out a key
                // query for every hit.
                let found = try await service.searchUsernames(prefix: prefix)
                guard !Task.isCancelled else { return }
                results = found
                resolveEligibility(for: found)
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Resolve which results can receive a contact request (DIP-15 needs the
    /// recipient's DashPay encryption + decryption keys), so the user sees
    /// "Can't receive contact requests" instead of hitting the PIN gate and a
    /// network error.
    ///
    /// Asked for the whole page in one call as soon as the search lands, not
    /// per row on `.onAppear`: a row-by-row trigger issued one query per hit,
    /// each answering at its own time, so the list kept rearranging itself
    /// under the user after it had already been drawn.
    private func resolveEligibility(for results: [DpnsSearchResult]) {
        let ids = results
            .map(\.identityId)
            .filter { eligibilityById[$0] == nil && !eligibilityInFlight.contains($0) }
        guard let service, !ids.isEmpty else { return }

        eligibilityInFlight.formUnion(ids)
        eligibilityPending.formUnion(ids)
        Task {
            defer {
                eligibilityInFlight.subtract(ids)
                // Only this batch's ids: a newer search may already have
                // marked others pending.
                eligibilityPending.subtract(ids)
            }
            let checked = await service.contactRequestEligibility(for: ids)
            eligibilityById.merge(checked) { _, new in new }
        }
    }

    // MARK: - Actions

    func send(to target: DpnsSearchResult) {
        guard let service, eligibilityById[target.identityId] != false else { return }
        run(on: target.identityId) {
            try await service.sendContactRequest(
                to: target.identityId,
                usernameHint: target.fullName)
            withAnimation { self.sentToast = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { self.sentToast = false }
        }
    }

    func accept(_ target: DpnsSearchResult) {
        guard let service else { return }
        let wasIgnored = ignoredSenderIds.contains(target.identityId)
        run(on: target.identityId) {
            if wasIgnored {
                try await service.acceptFromIgnoredSender(target.identityId)
            } else {
                try await service.acceptContactRequest(from: target.identityId)
            }
        }
    }

    /// Decline a request this identity sent us. Reachable from the sheet a
    /// search hit opens, which shows the incoming-request card for
    /// ``Collision/theyAskedUs``.
    func ignore(_ target: DpnsSearchResult) {
        guard let service else { return }
        run(on: target.identityId) {
            try await service.ignoreSender(target.identityId)
        }
    }

    private func run(on identityId: Data, _ operation: @escaping () async throws -> Void) {
        guard !sendingIds.contains(identityId) else { return }
        sendingIds.insert(identityId)
        Task {
            defer { sendingIds.remove(identityId) }
            do {
                try await operation()
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt — not an error state.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG

extension AddContactViewModel {
    /// Preview seed: fixed results, no contacts service behind them.
    static func preview(
        query: String = "",
        results: [DpnsSearchResult] = [],
        isSearching: Bool = false
    ) -> AddContactViewModel {
        let model = AddContactViewModel(service: nil)
        model.query = query
        model.results = results
        model.isSearching = isSearching
        return model
    }
}

#endif

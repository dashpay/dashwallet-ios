//
//  AddContactScreen.swift
//  DashWallet
//
//  Search for a Dash username and preview the result before sending a contact request.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

struct AddContactScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [DpnsSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var sendingIds: Set<Data> = []
    /// identityId → can receive a contact request (has enabled
    /// DashPay ENCRYPTION + DECRYPTION keys). Absent = unknown
    /// (eligibility query unavailable) — row stays actionable and the
    /// send path surfaces the real error.
    @State private var eligibilityById: [Data: Bool] = [:]
    /// identityIds with an in-flight eligibility query — set while the
    /// lazy per-row check runs so a row doesn't fire it twice.
    @State private var eligibilityInFlight: Set<Data> = []
    /// Tapped result shown in the preview sheet (the single
    /// send/accept confirmation surface).
    @State private var previewTarget: DpnsSearchResult? = nil
    @State private var errorMessage: String? = nil
    @State private var sentToast = false

    @ObservedObject private var service = SwiftDashSDKContactsService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ContactsSearchField(
                        placeholder: NSLocalizedString("Search by username", comment: "DashPay Contacts"),
                        text: $query,
                        height: 52)
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                    resultsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                        .foregroundColor(.dash.blue)
                }
            }
            .onChange(of: query) { _, _ in
                scheduleSearch()
            }
            .alert(
                NSLocalizedString("Error", comment: ""),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } })
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $previewTarget) { target in
                AddContactPreviewSheet(
                    result: target,
                    collision: collision(for: target),
                    contact: service.contactItem(for: target.identityId),
                    onSend: { send(to: target) },
                    onAccept: { accept(target) })
            }
            .overlay(alignment: .bottom) {
                if sentToast {
                    Text(NSLocalizedString("Contact request sent", comment: "DashPay Contacts"))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    /// Android search screen header: icon, headline, subtitle.
    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(.dash.blue)
                .padding(.bottom, 14)
            Text(NSLocalizedString("Add a New Contact", comment: "DashPay Contacts"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(NSLocalizedString("Find a User", comment: "DashPay Contacts"))
                .font(.system(size: 16))
                .foregroundColor(.dash.secondaryText)
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if isSearching {
                    SwiftUI.ProgressView()
                        .padding(.top, 32)
                } else if results.isEmpty && trimmedQuery.count >= 2 {
                    Text(NSLocalizedString("No usernames found", comment: "DashPay Contacts"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                        .padding(.top, 32)
                } else if trimmedQuery.count < 2 && !trimmedQuery.isEmpty {
                    Text(NSLocalizedString("Type at least 2 characters to search usernames", comment: "DashPay Contacts"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                        .padding(.top, 32)
                }
                ForEach(results) { result in
                    resultRow(result)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.secondaryBackground))
                        .contentShape(Rectangle())
                        .onTapGesture { previewTarget = result }
                        .onAppear { checkEligibilityIfNeeded(result) }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
        }
    }

    // MARK: Rows

    /// Non-private so `AddContactPreviewSheet` can render the
    /// state-appropriate CTA from the same classification.
    enum Collision {
        case none
        case established
        case alreadyRequested
        case theyAskedUs
        case isSelf
        /// Identity lacks the DashPay-contract encryption/decryption
        /// keys a contact request needs (pre-DashPay identities).
        case missingDashPayKeys
    }

    private func collision(for result: DpnsSearchResult) -> Collision {
        if let ownId = DWCurrentUserIdentityInfo.shared.identityId,
           ownId == result.identityId {
            return .isSelf
        }
        if service.contacts.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .established
        }
        if service.outgoingRequests.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .alreadyRequested
        }
        if service.incomingRequests.contains(where: { $0.contactIdentityId == result.identityId }) {
            return .theyAskedUs
        }
        if eligibilityById[result.identityId] == false {
            return .missingDashPayKeys
        }
        return .none
    }

    @ViewBuilder
    private func resultRow(_ result: DpnsSearchResult) -> some View {
        let state = collision(for: result)
        HStack(spacing: 10) {
            ContactAvatarView(
                title: result.fullName,
                avatarURL: nil,
                identitySeed: result.identityId)
                .padding(.leading, 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.fullName.withoutDashSuffix)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if let hint = collisionText(state) {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundColor(state == .alreadyRequested ? .dashGolden : .dash.tertiaryText)
                }
            }
            Spacer()
            trailingControl(result, state: state)
                .padding(.trailing, 12)
        }
        .frame(height: 70)
    }

    private func collisionText(_ state: Collision) -> String? {
        switch state {
        case .none: return nil
        case .established: return NSLocalizedString("Already a contact", comment: "DashPay Contacts")
        case .alreadyRequested: return NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts")
        case .theyAskedUs: return NSLocalizedString("Sent you a request", comment: "DashPay Contacts")
        case .isSelf: return NSLocalizedString("This is you", comment: "DashPay Contacts")
        case .missingDashPayKeys: return NSLocalizedString("Can't receive contact requests", comment: "DashPay Contacts")
        }
    }

    @ViewBuilder
    private func trailingControl(_ result: DpnsSearchResult, state: Collision) -> some View {
        if sendingIds.contains(result.identityId) {
            SwiftUI.ProgressView()
        } else {
            switch state {
            case .none:
                Button {
                    previewTarget = result
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.dash.blue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.blue.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Send Contact Request", comment: "DashPay Contacts"))
            case .theyAskedUs:
                AcceptPillButton { accept(result) }
            case .established:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.dashGreen)
            case .alreadyRequested:
                Image(systemName: "hourglass")
                    .foregroundColor(.dashGolden)
            case .isSelf:
                EmptyView()
            case .missingDashPayKeys:
                Image(systemName: "lock.slash")
                    .foregroundColor(.dash.tertiaryText)
            }
        }
    }

    // MARK: Search

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let prefix = trimmedQuery
        guard prefix.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            // Debounce keystrokes; canceled by the next onChange.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                // limit 0 → the SDK's default cap (100), matching the
                // legacy global search's page size. Eligibility is
                // resolved lazily per visible row (below) so a large
                // result set doesn't fan out a key query for every hit.
                let found = try await service.searchUsernames(prefix: prefix)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Resolve whether one result can receive a contact request (DIP-15
    /// needs the recipient's DashPay encryption + decryption keys), the
    /// first time its row scrolls into view. Marks pre-DashPay
    /// identities so the user sees "Can't receive contact requests"
    /// instead of hitting the PIN gate and a network error. One query
    /// per identity, deduped via `eligibilityInFlight`.
    private func checkEligibilityIfNeeded(_ result: DpnsSearchResult) {
        let id = result.identityId
        guard eligibilityById[id] == nil, !eligibilityInFlight.contains(id) else { return }
        eligibilityInFlight.insert(id)
        Task {
            defer { eligibilityInFlight.remove(id) }
            let checked = await service.contactRequestEligibility(for: [id])
            eligibilityById.merge(checked) { _, new in new }
        }
    }

    // MARK: Actions

    private func send(to target: DpnsSearchResult) {
        guard eligibilityById[target.identityId] != false else { return }
        guard !sendingIds.contains(target.identityId) else { return }
        sendingIds.insert(target.identityId)
        Task {
            defer { sendingIds.remove(target.identityId) }
            do {
                try await service.sendContactRequest(
                    to: target.identityId,
                    usernameHint: target.fullName)
                withAnimation { sentToast = true }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation { sentToast = false }
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func accept(_ target: DpnsSearchResult) {
        guard !sendingIds.contains(target.identityId) else { return }
        sendingIds.insert(target.identityId)
        Task {
            defer { sendingIds.remove(target.identityId) }
            do {
                try await service.acceptContactRequest(from: target.identityId)
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - AddContactPreviewSheet

/// Preview shown when a search result is tapped — the SDK-side stand-in
/// for the legacy `DWUserProfileViewController` a user reached before
/// sending a request. It confirms who you're adding (avatar, name,
/// username, and — when we already hold it — the contact's profile
/// message) and carries the single send/accept CTA.
///
/// Honest limitation: the SDK exposes no on-chain profile fetch for an
/// arbitrary identity (`getDashPayProfile`/`getContactProfile` read the
/// local cache only), so for a true stranger this shows the DPNS
/// username + placeholder avatar, not a fetched bio. Real profile
/// fields appear once the identity is one of our contacts/requesters
/// (`contact` non-nil). Nothing is fabricated when the data is absent.

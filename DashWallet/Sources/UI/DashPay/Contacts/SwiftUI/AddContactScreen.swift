//
//  AddContactScreen.swift
//  DashWallet
//
//  Add-contact flow (migration Row #18 phase 3): debounced DPNS
//  prefix search via `searchDpnsNames`, collision detection against
//  the local snapshots, DashPay-key eligibility marking, and the
//  PIN-gated send. Visual design mirrors the Android dash-wallet
//  "Add New Contact" screen (activity_search_dashpay_profile_1.xml):
//  centered icon + "Add a New Contact" headline + "Find a User"
//  subtitle, elevated rounded white search field, white card result
//  rows on the gray background.
//

import SwiftDashSDK
import SwiftUI

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
    @State private var confirmTarget: DpnsSearchResult? = nil
    @State private var errorMessage: String? = nil
    @State private var sentToast = false

    private let service = SwiftDashSDKContactsService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
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
                        .foregroundColor(.dashBlue)
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
            .alert(item: $confirmTarget) { target in
                Alert(
                    title: Text(NSLocalizedString("Send Contact Request", comment: "DashPay Contacts")),
                    message: Text(String(
                        format: NSLocalizedString("Send a contact request to %@?", comment: "DashPay Contacts"),
                        target.fullName.withoutDashSuffix)),
                    primaryButton: .default(Text(NSLocalizedString("Send", comment: "DashPay Contacts"))) {
                        send(to: target)
                    },
                    secondaryButton: .cancel())
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
                .foregroundColor(.dashBlue)
                .padding(.bottom, 14)
            Text(NSLocalizedString("Add a New Contact", comment: "DashPay Contacts"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primaryText)
            Text(NSLocalizedString("Find a User", comment: "DashPay Contacts"))
                .font(.system(size: 16))
                .foregroundColor(.secondaryText)
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
                        .foregroundColor(.secondaryText)
                        .padding(.top, 32)
                } else if trimmedQuery.count < 2 && !trimmedQuery.isEmpty {
                    Text(NSLocalizedString("Type at least 2 characters to search usernames", comment: "DashPay Contacts"))
                        .font(.system(size: 14))
                        .foregroundColor(.secondaryText)
                        .padding(.top, 32)
                }
                ForEach(results) { result in
                    resultRow(result)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondaryBackground))
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
        }
    }

    // MARK: Rows

    private enum Collision {
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
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if let hint = collisionText(state) {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundColor(state == .alreadyRequested ? .dashGolden : .tertiaryText)
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
                    confirmTarget = result
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.dashBlue)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dashBlue.opacity(0.1)))
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
                    .foregroundColor(.tertiaryText)
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
                let found = try await service.searchUsernames(prefix: prefix, limit: 10)
                guard !Task.isCancelled else { return }
                results = found
                // Check who can actually receive a request (DIP-15
                // needs the recipient's DashPay encryption +
                // decryption keys) so pre-DashPay identities are
                // marked instead of failing after the PIN gate.
                let unknownIds = found.map(\.identityId).filter { eligibilityById[$0] == nil }
                if !unknownIds.isEmpty {
                    let checked = await service.contactRequestEligibility(for: unknownIds)
                    guard !Task.isCancelled else { return }
                    eligibilityById.merge(checked) { _, new in new }
                }
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = error.localizedDescription
            }
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

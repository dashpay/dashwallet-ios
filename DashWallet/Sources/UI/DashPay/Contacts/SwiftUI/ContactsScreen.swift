//
//  ContactsScreen.swift
//  DashWallet
//
//  SwiftUI contacts home (migration Row #18 phase 2) — replaces the
//  DashSync-era `DWContactsViewController` + FRC data-source stack.
//  Visual design mirrors the Android dash-wallet contacts screen
//  (contacts_list_layout.xml / dashpay_contact_row.xml): #f7f7f7
//  screen background, white 8pt-radius card rows (70pt) with 3pt
//  gaps, rounded white search field, "Contact Requests (n)" /
//  "My Contacts" section headers, light-blue Accept pill + round
//  ignore on incoming rows, golden "Contact Request Pending" on
//  outgoing rows.
//

import SwiftUI

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

    private let service = SwiftDashSDKContactsService.shared

    init() {
        // Republish the service snapshots. Direct assign is safe:
        // both objects are main-actor and the service publishes on main.
        service.$contacts.assign(to: &$contacts)
        service.$incomingRequests.assign(to: &$incomingRequests)
        service.$outgoingRequests.assign(to: &$outgoingRequests)
    }

    var isEmpty: Bool {
        contacts.isEmpty && incomingRequests.isEmpty && outgoingRequests.isEmpty
    }

    func refresh() {
        service.refresh()
    }

    func syncNow() async {
        await service.syncNow()
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
        Task { _ = await service.resolveUsername(for: item.contactIdentityId) }
    }

    private func runAction(
        on item: ContactItem,
        _ operation: @escaping (SwiftDashSDKContactsService) async throws -> Void
    ) {
        guard !processingIds.contains(item.contactIdentityId) else { return }
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

// MARK: - ContactsScreen

struct ContactsScreen: View {
    @StateObject private var viewModel = ContactsViewModel()
    @State private var filterText = ""
    @State private var showingAddContact = false
    @State private var selectedContact: ContactItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(NSLocalizedString("Contacts", comment: "DashPay Contacts"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddContact = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.dashBlue)
                    }
                    .accessibilityLabel(NSLocalizedString("Add a New Contact", comment: "DashPay Contacts"))
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactScreen()
            }
            .sheet(item: $selectedContact) { contact in
                ContactProfileSheet(contact: contact)
            }
            .alert(
                NSLocalizedString("Error", comment: ""),
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } })
            ) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear { viewModel.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ContactsSearchField(
                    placeholder: NSLocalizedString("Search Contacts", comment: "DashPay Contacts"),
                    text: $filterText)
                    .padding(.horizontal, 15)
                    .padding(.top, 12)

                if !filteredIncoming.isEmpty {
                    sectionHeader(
                        String(
                            format: NSLocalizedString("Contact Requests (%d)", comment: "DashPay Contacts"),
                            filteredIncoming.count),
                        size: 15)
                    ForEach(filteredIncoming) { item in
                        cardRow {
                            IncomingRequestRow(
                                item: item,
                                isProcessing: viewModel.processingIds.contains(item.contactIdentityId),
                                onAccept: { viewModel.accept(item) },
                                onIgnore: { viewModel.ignore(item) })
                        }
                        .onTapGesture { selectedContact = item }
                        .onAppear { viewModel.resolveUsernameIfNeeded(item) }
                    }
                }

                if !filteredContacts.isEmpty {
                    sectionHeader(NSLocalizedString("My Contacts", comment: "DashPay Contacts"), size: 17)
                    ForEach(filteredContacts) { item in
                        cardRow {
                            ContactRow(item: item)
                        }
                        .onTapGesture { selectedContact = item }
                    }
                }

                if !filteredOutgoing.isEmpty {
                    sectionHeader(NSLocalizedString("Pending Requests", comment: "DashPay Contacts"), size: 15)
                    ForEach(filteredOutgoing) { item in
                        cardRow {
                            ContactRow(item: item, showPendingBadge: true)
                        }
                        .onTapGesture { selectedContact = item }
                        .onAppear { viewModel.resolveUsernameIfNeeded(item) }
                    }
                }

                if !filteredHidden.isEmpty {
                    sectionHeader(NSLocalizedString("Hidden", comment: "DashPay Contacts"), size: 15)
                    ForEach(filteredHidden) { item in
                        cardRow {
                            ContactRow(item: item)
                        }
                        .opacity(0.55)
                        .onTapGesture { selectedContact = item }
                    }
                }

                Spacer(minLength: 24)
            }
        }
        .refreshable { await viewModel.syncNow() }
    }

    private func sectionHeader(_ text: String, size: CGFloat) -> some View {
        HStack {
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.primaryText)
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func cardRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondaryBackground))
            .padding(.horizontal, 15)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
    }

    /// Android contacts_empty_state_layout: centered add-contact icon,
    /// "Add a New Contact" headline, "Find a User" body, blue CTA.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 72, weight: .light))
                .foregroundColor(.dashBlue)
                .padding(.bottom, 12)
            Text(NSLocalizedString("Add a New Contact", comment: "DashPay Contacts"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primaryText)
            Text(NSLocalizedString("Find a user and add them to your contacts.", comment: "DashPay Contacts"))
                .font(.system(size: 16))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingAddContact = true
            } label: {
                Label(
                    NSLocalizedString("Search for a User", comment: "DashPay Contacts"),
                    systemImage: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.dashBlue))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 18)
            Spacer()
            Spacer()
        }
    }

    // MARK: Filtering (local, over the already-materialized snapshots)

    private func matches(_ item: ContactItem) -> Bool {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return item.displayTitle.localizedCaseInsensitiveContains(trimmed)
            || (item.username?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }

    private var filteredContacts: [ContactItem] { viewModel.contacts.filter { !$0.isHidden && matches($0) } }
    private var filteredHidden: [ContactItem] { viewModel.contacts.filter { $0.isHidden && matches($0) } }
    private var filteredIncoming: [ContactItem] { viewModel.incomingRequests.filter(matches) }
    private var filteredOutgoing: [ContactItem] { viewModel.outgoingRequests.filter(matches) }
}

// MARK: - Rows (Android dashpay_contact_row: 70pt, avatar 36, name 17sb)

struct ContactRow: View {
    let item: ContactItem
    var showPendingBadge: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ContactAvatarView(
                title: item.displayTitle,
                avatarURL: item.avatarURL,
                identitySeed: item.contactIdentityId)
                .padding(.leading, 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if let secondary = secondaryLine {
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundColor(.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if showPendingBadge {
                Text(NSLocalizedString("Contact Request Pending", comment: "DashPay Contacts"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.dashGolden)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 70)
    }

    /// Show the username as the second line when the first line is the
    /// profile display name or alias (both known and different).
    private var secondaryLine: String? {
        guard let username = item.username?.withoutDashSuffix,
              !username.isEmpty,
              username != item.displayTitle else { return nil }
        return username
    }
}

struct IncomingRequestRow: View {
    let item: ContactItem
    let isProcessing: Bool
    let onAccept: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ContactAvatarView(
                title: item.displayTitle,
                avatarURL: item.avatarURL,
                identitySeed: item.contactIdentityId)
                .padding(.leading, 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if let username = item.username?.withoutDashSuffix, !username.isEmpty, username != item.displayTitle {
                    Text(username)
                        .font(.system(size: 12))
                        .foregroundColor(.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isProcessing {
                // Android shows an hourglass + golden "Accepting".
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12))
                    Text(NSLocalizedString("Accepting", comment: "DashPay Contacts"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.dashGolden)
                .padding(.trailing, 12)
            } else {
                AcceptPillButton(action: onAccept)
                IgnoreCircleButton(action: onIgnore)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 70)
    }
}

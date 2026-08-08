//
//  ContactsScreen.swift
//  DashWallet
//
//  The contacts list: search, established contacts, incoming requests.
//

import SwiftUI
import DashUIKit

struct ContactsScreen: View {
    @StateObject private var viewModel = ContactsViewModel()
    @State private var filterText = ""
    @State private var showingAddContact = false
    @State private var selectedContact: ContactItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(NSLocalizedString("Contacts", comment: "DashPay Contacts"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddContact = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.dash.blue)
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
                    ForEach(entries(filteredIncoming, section: .incoming)) { entry in
                        let item = entry.item
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
                    ForEach(entries(filteredContacts, section: .established)) { entry in
                        let item = entry.item
                        cardRow {
                            ContactRow(item: item)
                        }
                        .onTapGesture { selectedContact = item }
                    }
                }

                if !filteredOutgoing.isEmpty {
                    sectionHeader(NSLocalizedString("Pending Requests", comment: "DashPay Contacts"), size: 15)
                    ForEach(entries(filteredOutgoing, section: .outgoing)) { entry in
                        let item = entry.item
                        cardRow {
                            ContactRow(item: item, showPendingBadge: true)
                        }
                        .onTapGesture { selectedContact = item }
                        .onAppear { viewModel.resolveUsernameIfNeeded(item) }
                    }
                }

                if !filteredHidden.isEmpty {
                    sectionHeader(NSLocalizedString("Hidden", comment: "DashPay Contacts"), size: 15)
                    ForEach(entries(filteredHidden, section: .hidden)) { entry in
                        let item = entry.item
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
                .foregroundColor(.dash.primaryText)
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
                    .fill(Color.dash.secondaryBackground))
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
                .foregroundColor(.dash.blue)
                .padding(.bottom, 12)
            Text(NSLocalizedString("Add a New Contact", comment: "DashPay Contacts"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
            Text(NSLocalizedString("Find a user and add them to your contacts.", comment: "DashPay Contacts"))
                .font(.system(size: 16))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingAddContact = true
            } label: {
                Label(
                    NSLocalizedString("Search for a User", comment: "DashPay Contacts"),
                    systemImage: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.dash.blue))
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

    private func entries(
        _ items: [ContactItem],
        section: ContactListEntry.Section
    ) -> [ContactListEntry] {
        items.map { ContactListEntry(item: $0, section: section) }
    }
}

// MARK: - Rows (Android dashpay_contact_row: 70pt, avatar 36, name 17sb)

//
//  ContactsScreen.swift
//  DashWallet
//
//  The contacts list: search, established contacts, incoming requests.
//

import SwiftDashSDK
import SwiftUI
import DashUIKit

struct ContactsScreen: View {
    @StateObject private var viewModel: ContactsViewModel
        @State private var showingAddContact = false
    @State private var selectedContact: ContactItem? = nil
    /// A network hit tapped for the send confirmation.
    @State private var previewTarget: DpnsSearchResult? = nil

    /// Default `nil` rather than a fresh view model: default arguments are
    /// evaluated off the main actor and `ContactsViewModel` is `@MainActor`.
    /// `StateObject`'s autoclosure defers construction to view installation.
    /// Previews pass one in.
    init(viewModel: ContactsViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ContactsViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                content
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactScreen()
            }
            .sheet(item: $selectedContact) { contact in
                ContactProfileSheet(contact: contact)
            }
            .sheet(item: $previewTarget) { target in
                ContactSheet(
                    result: target,
                    collision: viewModel.search.collision(for: target),
                    contact: viewModel.search.contactItem(for: target.identityId),
                    isSending: viewModel.search.sendingIds.contains(target.identityId),
                    onSendRequest: { viewModel.search.send(to: target) },
                    onAccept: { viewModel.search.accept(target) },
                    onIgnore: { viewModel.search.ignore(target) })
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
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(central: {
                Text(NSLocalizedString("Contacts", comment: "DashPay Contacts"))
                    .dashFont(.subheadMedium)
                    .foregroundColor(.dash.primaryText)
            }) {
                NavigationBarElement.plus.button {
                    showingAddContact = true
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                DashUIKit.SearchBar(
                    text: $viewModel.filterText,
                    placeholder: NSLocalizedString("Search", comment: "DashPay Contacts")
                )
                .padding(.horizontal, 20)

                list
                    .padding(.horizontal, 20)
            }
        }
    }

    private var list: some View {
        ScrollView {
            myContacts

            if viewModel.showsNetworkResults {
                networkResults
            }
        }
        .refreshable { await viewModel.syncNow() }
    }

    /// Mutual contacts and the requests waiting on us — everything that is
    /// already "mine".
    private var myContacts: some View {
        LazyVStack(spacing: 2) {
            if viewModel.hasVisibleContacts {
                ForEach(viewModel.entries(viewModel.filteredIncoming, section: .incoming)) { entry in
                    let item = entry.item

                    ContactRow(
                        item: item,
                        isProcessing: viewModel.processingIds.contains(item.contactIdentityId),
                        onAccept: { viewModel.accept(item) },
                        onIgnore: { viewModel.ignore(item) }
                    )
                    .onTapGesture { selectedContact = item }
                    .onAppear { viewModel.resolveUsernameIfNeeded(item) }
                }

                ForEach(viewModel.entries(viewModel.filteredContacts, section: .established)) { entry in
                    let item = entry.item

                    ContactRow(item: item)
                        .onTapGesture { selectedContact = item }
                }
            } else {
                emptyStateView(NSLocalizedString("No contacts found.", comment: "DashPay Contacts"))
            }
        }
        .modifier(DashUIKit.MenuViewModifier())
    }

    /// Everyone else: the network search, and the contacts we have hidden —
    /// both are "not in my list", so they share a card. Shown only while the
    /// field has text; an empty search means "just my contacts".
    @ViewBuilder
    private var networkResults: some View {
        let search = viewModel.search

        VStack(alignment: .leading, spacing: 2) {
            Text(NSLocalizedString("Users on the Dash network", comment: "DashPay Contacts"))
                .dashFont(.footnoteMedium)
                .foregroundStyle(Color.dash.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)

            if search.isSearching {
                SwiftUI.ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if search.results.isEmpty && viewModel.filteredHidden.isEmpty {
                emptyStateView(NSLocalizedString("No users found", comment: "DashPay Contacts"))
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(search.results) { result in
                        // The button acts; the row opens the profile. Two
                        // targets in one row, so the tap gesture is on the
                        // row and the button swallows its own hit.
                        ContactRow(
                            result: result,
                            state: search.collision(for: result),
                            isSending: search.sendingIds.contains(result.identityId),
                            onRequest: { search.send(to: result) },
                            onAccept: { search.accept(result) })
                            .contentShape(Rectangle())
                            .onTapGesture { previewTarget = result }
                            .onAppear { search.checkEligibilityIfNeeded(result) }
                    }

                    // Hidden contacts sit at the end: still ours, but taken
                    // out of the list on purpose.
                    ForEach(viewModel.entries(viewModel.filteredHidden, section: .hidden)) { entry in
                        let item = entry.item

                        ContactRow(item: item)
                            .opacity(0.55)
                            .onTapGesture { selectedContact = item }
                    }
                }
            }
        }
        .modifier(DashUIKit.MenuViewModifier())
    }

    /// Placeholder for a card that has no rows. Deliberately carries no
    /// `MenuViewModifier` of its own — it is placed *inside* the card the
    /// rows would have filled, so the caller owns the background.
    private func emptyStateView(_ message: String) -> some View {
        Text(message)
            .dashFont(.footnote)
            .foregroundColor(Color.dash.gray500)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 100)
    }
}

#if DEBUG

/// Seeded rows, no contacts service behind them — see
/// `ContactsViewModel.preview(contacts:incoming:outgoing:)`.
#Preview("With contacts") {
    ContactsScreen(viewModel: .preview(
        contacts: [
            .preview(title: "briantest63a"),
            .preview(title: "s22test63b"),
            .preview(title: "Upsilon2"),
        ],
        incoming: [.preview(title: "Delta", relationship: .incoming)],
        outgoing: [.preview(title: "Epsilon2", relationship: .outgoing)]))
}

#Preview("Empty") {
    ContactsScreen(viewModel: .preview())
}

#endif

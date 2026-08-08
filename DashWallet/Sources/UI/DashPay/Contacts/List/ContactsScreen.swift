//
//  ContactsScreen.swift
//  DashWallet
//
//  The contacts list: search, established contacts, incoming requests.
//

import SwiftUI
import DashUIKit

struct ContactsScreen: View {
    @StateObject private var viewModel: ContactsViewModel
        @State private var showingAddContact = false
    @State private var selectedContact: ContactItem? = nil

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

                Group {
                    if viewModel.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
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

                ForEach(viewModel.entries(viewModel.filteredOutgoing, section: .outgoing)) { entry in
                    let item = entry.item

                    ContactRow(item: item)
                        .onTapGesture { selectedContact = item }
                        .onAppear { viewModel.resolveUsernameIfNeeded(item) }
                }

                ForEach(viewModel.entries(viewModel.filteredHidden, section: .hidden)) { entry in
                    let item = entry.item

                    ContactRow(item: item)
                        .opacity(0.55)
                        .onTapGesture { selectedContact = item }
                }
            }
            .modifier(DashUIKit.MenuViewModifier())
        }
        .refreshable { await viewModel.syncNow() }
    }

    /// Android contacts_empty_state_layout: centered add-contact icon,
    /// "Add a New Contact" headline, "Find a User" body, blue CTA.
    private var emptyState: some View {

        VStack(alignment: .center, spacing: 0) {
            Spacer()

            Text(NSLocalizedString("Search for users on the Dash Network", comment: "DashPay Contacts"))
                .dashFont(.subhead)
                .foregroundStyle(Color.dash.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer()
        }
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

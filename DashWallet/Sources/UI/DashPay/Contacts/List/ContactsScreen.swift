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
    /// The person whose sheet is up, from whichever list they were tapped in.
    @State private var sheetTarget: ContactTarget? = nil
    @State private var showScanner = false

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
            .sheet(item: $sheetTarget) { target in
                ContactSheetPresenter(target: target, viewModel: viewModel)
            }
            .sheet(isPresented: $showScanner) {
                GenericQRScannerView(
                    onQRCodeScanned: { value in
                        showScanner = false
                        // Verified against Platform before it is shown as
                        // anyone — the code itself proves nothing.
                        viewModel.search.verifyScannedCode(value) { user in
                            sheetTarget = .scanned(user)
                        }
                    },
                    onCancel: { showScanner = false })
            }
            .overlay {
                if viewModel.search.isVerifyingScan {
                    VStack(spacing: 12) {
                        SwiftUI.ProgressView()
                        Text(NSLocalizedString("Verifying user…", comment: "DashPay Contacts"))
                            .dashFont(.footnote)
                            .foregroundStyle(Color.dash.secondaryText)
                    }
                    .padding(24)
                    .background(Color.dash.secondaryBackground)
                    .clipShape(.rect(cornerRadius: 16))
                }
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
            // `central:` spelled out: the bare trailing closure is ambiguous
            // between NavigationBar's leading-, central- and trailing-only
            // initializers, which are all single-closure.
            DashUIKit.NavigationBar(central: {
                Text(NSLocalizedString("Contacts", comment: "DashPay Contacts"))
                    .dashFont(.subheadMedium)
                    .foregroundColor(.dash.primaryText)
            }, trailing: {
                // Their code lives on their profile; the scanner lives where
                // contacts are added. An SF Symbol rather than a
                // `NavigationBarElement`, which has no QR icon.
                Button { showScanner = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.dash.primaryText)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .accessibilityLabel(NSLocalizedString("Scan a contact's QR code", comment: "DashPay Contacts"))
            })

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
    /// already "mine". Absent entirely when there are none: the card carries
    /// no message of its own, so an empty one would just be a blank block
    /// above the network results.
    @ViewBuilder
    private var myContacts: some View {
        if viewModel.hasVisibleContacts {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.entries(viewModel.filteredIncoming, section: .incoming)) { entry in
                    let item = entry.item

                    ContactRow(
                        item: item,
                        isProcessing: viewModel.processingIds.contains(item.contactIdentityId),
                        onAccept: { viewModel.accept(item) },
                        onIgnore: { viewModel.ignore(item) }
                    )
                    .onTapGesture { sheetTarget = .contact(item) }
                    .onAppear { viewModel.resolveUsernameIfNeeded(item) }
                }

                ForEach(viewModel.entries(viewModel.filteredContacts, section: .established)) { entry in
                    let item = entry.item

                    ContactRow(item: item)
                        .onTapGesture { sheetTarget = .contact(item) }
                }
            }
            .modifier(DashUIKit.MenuViewModifier())
        }
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
                            isCheckingEligibility: search.eligibilityPending.contains(result.identityId),
                            onRequest: { search.send(to: result) },
                            onAccept: { search.accept(result) })
                            .contentShape(Rectangle())
                            .onTapGesture { sheetTarget = .searchHit(result) }
                    }

                    // Hidden contacts sit at the end: still ours, but taken
                    // out of the list on purpose.
                    ForEach(viewModel.entries(viewModel.filteredHidden, section: .hidden)) { entry in
                        let item = entry.item

                        ContactRow(item: item)
                            .opacity(0.55)
                            .onTapGesture { sheetTarget = .contact(item) }
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

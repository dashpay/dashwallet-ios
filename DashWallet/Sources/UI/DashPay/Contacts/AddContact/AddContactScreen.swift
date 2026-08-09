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

    @StateObject private var viewModel: AddContactViewModel
    /// Tapped result shown in the preview sheet (the single send/accept
    /// confirmation surface). Presentation state, so it stays in the view.
    @State private var previewTarget: DpnsSearchResult? = nil

    /// Default `nil` rather than a fresh view model: default arguments are
    /// evaluated off the main actor, and `AddContactViewModel` is
    /// `@MainActor`. `StateObject`'s autoclosure defers construction to view
    /// installation. Previews pass one in.
    init(viewModel: AddContactViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? AddContactViewModel())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ContactsSearchField(
                        placeholder: NSLocalizedString("Search by username", comment: "DashPay Contacts"),
                        text: $viewModel.query,
                        height: 52
                    )
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
            .onChange(of: viewModel.query) { _, _ in
                viewModel.scheduleSearch()
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
            .sheet(item: $previewTarget) { target in
                AddContactPreviewSheet(
                    result: target,
                    collision: viewModel.collision(for: target),
                    contact: viewModel.contactItem(for: target.identityId),
                    isSending: viewModel.sendingIds.contains(target.identityId),
                    onSend: { viewModel.send(to: target) },
                    onAccept: { viewModel.accept(target) })
            }
            .overlay(alignment: .bottom) {
                if viewModel.sentToast {
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
                if viewModel.isSearching {
                    SwiftUI.ProgressView()
                        .padding(.top, 32)
                } else if viewModel.results.isEmpty && viewModel.trimmedQuery.count >= 2 {
                    Text(NSLocalizedString("No usernames found", comment: "DashPay Contacts"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                        .padding(.top, 32)
                } else if viewModel.trimmedQuery.count < 2 && !viewModel.trimmedQuery.isEmpty {
                    Text(NSLocalizedString("Type at least 2 characters to search usernames", comment: "DashPay Contacts"))
                        .font(.system(size: 14))
                        .foregroundColor(.dash.secondaryText)
                        .padding(.top, 32)
                }
                ForEach(viewModel.results) { result in
                    resultRow(result)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dash.secondaryBackground))
                        .contentShape(Rectangle())
                        .onTapGesture { previewTarget = result }
                        .onAppear { viewModel.checkEligibilityIfNeeded(result) }
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
        }
    }

    // MARK: Rows

    /// Non-private so `AddContactPreviewSheet` can render the
    @ViewBuilder
    private func resultRow(_ result: DpnsSearchResult) -> some View {
        ContactRow(
            result: result,
            state: viewModel.collision(for: result),
            isSending: viewModel.sendingIds.contains(result.identityId),
            onRequest: { previewTarget = result },
            onAccept: { viewModel.accept(result) })
    }

    // MARK: Search
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

#if DEBUG

/// Result rows can't be previewed: `DpnsSearchResult` is a `public struct`
/// in SwiftDashSDK with only the implicit memberwise initializer, which is
/// internal to that module — the app cannot build one. So these cover the
/// states that don't need results, which is also where the copy lives.
#Preview("Empty") {
    AddContactScreen(viewModel: .preview())
}

#Preview("Query too short") {
    AddContactScreen(viewModel: .preview(query: "b"))
}

#Preview("Searching") {
    AddContactScreen(viewModel: .preview(query: "brian", isSearching: true))
}

#endif

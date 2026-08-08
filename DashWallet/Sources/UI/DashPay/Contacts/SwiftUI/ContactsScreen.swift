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

    /// True while the main identity's persisted key set lacks the DIP-15
    /// ENCRYPTION/DECRYPTION pair — without it nobody can send this
    /// identity a contact request. Drives the "Enable DashPay" banner.
    @Published var needsDashPayEnable = false
    @Published var isEnablingDashPay = false

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
        needsDashPayEnable = service.mainIdentityNeedsDashPayKeys()
    }

    /// Estimated IdentityUpdate fee for the confirm sheet:
    /// "~0.0000131 DASH (≈ THB 0.01)" in the user's local currency.
    var enableDashPayEstimatedCostText: String {
        let duffs = SwiftDashSDKContactsService.enableDashPayEstimatedFeeDuffs
        return String.localizedStringWithFormat(
            NSLocalizedString("~%@ DASH (≈ %@)", comment: "DashPay: estimated network fee — DASH amount, then its local-currency equivalent"),
            duffs.formattedDashAmountWithoutCurrencySymbol,
            CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
    }

    /// PIN-gated IdentityUpdate adding the missing contact-request keys.
    /// On success the banner clears optimistically (Platform accepted the
    /// broadcast, or already had the keys).
    func enableDashPay() {
        guard !isEnablingDashPay else { return }
        isEnablingDashPay = true
        Task {
            defer { isEnablingDashPay = false }
            do {
                _ = try await service.enableDashPay()
                needsDashPayEnable = false
            } catch SwiftDashSDKContactsService.ServiceError.authCancelled {
                // User backed out of the PIN prompt — not an error state.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

/// SwiftUI otherwise reuses a contact row by `ContactItem.id` when the same
/// identity moves between incoming / established / outgoing sections. That
/// can preserve the old row type and its action closures (for example an
/// Accept button rendered inside the Pending section).
private struct ContactListEntry: Identifiable {
    enum Section: Hashable {
        case incoming
        case established
        case outgoing
        case hidden
    }

    struct ID: Hashable {
        let section: Section
        let contactIdentityId: Data
    }

    let item: ContactItem
    let id: ID

    init(item: ContactItem, section: Section) {
        self.item = item
        id = ID(
            section: section,
            contactIdentityId: item.contactIdentityId)
    }
}

struct ContactsScreen: View {
    @StateObject private var viewModel = ContactsViewModel()
    @State private var filterText = ""
    @State private var showingAddContact = false
    @State private var showingEnableDashPay = false
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
        VStack(spacing: 0) {
            if viewModel.needsDashPayEnable {
                enableDashPayBanner
            }
            if viewModel.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    /// Shown while the main identity lacks the DIP-15 contact-request key
    /// pair: without it, other users can't send this identity a contact
    /// request. Tapping opens the fee-confirm sheet.
    private var enableDashPayBanner: some View {
        Button(action: { showingEnableDashPay = true }) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 22))
                    .foregroundColor(.dash.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Enable DashPay", comment: "DashPay: add the identity keys other users need to send contact requests"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                    Text(NSLocalizedString("Your identity can't receive contact requests yet", comment: "DashPay: subtitle of the Enable DashPay banner"))
                        .font(.system(size: 13))
                        .foregroundColor(.dash.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.dash.secondaryText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingEnableDashPay) {
            EnableDashPayConfirmSheet(viewModel: viewModel)
                .presentationDetents([.height(360)])
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

// MARK: - EnableDashPayConfirmSheet

/// Fee-confirm sheet for the "Enable DashPay" banner: explains that
/// confirming adds the contact-request key pair to the identity via one
/// IdentityUpdate, shows the schedule-derived fee estimate in DASH and
/// local currency, and hands off to the PIN gate on confirm. The
/// transition is paid from the identity's credit balance.
private struct EnableDashPayConfirmSheet: View {
    @ObservedObject var viewModel: ContactsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.2.badge.key.fill")
                .font(.system(size: 34))
                .foregroundColor(.dash.blue)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.dash.blue.opacity(0.08)))
                .padding(.top, 28)

            Text(NSLocalizedString("Enable DashPay", comment: "DashPay: add the identity keys other users need to send contact requests"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
                .padding(.top, 16)

            Text(NSLocalizedString(
                "This adds two keys to your identity so other users can send you contact requests, and so you can accept theirs. It happens once, on the Dash Platform network.",
                comment: "DashPay: body of the Enable DashPay confirmation"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            HStack {
                Text(NSLocalizedString("Estimated network fee", comment: "DashPay: fee line of the Enable DashPay confirmation"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
                Spacer()
                Text(viewModel.enableDashPayEstimatedCostText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .multilineTextAlignment(.trailing)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.dash.secondaryBackground))
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Text(NSLocalizedString("Paid from your identity's credit balance.", comment: "DashPay: fee source note of the Enable DashPay confirmation"))
                .font(.system(size: 12))
                .foregroundColor(.dash.tertiaryText)
                .padding(.top, 6)

            Spacer(minLength: 12)

            Button(action: {
                dismiss()
                viewModel.enableDashPay()
            }) {
                Text(NSLocalizedString("Enable", comment: "DashPay: confirm button of the Enable DashPay sheet"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dash.blue)
                    .cornerRadius(12)
            }
            .disabled(viewModel.isEnablingDashPay)
            .padding(.horizontal, 20)

            Button(action: { dismiss() }) {
                Text(NSLocalizedString("Cancel", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.dash.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .background(Color.dash.primaryBackground)
    }
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
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if let secondary = secondaryLine {
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.tertiaryText)
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
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(1)
                if let username = item.username?.withoutDashSuffix, !username.isEmpty, username != item.displayTitle {
                    Text(username)
                        .font(.system(size: 12))
                        .foregroundColor(.dash.tertiaryText)
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

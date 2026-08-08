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
    /// identity a contact request. Drives the "Enable DashPay" intro.
    @Published var needsDashPayEnable = false
    @Published var isEnablingDashPay = false

    /// How many of the pair are missing (1 or 2 while
    /// `needsDashPayEnable`); sizes the fee estimate.
    private var missingDashPayKeyCount = 0

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
        missingDashPayKeyCount = service.missingDashPayKeyCount()
        needsDashPayEnable = missingDashPayKeyCount > 0
    }

    /// Estimated IdentityUpdate fee for the confirm sheet, sized to the
    /// keys actually missing: "~0.000131 DASH (≈ THB 0.13)" in the user's
    /// local currency.
    var enableDashPayEstimatedCostText: String {
        let duffs = SwiftDashSDKContactsService.enableDashPayEstimatedFeeDuffs(
            missingKeyCount: missingDashPayKeyCount)
        return String.localizedStringWithFormat(
            NSLocalizedString("~%@ DASH (≈ %@)", comment: "DashPay: estimated network fee — DASH amount, then its local-currency equivalent"),
            duffs.formattedDashAmountWithoutCurrencySymbol,
            CurrencyExchanger.shared.fiatAmountString(for: duffs.dashAmount))
    }

    /// True right after a successful enable — drives the one-off success
    /// sheet with the "Send your first contact request" CTA.
    @Published var showEnableSuccess = false

    /// PIN-gated IdentityUpdate adding the missing contact-request keys.
    /// On success the intro clears (Platform accepted the broadcast, or
    /// already had the keys) and the success sheet presents.
    func enableDashPay() {
        guard !isEnablingDashPay else { return }
        isEnablingDashPay = true
        Task {
            defer { isEnablingDashPay = false }
            do {
                _ = try await service.enableDashPay()
                missingDashPayKeyCount = 0
                needsDashPayEnable = false
                showEnableSuccess = true
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
    /// Set by the success sheet's CTA; consumed on its dismissal to open
    /// the add-contact sheet.
    @State private var pendingFirstContactRequest = false
    @State private var selectedContact: ContactItem? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.dash.primaryBackground.ignoresSafeArea()
                content
            }
            .navigationTitle(viewModel.needsDashPayEnable
                ? NSLocalizedString("DashPay", comment: "DashPay")
                : NSLocalizedString("Contacts", comment: "DashPay Contacts"))
            .toolbar {
                // Adding a contact needs the DIP-15 key pair on our own
                // side too (the outgoing request's ECDH) — hide the
                // affordance until the identity is DashPay-enabled.
                if !viewModel.needsDashPayEnable {
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
            }
            .sheet(isPresented: $showingAddContact) {
                AddContactScreen()
            }
            .sheet(
                isPresented: $viewModel.showEnableSuccess,
                onDismiss: {
                    // Chain into the add-contact sheet only after this one
                    // is fully gone — presenting both at once drops the
                    // second.
                    if pendingFirstContactRequest {
                        pendingFirstContactRequest = false
                        showingAddContact = true
                    }
                }
            ) {
                EnableDashPaySuccessSheet(onSendFirstRequest: {
                    pendingFirstContactRequest = true
                    viewModel.showEnableSuccess = false
                })
                // .medium can clip at large Dynamic Type sizes; the sheet
                // content scrolls and .large stays reachable.
                .presentationDetents([.medium, .large])
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
        if viewModel.needsDashPayEnable {
            // Until the identity has its contact-key pair the tab is the
            // DashPay pitch: what it is, why enable it, and the one CTA.
            // The contacts UI (and its add affordances) appear only once
            // requests can actually be exchanged.
            DashPayIntroView(
                viewModel: viewModel,
                showingEnableDashPay: $showingEnableDashPay)
                .sheet(isPresented: $showingEnableDashPay) {
                    EnableDashPayConfirmSheet(viewModel: viewModel)
                        // .medium can clip at large Dynamic Type sizes; the
                        // sheet content scrolls and .large stays reachable.
                        .presentationDetents([.medium, .large])
                }
        } else if viewModel.isEmpty {
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

// MARK: - DashPayIntroView

/// The Contacts tab's pre-enable takeover: pitches DashPay, links the
/// FAQ, and carries the single Enable CTA. Shown while the main identity
/// lacks the DIP-15 contact-key pair (it can neither send nor receive
/// contact requests until then).
private struct DashPayIntroView: View {
    @ObservedObject var viewModel: ContactsViewModel
    @Binding var showingEnableDashPay: Bool
    @State private var showingFAQ = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.dash.blue)
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(Color.dash.blue.opacity(0.08)))
                        .padding(.top, 12)

                    Text(NSLocalizedString("Pay people, not addresses", comment: "DashPay intro: headline"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.dash.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)

                    Text(NSLocalizedString(
                        "DashPay replaces long cryptic addresses with usernames. Add friends as contacts, send money to a name, and keep every payment organized by person.",
                        comment: "DashPay intro: pitch paragraph"))
                        .font(.system(size: 15))
                        .foregroundColor(.dash.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)

                    VStack(spacing: 14) {
                        featureRow(
                            icon: "at",
                            title: NSLocalizedString("Usernames, not addresses", comment: "DashPay intro: feature title"),
                            body: NSLocalizedString("Send to a username you can actually remember and verify.", comment: "DashPay intro: feature body"))
                        featureRow(
                            icon: "lock.shield.fill",
                            title: NSLocalizedString("Private payments", comment: "DashPay intro: feature title"),
                            body: NSLocalizedString("Private payment addresses are exchanged between you and your contacts. Only you and your contact know the recipient and sender of payments between yourselves.", comment: "DashPay intro: feature body"))
                        featureRow(
                            icon: "clock.arrow.circlepath",
                            title: NSLocalizedString("Your history, organized", comment: "DashPay intro: feature title"),
                            body: NSLocalizedString("Payments with each contact are grouped in one place, with names and profiles instead of raw transactions.", comment: "DashPay intro: feature body"))
                        featureRow(
                            icon: "sparkles",
                            title: NSLocalizedString("Coming soon", comment: "DashPay intro: feature title"),
                            body: NSLocalizedString("Private contact requests, Shielded DashPay, and paying people who aren't contacts yet.", comment: "DashPay intro: coming-soon body"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Button {
                        showingFAQ = true
                    } label: {
                        Text(NSLocalizedString("Learn More", comment: "DashPay intro: opens the FAQ"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.dash.blue)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }
            }

            Button {
                showingEnableDashPay = true
            } label: {
                Text(NSLocalizedString("Enable DashPay", comment: "DashPay: add the identity keys other users need to send contact requests"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dash.blue)
                    .cornerRadius(12)
            }
            .disabled(viewModel.isEnablingDashPay)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showingFAQ) {
            DashPayFAQSheet()
        }
    }

    private func featureRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.dash.blue)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.dash.blue.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(.dash.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.dash.secondaryBackground))
    }
}

// MARK: - DashPayFAQSheet

/// "Learn More" FAQ for the DashPay intro: what DashPay is, why enabling
/// is needed, privacy, cost, and what's coming next.
private struct DashPayFAQSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        let question: String
        let answer: String

        /// Identity must be stable across body re-evaluations (a fresh
        /// `UUID()` per rebuild makes ForEach discard the rows and their
        /// DisclosureGroups collapse mid-read); the question text is
        /// unique and constant.
        var id: String { question }
    }

    private var items: [Item] {
        [
            Item(
                question: NSLocalizedString("What is DashPay?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "DashPay is Dash's social payments experience, built on Dash Platform. You register a username, add other users as contacts, and pay them by name — no more copying addresses.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("Why do I need to enable it?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "Your identity needs an encryption and a decryption key so contact requests can be encrypted between you and other users. Enabling adds whichever of them are missing with a single network transaction. This is a one time event.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("How private is DashPay?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "Payments are private: the addresses you exchange with a contact travel inside an encrypted payload only the two of you can read, and are never published — so your payments aren't trivially linkable to your username. They are still regular transparent-chain payments, though: sophisticated chain analysis might leak information. Shielded DashPay (coming soon) will close that gap. Contact requests themselves are currently NOT private: anyone can see that two identities are connected. Private contact requests are a feature coming soon. Your username and profile are also public on Dash Platform.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("When will contact requests become private?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "Private contact requests are in development and expected around September–October 2026. Today the request itself is public — anyone can see that two identities are connected, even though the payment details inside it are encrypted. Once private contact requests ship, you will have the choice of having your friendship be public or private.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("How does this compare to Bitcoin in terms of privacy?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "On Bitcoin there is no name layer, so people share and reuse addresses out in the open — once an address is known, everything it ever received is linkable to its owner. With DashPay your username is public, but it never points at a payment address: addresses are exchanged privately per contact and rotate, so paying by name doesn't publish where your money goes. Both are transparent chains, so chain analysis still applies to the coins themselves.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("How does this compare to Ethereum Accounts in terms of privacy?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "An Ethereum account is one reusable address: your entire balance and payment history sit publicly under it, and a name (like an ENS domain) typically points straight at that address for anyone to resolve. DashPay is the opposite shape — the name resolves to an identity, not a payment address, and actual payment addresses stay inside encrypted contact exchanges, fresh for each contact.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("What about Unstoppable Domains and similar name services?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "Name services like Unstoppable Domains map a human-readable name to a fixed public address on-chain. Anyone can resolve the name and see every payment ever made to it. A DashPay username never publicly resolves to a payment address — addresses are revealed only inside the encrypted exchange with each contact, so your name and your money stay unlinked to outside observers.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("What does it cost?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "Enabling DashPay costs a small one-time network fee, paid from your identity's credit balance. The exact estimate is shown before you confirm. Sending contact requests and payments costs the usual network fees.",
                    comment: "DashPay FAQ")),
            Item(
                question: NSLocalizedString("What's coming next?", comment: "DashPay FAQ"),
                answer: NSLocalizedString(
                    "Private contact requests (so who you connect with stays private), Shielded DashPay — contact payments from your private Shielded balance — and paying users who aren't in your contacts yet are all coming soon.",
                    comment: "DashPay FAQ")),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        DisclosureGroup {
                            Text(item.answer)
                                .font(.system(size: 14))
                                .foregroundColor(.dash.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        } label: {
                            Text(item.question)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.dash.primaryText)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.dash.secondaryBackground))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color.dash.primaryBackground)
            .navigationTitle(NSLocalizedString("About DashPay", comment: "DashPay FAQ title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - EnableDashPaySuccessSheet

/// Shown once, right after the enable IdentityUpdate succeeds: confirms
/// the identity can now exchange contact requests and offers the first
/// action. The CTA dismisses this sheet and chains into AddContactScreen
/// via the presenter's onDismiss.
private struct EnableDashPaySuccessSheet: View {
    let onSendFirstRequest: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Scrollable so every action stays reachable at large Dynamic
        // Type sizes.
        ScrollView {
            successContent
        }
        .background(Color.dash.primaryBackground)
    }

    private var successContent: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.dash.green)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.dash.green.opacity(0.1)))
                .padding(.top, 28)

            Text(NSLocalizedString("DashPay enabled", comment: "DashPay: title of the enable success sheet"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.dash.primaryText)
                .padding(.top, 16)

            Text(NSLocalizedString(
                "You're all set. Other users can now send you contact requests — and you can send yours.",
                comment: "DashPay: body of the enable success sheet"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            Button(action: onSendFirstRequest) {
                Text(NSLocalizedString("Send your first contact request", comment: "DashPay: CTA of the enable success sheet"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.dash.whiteText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.dash.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("Not now", comment: "DashPay: dismiss button of the enable success sheet"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.dash.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
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
        // Scrollable so every action stays reachable at large Dynamic
        // Type sizes.
        ScrollView {
            confirmContent
        }
        .background(Color.dash.primaryBackground)
    }

    private var confirmContent: some View {
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
                "This adds the missing keys to your identity so other users can send you contact requests, and so you can accept theirs. This is a one time event.",
                comment: "DashPay: body of the Enable DashPay confirmation"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Estimated network fee", comment: "DashPay: fee line of the Enable DashPay confirmation"))
                    .font(.caption)
                    .foregroundColor(.dash.secondaryText)
                Text(viewModel.enableDashPayEstimatedCostText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

            Button {
                dismiss()
                viewModel.enableDashPay()
            } label: {
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
            .padding(.top, 20)

            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("Cancel", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.dash.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
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

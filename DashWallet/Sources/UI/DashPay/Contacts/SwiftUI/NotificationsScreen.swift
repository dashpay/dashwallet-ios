//
//  NotificationsScreen.swift
//  DashWallet
//
//  DashPay notifications (migration Row #18 phase 4) — SwiftUI
//  replacement for `DWNotificationsViewController` +
//  `DWNotificationsProvider`'s Core Data aggregation. Visual design
//  mirrors the Android dash-wallet notifications screen
//  (fragment_notifications.xml /
//  notification_contact_request_received_row.xml): gray background,
//  a search field over the list, one white rounded container holding
//  all rows, "New" / "Earlier" section labels (15pt semibold), request
//  rows with 36pt avatar, 14pt body text, timestamp line
//  ("26 May 2023, 9:45" format), and the light-blue Accept pill +
//  round ignore inline.
//

import SwiftUI
import DashUIKit

struct NotificationsScreen: View {
    /// Debounce before a typed query is applied to the list, matching
    /// the network-search debounce the contacts screens use.
    private static let searchDebounceNanoseconds: UInt64 = 350_000_000

    @StateObject private var viewModel = ContactsViewModel()
    @State private var selectedContact: ContactItem? = nil

    let onBack: () -> Void

    /// Read-state captured once at screen entry so rows don't jump
    /// between sections while the user is looking at them; the marker
    /// itself advances on exit (`markViewed`).
    @State private var lastViewedAtEntry: Date = .distantPast

    /// The search field's live text.
    @State private var searchText = ""
    /// The query the list is filtered by — trails `searchText` by the
    /// debounce so the list doesn't churn on every keystroke.
    @State private var appliedSearchQuery = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                NavigationBar(
                    leading: {
                        NavigationBarElement.back.button {
                            markViewed()
                            onBack()
                        }
                    },
                    central: {
                        Text(NSLocalizedString("Notifications", comment: "DashPay Notifications"))
                            .font(.subheadMedium)
                            .foregroundColor(.dash.primaryText)
                    }
                )

                content
            }
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
        .onAppear {
            lastViewedAtEntry = DWGlobalOptions.sharedInstance().mostRecentViewedNotificationDate ?? .distantPast
            viewModel.refresh()
        }
        .onDisappear {
            markViewed()
        }
        // Backgrounding while this screen is frontmost is an exit too —
        // the app may never come back to run `.onDisappear`.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            markViewed()
        }
    }

    /// Marks everything on screen viewed: advances the read-state marker
    /// and (through the service's injected seam) clears the tray's dashpay
    /// thread and the store's dashpay seen-state. Idempotent — the marker
    /// only moves forward — so firing from every exit path (back button,
    /// `.onDisappear`, backgrounding) is harmless.
    private func markViewed() {
        SwiftDashSDKContactsService.shared.markNotificationsViewed()
    }

    // MARK: Events

    private enum EventKind: Hashable {
        /// Pending incoming request — actionable.
        case incomingRequest
        /// Pending outgoing request we sent — awaiting their acceptance.
        case sentRequest
        /// Established because they reciprocated our request.
        case theyAccepted
        /// Established because we accepted their request.
        case weAccepted
    }

    private struct Event: Identifiable {
        struct ID: Hashable {
            let contactIdentityId: Data
            let kind: EventKind
        }

        let item: ContactItem
        let kind: EventKind
        var id: ID {
            ID(
                contactIdentityId: item.contactIdentityId,
                kind: kind)
        }
        var date: Date { item.createdAt }
    }

    private var events: [Event] {
        let requests = viewModel.incomingRequests.map { Event(item: $0, kind: .incomingRequest) }
        let sent = viewModel.outgoingRequests.map { Event(item: $0, kind: .sentRequest) }
        let established = viewModel.contacts.map { item -> Event in
            Event(item: item, kind: item.establishedByTheirAccept ? .theyAccepted : .weAccepted)
        }
        return (requests + sent + established).sorted { $0.date > $1.date }
    }

    /// Events surviving the applied search query (`ContactItem
    /// .matches(searchQuery:)` — the same predicate the contacts screen
    /// filters with). An empty query keeps everything.
    private var filteredEvents: [Event] {
        events.filter { $0.item.matches(searchQuery: appliedSearchQuery) }
    }

    private var newEvents: [Event] { filteredEvents.filter { $0.date > lastViewedAtEntry } }
    private var earlierEvents: [Event] { filteredEvents.filter { $0.date <= lastViewedAtEntry } }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if events.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bell")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(.dash.tertiaryText)
                Text(NSLocalizedString("You have no notifications", comment: "DashPay Notifications"))
                    .font(.system(size: 14))
                    .foregroundColor(.dash.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Android parity: the search field shows whenever there
                    // are notifications, filtering by the row's title.
                    ContactsSearchField(
                        placeholder: NSLocalizedString("Search notifications", comment: "DashPay Notifications"),
                        text: $searchText)
                        .padding(.horizontal, 15)
                        .padding(.top, 12)

                    if !newEvents.isEmpty {
                        sectionHeader(NSLocalizedString("New", comment: "DashPay Notifications"))
                        rowsCard(newEvents)
                    }
                    if !earlierEvents.isEmpty {
                        sectionHeader(NSLocalizedString("Earlier", comment: "DashPay Notifications"))
                        rowsCard(earlierEvents)
                    }
                    if filteredEvents.isEmpty {
                        noSearchResults
                    }
                    Spacer(minLength: 24)
                }
            }
            .refreshable { await viewModel.syncNow() }
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(newValue)
            }
        }
    }

    /// Debounced hand-off from the field text to the applied query.
    /// Clearing applies immediately — the full list must come straight
    /// back when the ✕ empties the field.
    private func scheduleSearch(_ text: String) {
        searchDebounceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            appliedSearchQuery = ""
            return
        }
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.searchDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            appliedSearchQuery = text
        }
    }

    /// Under a query that matched nothing the sections both hide;
    /// say so instead of leaving a blank page.
    private var noSearchResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.dash.tertiaryText)
            Text(NSLocalizedString("No notifications match your search", comment: "DashPay Notifications"))
                .font(.system(size: 14))
                .foregroundColor(.dash.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.dash.primaryText)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    /// Android puts the rows in one white rounded container per section.
    private func rowsCard(_ events: [Event]) -> some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                row(for: event)
                if event.id != events.last?.id {
                    Divider().padding(.leading, 61)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dash.secondaryBackground))
        .padding(.horizontal, 15)
    }

    @ViewBuilder
    private func row(for event: Event) -> some View {
        switch event.kind {
        case .incomingRequest:
            notificationRow(
                event,
                text: String(
                    format: NSLocalizedString("%@ has sent you a contact request", comment: "DashPay Notifications"),
                    event.item.displayTitle)
            ) {
                if viewModel.processingIds.contains(event.item.contactIdentityId) {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass").font(.system(size: 12))
                        Text(NSLocalizedString("Accepting", comment: "DashPay Contacts"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.dashGolden)
                } else {
                    AcceptPillButton { viewModel.accept(event.item) }
                    IgnoreCircleButton { viewModel.ignore(event.item) }
                }
            }
            .onAppear { viewModel.resolveUsernameIfNeeded(event.item) }
        case .sentRequest:
            notificationRow(
                event,
                text: String(
                    format: NSLocalizedString("You sent a contact request to %@", comment: "DashPay Notifications"),
                    event.item.displayTitle)
            ) {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass").font(.system(size: 12))
                    Text(NSLocalizedString("Pending", comment: "DashPay Contacts"))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.dashGolden)
            }
            .onAppear { viewModel.resolveUsernameIfNeeded(event.item) }
        case .theyAccepted:
            notificationRow(
                event,
                text: String(
                    format: NSLocalizedString("%@ accepted your contact request", comment: "DashPay Notifications"),
                    event.item.displayTitle)
            ) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.dashGreen)
            }
        case .weAccepted:
            notificationRow(
                event,
                text: String(
                    format: NSLocalizedString("You added %@ as a contact", comment: "DashPay Notifications"),
                    event.item.displayTitle)
            ) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.dashGreen)
            }
        }
    }

    /// Android notification_contact_request_received_row: avatar 36,
    /// two-line body (14pt), timestamp line, trailing accessory.
    private func notificationRow<Accessory: View>(
        _ event: Event,
        text: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ContactAvatarView(
                title: event.item.displayTitle,
                avatarURL: event.item.avatarURL,
                identitySeed: event.item.contactIdentityId)
                .padding(.leading, 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.dash.primaryText)
                    .lineLimit(2)
                Text(Self.timestampFormatter.string(from: event.date))
                    .font(.system(size: 11))
                    .foregroundColor(.dash.secondaryText)
            }
            Spacer()
            accessory()
                .padding(.trailing, 15)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { selectedContact = event.item }
    }

    /// Android format: "26 May 2023, 9:45".
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, H:mm"
        return formatter
    }()
}

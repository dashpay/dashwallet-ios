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
//  one white rounded container holding all rows, "New" / "Earlier"
//  section labels (15pt semibold), request rows with 36pt avatar,
//  14pt body text, timestamp line ("26 May 2023, 9:45" format), and
//  the light-blue Accept pill + round ignore inline.
//

import SwiftUI
import DashUIKit

struct NotificationsScreen: View {
    @StateObject private var viewModel: NotificationsViewModel
    @State private var selectedContact: ContactItem? = nil

    /// The default is `nil`, not a freshly built view model: a default
    /// argument is evaluated in the caller's context, which is not the main
    /// actor, and `NotificationsViewModel` is `@MainActor`. Constructing it
    /// inside `StateObject`'s autoclosure defers that to view installation,
    /// which is on the main actor. Previews pass one in.
    init(viewModel: NotificationsViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? NotificationsViewModel())
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()
            content
        }
        .navigationTitle(NSLocalizedString("Notifications", comment: "DashPay Notifications"))
        .navigationBarTitleDisplayMode(.inline)
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
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
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
                    if !viewModel.newEvents.isEmpty {
                        sectionHeader(NSLocalizedString("New", comment: "DashPay Notifications"))
                        rowsCard(viewModel.newEvents)
                    }
                    if !viewModel.earlierEvents.isEmpty {
                        sectionHeader(NSLocalizedString("Earlier", comment: "DashPay Notifications"))
                        rowsCard(viewModel.earlierEvents)
                    }
                    Spacer(minLength: 24)
                }
            }
            .refreshable { await viewModel.syncNow() }
        }
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
    private func rowsCard(_ events: [NotificationsViewModel.Event]) -> some View {
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
    private func row(for event: NotificationsViewModel.Event) -> some View {
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
                    .foregroundColor(Color.dash.orange)
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
                .foregroundColor(Color.dash.orange)
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
                    .foregroundColor(Color.dash.green)
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
                    .foregroundColor(Color.dash.green)
            }
        }
    }

    /// Android notification_contact_request_received_row: avatar 36,
    /// two-line body (14pt), timestamp line, trailing accessory.
    private func notificationRow<Accessory: View>(
        _ event: NotificationsViewModel.Event,
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

#if DEBUG

/// Seeded feed, no contacts service behind it — see
/// `NotificationsViewModel.preview(new:earlier:)`. The screen must not be
/// given the production view model here: building one wakes
/// `SwiftDashSDKContactsService.shared`, which does real work in its
/// initializer.
#Preview("Feed") {
    NavigationStack {
        NotificationsScreen(viewModel: .preview(
            new: [
                .init(item: .preview(title: "briantest63a"), kind: .incomingRequest),
                .init(item: .preview(title: "s22test63b"), kind: .theyAccepted),
            ],
            earlier: [
                .init(item: .preview(title: "Upsilon2"), kind: .sentRequest),
                .init(item: .preview(title: "Delta"), kind: .weAccepted),
            ]))
    }
}

#Preview("Empty") {
    NavigationStack {
        NotificationsScreen(viewModel: .preview())
    }
}

#endif

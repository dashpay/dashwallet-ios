//
//  NotificationsScreen.swift
//  DashWallet
//
//  DashPay notifications: every contact request sent, received and accepted,
//  split into days.
//

import SwiftUI
import DashUIKit

/// The same rows and day headings as the contact activity card, over the
/// whole address book rather than one contact — the events are the same
/// events, and a user who reads them on a contact's sheet should recognise
/// them here.
///
/// Read state is no longer a section split. It survives as the dot on unread
/// rows; the bell badge keeps reading it from the service
/// (`unreadNotificationCount`), which never depended on this screen's layout.
struct NotificationsScreen: View {
    @StateObject private var viewModel: NotificationsViewModel
    @State private var sheetTarget: ContactTarget? = nil

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
        .sheet(item: $sheetTarget) { target in
            if let contacts = viewModel.contacts {
                ContactSheetPresenter(target: target, viewModel: contacts)
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
                    .foregroundStyle(Color.dash.tertiaryText)
                Text(NSLocalizedString("You have no notifications", comment: "DashPay Notifications"))
                    .dashFont(.footnote)
                    .foregroundStyle(Color.dash.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                // Lazy is safe here, unlike in the activity card: this is a
                // real scroll view, so offscreen days genuinely need not be
                // built, and nothing measures the stack's ideal height.
                LazyVStack(spacing: 20) {
                    ForEach(viewModel.days) { day in
                        VStack(spacing: 4) {
                            dayHeader(day)

                            ForEach(day.elements) { event in
                                row(event)
                                    .contentShape(.rect)
                                    // Nothing to open without the contacts
                                    // view model the sheet is driven by,
                                    // which only a preview lacks.
                                    .onTapGesture {
                                        guard viewModel.contacts != nil else { return }
                                        sheetTarget = .contact(event.item)
                                    }
                                    .onAppear { viewModel.resolveUsernameIfNeeded(event.item) }
                            }
                        }
                        .modifier(DashUIKit.MenuViewModifier())
                    }
                }
                .padding(20)
            }
            .refreshable { await viewModel.syncNow() }
        }
    }

    /// Date on the left, weekday on the right — the contact activity card's
    /// heading.
    private func dayHeader(_ day: DayGrouping.Day<NotificationsViewModel.Event>) -> some View {
        HStack {
            Text(day.id)
                .dashFont(.footnoteMedium)
                .foregroundStyle(Color.dash.primaryText)

            Spacer()

            Text(DWDateFormatter.sharedInstance.dayOfWeek(from: day.date))
                .dashFont(.footnote)
                .foregroundStyle(Color.dash.tertiaryText)
        }
        // Matches the horizontal padding inside each row, so the heading
        // lines up with the text below it.
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func row(_ event: NotificationsViewModel.Event) -> some View {
        ContactActivityEventRow(
            kind: event.event.kind,
            date: event.date,
            counterparty: event.item.displayTitle,
            // The avatar replaces the state symbol: this feed mixes people,
            // so whose event it is matters more than which kind it is.
            avatar: .init(
                title: event.item.displayTitle,
                url: event.item.avatarURL,
                identitySeed: event.item.contactIdentityId),
            isUnread: event.isUnread,
            accessory: accessory(for: event))
    }

    /// Only a pending incoming request can be acted on; the rest of the feed
    /// is a record of what already happened.
    private func accessory(for event: NotificationsViewModel.Event) -> AnyView? {
        switch event.event.kind {
        case .requestReceived where event.item.relationship == .incoming:
            if viewModel.processingIds.contains(event.item.contactIdentityId) {
                return AnyView(
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass").font(.system(size: 12))
                        Text(NSLocalizedString("Accepting", comment: "DashPay Contacts"))
                            .dashFont(.caption2)
                    }
                    .foregroundStyle(Color.dash.orange))
            }
            return AnyView(
                HStack(spacing: 8) {
                    AcceptPillButton { viewModel.accept(event.item) }
                    IgnoreCircleButton { viewModel.ignore(event.item) }
                })

        case .requestSent where event.item.relationship == .outgoing:
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "hourglass").font(.system(size: 12))
                    Text(NSLocalizedString("Pending", comment: "DashPay Contacts"))
                        .dashFont(.caption2)
                }
                .foregroundStyle(Color.dash.orange))

        case .weAccepted, .theyAccepted:
            return AnyView(
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.dash.green))

        // A request that has since been answered: the acceptance below it
        // carries the outcome, so this row needs no marker of its own.
        case .requestReceived, .requestSent:
            return nil
        }
    }
}

#if DEBUG

/// Seeded feed, no contacts service behind it — see
/// `NotificationsViewModel.preview(events:)`. The screen must not be given
/// the production view model here: building one wakes
/// `SwiftDashSDKContactsService.shared`, which does real work in its
/// initializer.
#Preview("Feed") {
    NavigationStack {
        NotificationsScreen(viewModel: .preview(events: [
            .preview(title: "briantest63a", kind: .requestReceived,
                     relationship: .incoming, isUnread: true),
            .preview(title: "s22test63b", kind: .theyAccepted, isUnread: true),
            // The request that this contact's acceptance answered — no
            // pending marker, because it is no longer pending.
            .preview(title: "s22test63b", kind: .requestSent, daysAgo: 1),
            .preview(title: "Upsilon2", kind: .requestSent,
                     relationship: .outgoing, daysAgo: 3),
            .preview(title: "Delta", kind: .weAccepted, daysAgo: 12),
        ]))
    }
}

#Preview("Empty") {
    NavigationStack {
        NotificationsScreen(viewModel: .preview())
    }
}

#endif

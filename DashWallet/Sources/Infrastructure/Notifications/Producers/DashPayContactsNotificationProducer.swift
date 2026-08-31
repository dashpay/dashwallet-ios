//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if DASHPAY

import Combine
import Foundation
import UserNotifications

/// Posts a notification per new pending incoming contact request and per
/// contact who accepted one of our requests.
///
/// Signal: `SwiftDashSDKContactsService.contactsDidChangeNotification`,
/// posted after every published-snapshot rebuild (the SDK's 15 s DashPay
/// sync loop lands the rows). Each signal triggers a scan of the current
/// snapshots; the store dedup on the identity-scoped ids
/// ("contact.request.<id>" / "contact.accepted.<id>") IS the new-vs-known
/// detector — no second seen-set.
///
/// Replay guard (same thinking as `TransactionNotificationProducer`): a
/// freshly synced identity replays its whole request history, and none of
/// it may notify. Only events created within the freshness window AND newer
/// than the bell's read marker
/// (`DWGlobalOptions.mostRecentViewedNotificationDate`) are news.
@MainActor
final class DashPayContactsNotificationProducer {
    /// An event must have been created at most this long ago to notify.
    static let freshnessWindow: TimeInterval = 10 * 60

    /// The two contact snapshots a scan reads — a value type so tests can
    /// feed synthetic items without the contacts service singleton.
    struct ContactsSnapshot {
        /// Pending incoming requests (they asked us).
        let incomingRequests: [ContactItem]
        /// Established (mutual) contacts.
        let contacts: [ContactItem]
    }

    private let dispatcher: NotificationDispatcher
    private let store: NotifiedEventStoring
    private let snapshot: @MainActor () -> ContactsSnapshot
    /// The bell's read marker: events at or before it were already viewed
    /// on the notifications screen and are not news.
    private let lastViewedDate: () -> Date?
    private let appState: AppStateProvider
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()

    init(dispatcher: NotificationDispatcher,
         store: NotifiedEventStoring,
         snapshot: @escaping @MainActor () -> ContactsSnapshot = {
             let service = SwiftDashSDKContactsService.shared
             return ContactsSnapshot(incomingRequests: service.incomingRequests, contacts: service.contacts)
         },
         lastViewedDate: @escaping () -> Date? = { DWGlobalOptions.sharedInstance().mostRecentViewedNotificationDate },
         appState: AppStateProvider = UIApplicationStateProvider(),
         now: @escaping () -> Date = Date.init) {
        self.dispatcher = dispatcher
        self.store = store
        self.snapshot = snapshot
        self.lastViewedDate = lastViewedDate
        self.appState = appState
        self.now = now
    }

    /// Subscribes to the contacts-changed signal. Idempotent; called once
    /// by `NotificationsBootstrap`. Passive until the contacts service is
    /// alive — the default snapshot closure only touches the singleton
    /// once a change signal has fired, which requires the service to exist.
    func start() {
        guard cancellables.isEmpty else { return }
        NotificationCenter.default.publisher(for: SwiftDashSDKContactsService.contactsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.scanAndNotify() }
            }
            .store(in: &cancellables)
    }

    /// One pass over the current snapshots: per-item notification
    /// decisions out. The store resolves overlapping scans, so each event
    /// posts at most once no matter how many change signals see it.
    func scanAndNotify() async {
        let current = snapshot()
        let cutoff = now().addingTimeInterval(-Self.freshnessWindow)
        let lastViewed = lastViewedDate() ?? .distantPast

        for item in current.incomingRequests {
            await process(
                item,
                eventDate: item.createdAt,
                id: "contact.request.\(item.contactIdentityId.hexEncodedString())",
                bodyFormat: NSLocalizedString("%@ has sent you a contact request", comment: "DashPay Notifications"),
                cutoff: cutoff,
                lastViewed: lastViewed)
        }

        for item in current.contacts where item.establishedByTheirAccept {
            // For established pairs `createdAt` is the reciprocation time —
            // the moment they accepted.
            await process(
                item,
                eventDate: item.createdAt,
                id: "contact.accepted.\(item.contactIdentityId.hexEncodedString())",
                bodyFormat: NSLocalizedString("%@ accepted your contact request", comment: "DashPay Notifications"),
                cutoff: cutoff,
                lastViewed: lastViewed)
        }
    }

    // MARK: Private

    private func process(_ item: ContactItem,
                         eventDate: Date,
                         id: String,
                         bodyFormat: String,
                         cutoff: Date,
                         lastViewed: Date) async {
        // Replay guard: historical events (initial identity sync) and
        // events the user already viewed on the notifications screen are
        // not news. Both checks are deterministic per event, so dropped
        // events need no store record to stay dropped.
        guard eventDate >= cutoff, eventDate > lastViewed else { return }

        // App-state policy: in the foreground the bell badge updates live,
        // so the event is consumed — a later scan (relaunch, next sync
        // pass) cannot post what the user was watching arrive.
        if appState.isApplicationActive {
            await store.consume(id: id, topic: .dashpay)
            return
        }

        await dispatcher.post(AppNotification(
            id: id,
            topic: .dashpay,
            title: nil,
            // `displayTitle` is the same resolution the notifications
            // screen renders (alias > profile name > username > truncated
            // identity id).
            body: String(format: bodyFormat, item.displayTitle),
            sound: .default,
            route: .dashPayNotifications,
            // Suppressed while frontmost: the bell already shows it.
            foregroundBehavior: .suppress))
    }
}

#endif

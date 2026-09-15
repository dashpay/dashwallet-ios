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

import Foundation
import UserNotifications

// MARK: - CrowdNodeResultNotifying

/// The seam `CrowdNode` posts its result/error messages through.
/// `CrowdNode.shared` is created before the notifications graph exists, so
/// `NotificationsBootstrap` injects the implementation statically
/// (`CrowdNode.notificationProducer`) instead of adding another global.
///
/// The caller-side policy stays with the caller: `CrowdNode.notifyIfNeeded`
/// keeps its `showNotificationOnResult` guard (set by the CrowdNode screens
/// around user-visible operations), so only messages that pass it reach
/// this seam.
protocol CrowdNodeResultNotifying: AnyObject {
    /// Fire-and-forget: posts a one-shot CrowdNode result or error message.
    func postResult(message: String)
}

// MARK: - CrowdNodeNotificationProducer

/// Translates CrowdNode result/error messages into `AppNotification`s —
/// the dispatcher-backed replacement for the `UNMutableNotificationContent`
/// code that used to live inline in `CrowdNode.notifyIfNeeded`.
///
/// Identity: these messages are one-shot UX events (signup finished,
/// address confirmed, operation failed) with no natural content identity,
/// and every message the guard lets through is news — but only the latest
/// one is worth a banner. `handleError` fires on every API error, so a
/// retrying operation produces a run of them. Every result is therefore
/// posted under one stable identifier (`resultNotificationID`): the
/// notification center replaces the delivered banner instead of stacking
/// one per retry, and the store holds at most one CrowdNode row, so the
/// badge counts one unseen result rather than one per retry.
///
/// That id would make the store drop every message after the first as a
/// duplicate, so each post first re-arms it (`unmark`), serialized with the
/// post that follows so two results cannot race for the same row. If the
/// permission gate then drops the post, the previous row stays deleted —
/// its banner, if any, was already delivered and nothing new is posted.
/// Notifications delivered under the legacy "CrowdNode" id keep their
/// tap-fold to `.staking` in `NotificationLifecycle`.
///
/// Post-grant catch-up: none, on purpose. A message the dispatcher dropped
/// while authorization was `.notDetermined` has no source to rescan and is
/// discarded rather than queued — the CrowdNode screen that ran the
/// operation shows its outcome inline, and a "signup finished" banner
/// arriving minutes later, after the user has moved on, would be noise
/// rather than news. The other producers (transactions, swaps, contacts)
/// rescan their persisted rows on the grant instead.
final class CrowdNodeNotificationProducer: CrowdNodeResultNotifying {
    /// The request identifier and store id every CrowdNode result shares.
    static let resultNotificationID = "crowdnode.result"

    private let dispatcher: NotificationDispatcher
    /// The dispatcher's store, for re-arming `resultNotificationID`.
    private let store: NotifiedEventStoring
    /// Orders each re-arm with the post that follows it.
    private let posts = NotificationSerialQueue()

    init(dispatcher: NotificationDispatcher, store: NotifiedEventStoring) {
        self.dispatcher = dispatcher
        self.store = store
    }

    // MARK: CrowdNodeResultNotifying

    func postResult(message: String) {
        Task { await post(message: message) }
    }

    /// The awaitable body of `postResult` — behavior parity with the
    /// legacy inline posting: `.crowdnode` topic, `.staking` route, default
    /// sound, banner in the foreground.
    @discardableResult
    func post(message: String) async -> Bool {
        let notification = AppNotification(
            id: Self.resultNotificationID,
            topic: .crowdnode,
            title: nil,
            body: message,
            sound: .default,
            route: .staking,
            foregroundBehavior: .banner)
        return await posts.run { [store, dispatcher] in
            // The previous result's row, seen or not, gives way to this one.
            await store.unmark(id: Self.resultNotificationID)
            return await dispatcher.post(notification)
        }
    }
}

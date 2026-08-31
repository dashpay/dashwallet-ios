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
/// so each post gets an event-scoped id ("crowdnode.result.<UUID>") and the
/// store dedup is a deliberate no-op for them — every message the guard
/// lets through is news. The previous fixed "CrowdNode" id made the store
/// swallow every message after the first one as a duplicate; already-
/// delivered notifications under that legacy id keep their tap-fold to
/// `.staking` in `NotificationLifecycle`.
final class CrowdNodeNotificationProducer: CrowdNodeResultNotifying {
    private let dispatcher: NotificationDispatcher
    /// Event-scoped id per post; injectable so tests can pin it.
    private let makeEventId: () -> String

    init(dispatcher: NotificationDispatcher,
         makeEventId: @escaping () -> String = { "crowdnode.result.\(UUID().uuidString)" }) {
        self.dispatcher = dispatcher
        self.makeEventId = makeEventId
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
            id: makeEventId(),
            topic: .crowdnode,
            title: nil,
            body: message,
            sound: .default,
            route: .staking,
            foregroundBehavior: .banner)
        return await dispatcher.post(notification)
    }
}

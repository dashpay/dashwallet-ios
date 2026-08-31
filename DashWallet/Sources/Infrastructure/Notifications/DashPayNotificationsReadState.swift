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

import Foundation

/// Pure read-state arithmetic for the DashPay notification bell.
/// `SwiftDashSDKContactsService` delegates its `unreadNotificationCount` /
/// `markNotificationsViewed` decisions here so the logic is testable without
/// the singleton's SwiftData/SDK graph.
///
/// The event universe is exactly what the notifications screen renders:
/// pending incoming requests, pending outgoing requests, and established
/// contacts (each `ContactItem.createdAt` is the event's date). The marker
/// is `DWGlobalOptions.mostRecentViewedNotificationDate` — events at or
/// before it were already viewed on the screen.
enum DashPayNotificationsReadState {
    /// Events newer than the last-viewed marker, across all three lists —
    /// the number the bell badge shows. A `nil` marker (fresh install)
    /// counts everything.
    static func unreadCount(incoming: [ContactItem],
                            outgoing: [ContactItem],
                            contacts: [ContactItem],
                            lastViewed: Date?) -> Int {
        let marker = lastViewed ?? .distantPast
        return [incoming, outgoing, contacts].joined()
            .filter { $0.createdAt > marker }
            .count
    }

    /// The value viewing the screen advances the marker to: the newest
    /// event date currently shown (mirrors the legacy model, which tracked
    /// the max displayed item date rather than `Date()` — future-dated
    /// events stay unread). Returns `nil` when there is nothing to advance
    /// to — no events at all, or the marker already at/past the newest —
    /// so the marker can never move backward.
    static func advancedMarker(incoming: [ContactItem],
                               outgoing: [ContactItem],
                               contacts: [ContactItem],
                               lastViewed: Date?) -> Date? {
        guard let newest = [incoming, outgoing, contacts].joined().map(\.createdAt).max() else {
            return nil
        }
        return newest > (lastViewed ?? .distantPast) ? newest : nil
    }
}

#endif

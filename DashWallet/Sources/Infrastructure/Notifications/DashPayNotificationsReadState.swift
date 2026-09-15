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
/// contacts (each `ContactItem.createdAt` is the event's date).
///
/// Read-state is the set of events the screen has shown
/// (`DWGlobalOptions.viewedNotificationEventKeys`), not a date. A date
/// marker cannot be exact here: it is advanced to the newest event on
/// screen, which can be our own outgoing request, while an incoming request
/// carries the SENDER's Platform timestamp — one arriving after the viewing
/// can be dated behind the marker and would never count as unread. The
/// legacy date marker (`mostRecentViewedNotificationDate`) is still the
/// answer for an install that has not recorded any keys yet, so an upgrade
/// does not re-badge what the user already saw.
enum DashPayNotificationsReadState {
    /// Bound on the recorded set; past it, keys of events no longer rendered
    /// are dropped (the ones on screen are always kept).
    static let viewedKeysLimit = 500

    /// Stable identity of one rendered event: which list, which
    /// counterparty, and the row's timestamp — a request re-sent later
    /// carries a new timestamp and is a new event.
    static func eventKey(for item: ContactItem) -> String {
        let list: String
        switch item.relationship {
        case .incoming: list = "incoming"
        case .outgoing: list = "outgoing"
        case .established: list = "established"
        }
        let millis = Int64((item.createdAt.timeIntervalSince1970 * 1000).rounded())
        return "\(list).\(item.contactIdentityId.hexEncodedString()).\(millis)"
    }

    /// Whether the screen has not shown this event yet. `viewedKeys == nil`
    /// means nothing was ever recorded, which falls back to the legacy date
    /// marker; a `nil` marker too (fresh install) counts it unread.
    static func isUnread(_ item: ContactItem, lastViewed: Date?, viewedKeys: Set<String>?) -> Bool {
        if let viewedKeys {
            return !viewedKeys.contains(eventKey(for: item))
        }
        return item.createdAt > (lastViewed ?? .distantPast)
    }

    /// Unread events across all three lists — the number the bell badge shows.
    static func unreadCount(incoming: [ContactItem],
                            outgoing: [ContactItem],
                            contacts: [ContactItem],
                            lastViewed: Date?,
                            viewedKeys: Set<String>?) -> Int {
        [incoming, outgoing, contacts].joined()
            .filter { isUnread($0, lastViewed: lastViewed, viewedKeys: viewedKeys) }
            .count
    }

    /// The set viewing the screen records: every event currently rendered,
    /// added to what was recorded before. Added rather than replaced, so a
    /// viewing while a snapshot is mid-rebuild (lists briefly empty) cannot
    /// wipe the record and re-badge everything; past `viewedKeysLimit` the
    /// set is pruned to the events still rendered.
    static func recordingViewed(incoming: [ContactItem],
                                outgoing: [ContactItem],
                                contacts: [ContactItem],
                                previous: Set<String>?) -> Set<String> {
        let shown = Set([incoming, outgoing, contacts].joined().map(eventKey(for:)))
        let recorded = shown.union(previous ?? [])
        return recorded.count > viewedKeysLimit ? shown : recorded
    }

    /// The value viewing the screen advances the legacy date marker to —
    /// still kept current so a build without the key set reads a sane
    /// marker. The newest
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

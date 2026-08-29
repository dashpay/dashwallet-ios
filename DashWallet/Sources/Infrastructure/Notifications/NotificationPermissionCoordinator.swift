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

// MARK: - NotificationPermissionState

/// Effective notification permission, derived from two independent facts:
/// the in-app toggle and the live OS authorization.
enum NotificationPermissionState: Equatable {
    /// The user wants notifications and the OS has granted them.
    case on
    /// The user wants notifications but the OS authorization is still
    /// `.notDetermined` — iOS silently ignores requests until the grant
    /// lands, so the dispatcher must drop WITHOUT consuming the dedup id
    /// (the event stays postable once authorization arrives). UI renders
    /// this like `.on`: the toggle reflects the user's choice.
    case awaitingAuthorization
    /// The in-app toggle is off; nothing is posted.
    case offByUser
    /// The OS authorization is denied. Only iOS Settings can change that, so
    /// UI renders an "open iOS Settings" affordance instead of a lying toggle.
    case blockedBySystem
}

// MARK: - NotificationPreferenceStore

/// Storage seam for the in-app toggle.
protocol NotificationPreferenceStore: AnyObject {
    var userWantsNotifications: Bool { get set }
}

/// Production storage: the legacy `DWGlobalOptions.localNotificationsEnabled`
/// slot (`LOCAL_NOTIFICATIONS_ENABLED_KEY`), kept for upgrade continuity.
final class GlobalOptionsNotificationPreferenceStore: NotificationPreferenceStore {
    var userWantsNotifications: Bool {
        get { DWGlobalOptions.sharedInstance().localNotificationsEnabled }
        set { DWGlobalOptions.sharedInstance().localNotificationsEnabled = newValue }
    }
}

// MARK: - NotificationPermissionCoordinator

/// Owns the two permission facts and their combination. The facts never
/// write each other: the toggle changes only on explicit user action, and
/// the OS grant is read live on every query (never cached, never mirrored
/// into the toggle — that mirror is what used to silently re-enable
/// notifications the user had switched off). The coordinator itself is
/// stateless, so independent instances always agree.
final class NotificationPermissionCoordinator {
    private let client: UserNotificationCenterClient
    private let preferences: NotificationPreferenceStore

    init(client: UserNotificationCenterClient = SystemUserNotificationCenterClient(),
         preferences: NotificationPreferenceStore = GlobalOptionsNotificationPreferenceStore()) {
        self.client = client
        self.preferences = preferences
    }

    /// The in-app Settings toggle.
    var userWantsNotifications: Bool {
        get { preferences.userWantsNotifications }
        set { preferences.userWantsNotifications = newValue }
    }

    /// Invoked on the main thread when `requestAuthorizationIfNeeded`'s
    /// request returns granted. The composition root hooks the post-grant
    /// catch-up here (a producer rescan), so events the dispatcher dropped
    /// un-marked while the state was `.awaitingAuthorization` get their
    /// post. Never invoked on denial or failure.
    var onAuthorizationGranted: (() -> Void)?

    func effectiveState() async -> NotificationPermissionState {
        // OS denial wins over the toggle: the Settings row must offer the
        // way out (iOS Settings) even while the in-app toggle is off.
        let status = await client.authorizationStatus()
        if status == .denied {
            return .blockedBySystem
        }
        guard preferences.userWantsNotifications else {
            return .offByUser
        }
        // `.notDetermined` means the app simply hasn't asked yet (the
        // home-screen visit prompts). The toggle stays meaningful, but the
        // OS ignores posted requests until the grant lands — the distinct
        // state lets the dispatcher drop without consuming dedup ids.
        return status == .notDetermined ? .awaitingAuthorization : .on
    }

    /// The registration path the home screen triggers on appearance. iOS
    /// shows its permission prompt only while authorization is not yet
    /// determined; any later call reports the current grant without UI.
    /// The will/did-request signals bracket the call either way, so
    /// `DWWindow` keeps suppressing its privacy blur during the alert.
    /// Must be called on the main thread (`DWWindow` asserts it).
    func requestAuthorizationIfNeeded() {
        NotificationCenter.default.post(name: .willRequestOSPermission, object: nil)
        Task { [client, weak self] in
            var granted = false
            var failure: Error?
            do {
                granted = try await client.requestAuthorization(options: [.badge, .sound, .alert])
            } catch {
                failure = error
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .didRequestOSPermission, object: nil)
                if granted {
                    self?.onAuthorizationGranted?()
                }
            }
            DWLogger.log("NotificationPermissionCoordinator: authorization request result \(granted), error \(String(describing: failure))")
        }
    }
}

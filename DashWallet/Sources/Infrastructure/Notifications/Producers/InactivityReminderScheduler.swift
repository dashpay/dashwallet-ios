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
import UIKit
import UserNotifications

// MARK: - InactivityReminderActionHandling

/// The inactivity notification's category actions, dispatched back from
/// `NotificationLifecycle.didReceive` by action identifier.
@MainActor
protocol InactivityReminderActionHandling: AnyObject {
    /// "Remind me later": restart the 30-day countdown from now.
    func handleRemindLater()
    /// "Don't remind me again": persist the opt-out and drop any pending
    /// reminder.
    func handleOptOut()
}

// MARK: - InactivityReminderPreferenceStore

/// Storage seam for the reminder opt-out.
protocol InactivityReminderPreferenceStore: AnyObject {
    var isOptedOut: Bool { get set }
    /// Whether the wallet was last seen holding funds. Latched by the
    /// scheduler from balances it knows to be real; see
    /// `DWGlobalOptions.inactivityReminderWalletHadBalance`.
    var walletHadBalance: Bool { get set }
}

/// Production storage: a `DWGlobalOptions` dynamic property — the reminder
/// opt-out is an app-global user preference exactly like the notification
/// toggle stored there, and the shared defaults slot keeps it in the one
/// place the app already reads preferences from (no parallel UserDefaults
/// key namespace).
final class GlobalOptionsInactivityReminderPreferenceStore: InactivityReminderPreferenceStore {
    var isOptedOut: Bool {
        get { DWGlobalOptions.sharedInstance().inactivityReminderDisabled }
        set { DWGlobalOptions.sharedInstance().inactivityReminderDisabled = newValue }
    }

    var walletHadBalance: Bool {
        get { DWGlobalOptions.sharedInstance().inactivityReminderWalletHadBalance }
        set { DWGlobalOptions.sharedInstance().inactivityReminderWalletHadBalance = newValue }
    }
}

// MARK: - InactivityReminderScheduler

/// Schedules the "you still have funds" reminder ~30 days after the app is
/// backgrounded (Android `BootstrapReceiver.maybeShowInactivityNotification`
/// parity): every `didEnterBackground` with a positive balance replaces the
/// pending request; every `didBecomeActive` cancels it, so the countdown
/// restarts on the next backgrounding and only genuine inactivity fires it.
///
/// This is the one component that talks to the `UserNotificationCenterClient`
/// directly instead of going through `NotificationDispatcher`: the
/// dispatcher's contract is immediate delivery of an event that happened,
/// with `NotifiedEventStore` dedup and unseen-badge accounting — a
/// scheduled future reminder has no event behind it, must be re-scheduled
/// under the same id every time (dedup would swallow the replacement), and
/// must never count as unseen while it is merely pending. The permission
/// gate is applied here explicitly instead.
@MainActor
final class InactivityReminderScheduler {
    /// Also the replacement key: `UNUserNotificationCenter` replaces a
    /// pending request when another is added under the same identifier.
    nonisolated static let requestIdentifier = "system.inactivity"

    /// How far out the reminder fires after the app leaves the foreground.
    nonisolated static let reminderDelay: TimeInterval = 30 * 24 * 60 * 60

    nonisolated static let remindLaterActionIdentifier = "org.dash.notification.inactivity.remind-later"
    nonisolated static let optOutActionIdentifier = "org.dash.notification.inactivity.opt-out"

    private let client: UserNotificationCenterClient
    private let permissions: NotificationPermissionCoordinator
    private let preferences: InactivityReminderPreferenceStore
    /// Total wallet balance in duffs, or `nil` while the live balance has
    /// not loaded yet — NOT zero. "Remind me later" is registered without
    /// `.foreground`, so acting on it can cold-launch the app in the
    /// background and reach `scheduleReminder()` before the runtime has
    /// published a balance; collapsing that to zero silently scheduled
    /// nothing, and the reminder that prompted it had already fired.
    private let totalBalance: () -> UInt64?
    /// Last known "this wallet held funds", persisted per wallet — the
    /// fallback for the unknown case above. `BalanceModel` writes it on
    /// every balance it renders.
    private let hadBalance: () -> Bool
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []

    init(client: UserNotificationCenterClient,
         permissions: NotificationPermissionCoordinator,
         preferences: InactivityReminderPreferenceStore = GlobalOptionsInactivityReminderPreferenceStore(),
         totalBalance: @escaping () -> UInt64? = { SwiftDashSDKWalletState.shared.balance?.total },
         hadBalance: @escaping () -> Bool = { DWGlobalOptions.sharedInstance().userHasBalance },
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.permissions = permissions
        self.preferences = preferences
        self.totalBalance = totalBalance
        self.hadBalance = hadBalance
        self.now = now
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Subscribes to the app-lifecycle notifications. Idempotent; called
    /// once by `NotificationsBootstrap`.
    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.scheduleReminder() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // The user came back — the countdown restarts on the next
            // backgrounding.
            self.cancelPendingReminder()
        })
    }

    /// Replaces the pending reminder with one ~30 days out, unless the
    /// user opted out, notifications are off, or there is nothing to
    /// remind about (zero balance).
    func scheduleReminder() async {
        guard !preferences.isOptedOut else { return }
        guard await permissions.effectiveState() == .on else { return }
        // Skip only on a balance KNOWN to be empty. An unknown balance falls
        // back to the flag latched below, so a background cold launch from
        // "Remind me later" reschedules instead of silently dropping the
        // reminder.
        //
        // The fallback is this scheduler's OWN flag, not `userHasBalance`:
        // that one is written by `BalanceModel.reloadBalance`, which maps an
        // unavailable SDK balance to zero — a cold reminder-action launch
        // could therefore erase the eligibility it was about to read. This
        // flag only ever moves on a balance the SDK actually reported, and
        // `hadBalance()` seeds it for wallets that predate it.
        let known = totalBalance()
        if let known {
            preferences.walletHadBalance = known > 0
        } else if hadBalance() {
            // First run after the upgrade, with no balance to latch from:
            // adopt the legacy flag rather than start out ineligible.
            preferences.walletHadBalance = true
        }
        guard known.map({ $0 > 0 }) ?? preferences.walletHadBalance else { return }

        let content = UNMutableNotificationContent()
        // Deliberately no amount: this is delivered by the OS up to 30 days
        // later and shows in a lock-screen preview, where a passer-by would
        // read the wallet's total holdings without unlocking anything. The
        // user can also have "Autohide Balance" on, which every in-app
        // surface honours and a scheduled notification cannot.
        content.body = NSLocalizedString("It's been a while since you opened Dash Wallet.",
                                         comment: "Inactivity reminder")
        content.sound = .default
        content.threadIdentifier = NotificationTopic.system.rawValue
        content.categoryIdentifier = NotificationTopic.system.rawValue
        var userInfo: [String: Any] = [
            NotificationUserInfoKey.foregroundBehavior: NotificationForegroundBehavior.banner.rawValue,
        ]
        if let routeData = DeepLinkRoute.home.encodedForUserInfo() {
            userInfo[NotificationUserInfoKey.route] = routeData
        }
        content.userInfo = userInfo

        let fireDate = now().addingTimeInterval(Self.reminderDelay)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.requestIdentifier,
                                            content: content,
                                            trigger: trigger)
        do {
            try await client.add(request)
            DWLogger.log("InactivityReminderScheduler: reminder scheduled for \(fireDate)")
        } catch {
            DWLogger.log("InactivityReminderScheduler: scheduling failed: \(error)")
        }
    }

    /// Removes the pending reminder (delivered ones are none of this
    /// component's business — the user acts on those via the category
    /// actions).
    func cancelPendingReminder() {
        client.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
    }
}

// MARK: - InactivityReminderActionHandling

extension InactivityReminderScheduler: InactivityReminderActionHandling {
    func handleRemindLater() {
        Task { await scheduleReminder() }
    }

    func handleOptOut() {
        preferences.isOptedOut = true
        cancelPendingReminder()
    }
}

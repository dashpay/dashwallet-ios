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

// MARK: - BackgroundTaskHost

/// Seam over the two `UIApplication` background-task calls, so the hold can
/// be driven without a running application.
@MainActor
protocol BackgroundTaskHost: AnyObject {
    func beginBackgroundTask(withName name: String?,
                             expirationHandler: (() -> Void)?) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

// MARK: - UIApplication + BackgroundTaskHost

extension UIApplication: BackgroundTaskHost { }

// MARK: - BackgroundGraceHold

/// Keeps the process running for a short grace period after the user leaves
/// the app, so a payment landing in those seconds is still seen by the live
/// SPV client — and still notified about.
///
/// Without this iOS suspends the process almost immediately on
/// backgrounding: the peer connections die mid-flight, no signal reaches
/// `TransactionNotificationProducer`, and the only remaining path is
/// `BackgroundRefreshCoordinator`'s BGAppRefresh, which the system may run
/// minutes or hours later (and refuses outright in the simulator). "I
/// backgrounded the app and sent myself a payment" is the single most
/// common way both users and QA check notifications, and it is exactly the
/// window this covers.
///
/// The hold is bounded and self-cancelling: it ends after `duration`, on
/// the system's expiration handler, or as soon as the app comes back — the
/// same task is never held across a foreground visit.
@MainActor
final class BackgroundGraceHold {
    /// How long the process is kept alive after backgrounding. iOS grants
    /// roughly 30 s to a plain background task; staying under that means
    /// the hold always ends on our own terms rather than being killed.
    static let duration: TimeInterval = 25

    private let host: BackgroundTaskHost
    /// The in-app toggle. A user who wants no notifications gets no
    /// background time spent on producing them.
    private let permissions: NotificationPermissionCoordinator
    /// Cancellable wait; injected so tests need no wall clock.
    private let wait: (TimeInterval) async -> Void

    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var expiry: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    init(host: BackgroundTaskHost = UIApplication.shared,
         permissions: NotificationPermissionCoordinator,
         wait: @escaping (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         }) {
        self.host = host
        self.permissions = permissions
        self.wait = wait
    }

    /// Installs the lifecycle observers. Idempotent; called once by
    /// `NotificationsBootstrap`.
    func start() {
        guard !started else { return }
        started = true
        DWLogger.log("BackgroundGraceHold: observing app lifecycle")

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.beginHold() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.endHold(reason: "foregrounded") }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Hold

    /// Takes the background task, unless the user wants no notifications or
    /// a hold is somehow already in flight.
    func beginHold() {
        // Both bails log: a hold that silently does nothing is exactly how
        // the sync gate hid itself.
        guard permissions.userWantsNotifications else {
            DWLogger.log("BackgroundGraceHold: skipped — notifications are off")
            return
        }
        guard identifier == .invalid else {
            DWLogger.log("BackgroundGraceHold: already holding")
            return
        }

        identifier = host.beginBackgroundTask(withName: "notifications-grace") { [weak self] in
            // The system is reclaiming the time it lent us; end before it
            // kills the process for overstaying.
            guard let self else { return }
            MainActor.assumeIsolated { self.endHold(reason: "expired") }
        }
        guard identifier != .invalid else {
            DWLogger.log("BackgroundGraceHold: background time refused")
            return
        }
        DWLogger.log("BackgroundGraceHold: holding for \(Int(Self.duration))s")

        expiry = Task { [weak self] in
            guard let wait = self?.wait else { return }
            await wait(Self.duration)
            guard !Task.isCancelled else { return }
            self?.endHold(reason: "elapsed")
        }
    }

    /// Releases the background task. Safe to call when nothing is held.
    func endHold(reason: String) {
        expiry?.cancel()
        expiry = nil
        guard identifier != .invalid else { return }
        DWLogger.log("BackgroundGraceHold: released (\(reason))")
        host.endBackgroundTask(identifier)
        identifier = .invalid
    }

    /// Whether background time is currently held — the test seam, and the
    /// answer `NotificationsBootstrap` would need if it ever coordinated
    /// with another background consumer.
    var isHolding: Bool { identifier != .invalid }
}

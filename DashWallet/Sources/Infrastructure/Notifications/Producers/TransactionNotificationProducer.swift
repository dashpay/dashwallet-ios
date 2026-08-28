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

import Combine
import CoreData
import Foundation
import UIKit
import UserNotifications

// MARK: - AppStateProvider

/// Seam over "is the app frontmost right now", so producers never read
/// `UIApplication.shared` themselves — a background-refresh task runs the
/// same producer code with no UI available and injects its own answer.
protocol AppStateProvider: AnyObject {
    /// True while the application state is `.active`. Backgrounded and
    /// inactive (app switcher, transition) both read false.
    var isApplicationActive: Bool { get }
}

/// Production provider over `UIApplication.shared.applicationState`, which
/// is main-actor state — reads called from a producer's background thread
/// hop to the main thread first (the same trampoline
/// `TransactionObserver.resolveHostHandles` uses).
final class UIApplicationStateProvider: AppStateProvider {
    var isApplicationActive: Bool {
        let read = { @MainActor () -> Bool in
            UIApplication.shared.applicationState == .active
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated { read() }
        }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { read() } }
    }
}

// MARK: - TransactionNotificationProducer

/// Translates newly persisted incoming transactions into `AppNotification`s
/// with per-transaction identity ("tx.<txid>") — replacing the retired
/// balance-delta inference of `DWBalanceNotifier`.
///
/// Observes the same signal funnel `HomeViewModel.observeWallet()` trusts
/// for new transactions: the SwiftData save notification (filtered to
/// `PersistentTransaction` inserts),
/// `.swiftDashSDKTransactionProjectionDidChange`, and
/// `.platformAddressActivityRecorded` (DIP-15 contact payments bypass the
/// SwiftData trigger). Each signal triggers a bounded rescan of recent rows;
/// the dispatcher's `NotifiedEventStore` guarantees one notification per
/// txid no matter how many signals, scans, or app launches see the row.
///
/// Lifetime: `NotificationsBootstrap` constructs it and calls `start()`
/// during `application(_:didFinishLaunching:)`, before the wallet runtime is
/// up. That is safe because every signal is a `NotificationCenter` name
/// (subscribing needs no SDK handle), rows only exist once the SDK's
/// persister writes them, and the replay guard below keeps initial sync,
/// restore, and rescan bursts from notifying.
final class TransactionNotificationProducer {
    /// A row must prove it is at most this recent to notify — together with
    /// the sync gate this is the replay guard (Android's `isReplayedTx`
    /// parity): initial sync, restore, and rescan write historical rows in
    /// bulk, and none of them may fire a notification.
    static let freshnessWindow: TimeInterval = 10 * 60

    /// Rows admitted per scan. The freshness floor already bounds the
    /// window; this guards a resync burst that lands many rows at once.
    static let scanFetchLimit = 100

    private let dispatcher: NotificationDispatcher
    private let store: NotifiedEventStoring
    /// Recent rows, given a `firstSeen` floor (epoch seconds).
    private let rowSource: (UInt64) -> [ObservedTransaction]
    private let syncState: () -> SyncingActivityMonitor.State
    private let appState: AppStateProvider
    /// Mirrors a posted notification's body to the Apple Watch app.
    private let watchBridge: (String) -> Void
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()

    init(dispatcher: NotificationDispatcher,
         store: NotifiedEventStoring,
         rowSource: @escaping (UInt64) -> [ObservedTransaction] = TransactionNotificationProducer.defaultRowSource,
         syncState: @escaping () -> SyncingActivityMonitor.State = { SyncingActivityMonitor.shared.state },
         appState: AppStateProvider = UIApplicationStateProvider(),
         watchBridge: @escaping (String) -> Void = TransactionNotificationProducer.defaultWatchBridge,
         now: @escaping () -> Date = Date.init) {
        self.dispatcher = dispatcher
        self.store = store
        self.rowSource = rowSource
        self.syncState = syncState
        self.appState = appState
        self.watchBridge = watchBridge
        self.now = now
    }

    // MARK: Signals

    /// Subscribes to the three signals. Idempotent; called once by
    /// `NotificationsBootstrap`.
    func start() {
        guard cancellables.isEmpty else { return }

        // The insert filter runs before any queue hop — the userInfo object
        // sets belong to the posting thread (the same rule
        // `HomeViewModel.observeWallet` follows for its save filter).
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { Self.saveInsertsTransactionRows($0) }
            .sink { [weak self] _ in self?.requestScan() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .swiftDashSDKTransactionProjectionDidChange)
            .sink { [weak self] _ in self?.requestScan() }
            .store(in: &cancellables)

        // The platform-address recorder writes the app's own SQLite —
        // invisible to the SwiftData save signal — so DIP-15 contact
        // payments arrive through this dedicated signal.
        NotificationCenter.default.publisher(for: .platformAddressActivityRecorded)
            .sink { [weak self] _ in self?.requestScan() }
            .store(in: &cancellables)
    }

    /// Hops off the signal's posting thread. Scans are not serialized
    /// against each other: overlapping scans posting the same row are
    /// resolved by the store's `markIfNew` (an actor), so exactly one post
    /// and one watch mirror happen per txid.
    private func requestScan() {
        Task { [weak self] in
            await self?.scanAndNotify()
        }
    }

    // MARK: Scanning

    /// One bounded pass: recent rows in, per-row notification decisions out.
    func scanAndNotify() async {
        // Replay guard, part 1: while sync is running the persister writes
        // historical rows in bulk and none of them may notify. Checked
        // before scanning at all — no row can pass, so don't fetch any.
        guard syncState() == .syncDone else { return }

        let cutoff = now().addingTimeInterval(-Self.freshnessWindow)
        let floor = UInt64(max(0, cutoff.timeIntervalSince1970))
        for row in rowSource(floor) {
            await process(row, cutoff: cutoff)
        }
    }

    private func process(_ tx: ObservedTransaction, cutoff: Date) async {
        // Incoming only — the SDK direction classifier is authoritative.
        // `.moved` (internal legs: shielded transfers, CoinJoin, self-sends)
        // and sends never notify.
        guard tx.wrapped.direction == .received else { return }

        // Replay guard, part 2: even after syncDone a scan can hand back old
        // rows, and the scan floor cannot vouch for rows whose timestamp
        // fell back to `blockTimestamp`. A row that cannot prove it is
        // fresh does not notify.
        guard let timestamp = tx.timestamp, timestamp >= cutoff else { return }

        let amount = tx.wrapped.dashAmount
        guard amount > 0 else { return }

        let notification = Self.notification(for: tx, amount: amount)

        // App-state policy, preserved from the balance-delta notifier: a
        // plain received payment posts only while the app is backgrounded
        // or inactive — the foreground feed is already showing it. The id
        // is still consumed in the store, so a later scan (relaunch,
        // background refresh) cannot post a payment the user watched
        // arrive. CrowdNode deposits post in every app state.
        if notification.topic != .crowdnode, appState.isApplicationActive {
            await store.consume(id: notification.id, topic: notification.topic)
            return
        }

        if await dispatcher.post(notification) {
            // The watch mirrors exactly the rows that produced a post.
            watchBridge(notification.body)
        }
    }

    /// Classification picks copy, topic, sound, and route only — the
    /// identity stays the txid, so a CrowdNode deposit still dedups per
    /// transaction like every other received payment.
    private static func notification(for tx: ObservedTransaction, amount: UInt64) -> AppNotification {
        let id = "tx.\(tx.txidHexDisplay)"

        // The CrowdNode API encodes "deposit received" as an exact amount
        // (apiOffset + code) paid back to the account.
        if amount == ApiCode.depositReceived.rawValue + CrowdNode.apiOffset {
            return AppNotification(
                id: id,
                topic: .crowdnode,
                title: nil,
                body: NSLocalizedString("Your deposit to CrowdNode is received.", comment: "CrowdNode"),
                sound: .default,
                route: .staking,
                foregroundBehavior: .banner)
        }

        let amountText = amount.formattedDashAmount
        let fiatText = CurrencyExchanger.shared.fiatAmountString(for: amount.dashAmount)
        return AppNotification(
            id: id,
            topic: .transactions,
            title: nil,
            body: String(format: NSLocalizedString("Received %@ (%@)", comment: ""), amountText, fiatText),
            // The bundled resource is "coinflip.aiff" — without the
            // extension the sound name does not resolve and iOS delivers
            // the notification silently.
            sound: UNNotificationSound(named: UNNotificationSoundName(rawValue: "coinflip.aiff")),
            route: .transactionDetail(txid: tx.txid),
            foregroundBehavior: .banner)
    }

    // MARK: Production defaults

    /// Whether a SwiftData save inserted `PersistentTransaction` rows — only
    /// inserts can carry a not-yet-notified transaction. Fails open on a
    /// save whose payload cannot be inspected (a redundant bounded scan is
    /// cheap and the store dedups), mirroring `HomeViewModel`'s save filter.
    static func saveInsertsTransactionRows(_ notification: Notification) -> Bool {
        guard let userInfo = notification.userInfo else { return true }
        guard let inserted = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return false }
        return inserted.contains { $0.entity.name == "PersistentTransaction" }
    }

    /// Production rows: `TransactionObserver`'s bounded SwiftData scan,
    /// which reads through its own `ModelContext` on the calling thread —
    /// never `mainContext` off-main. A thin pass-through left untested; the
    /// decisions made on the rows it returns are covered through the
    /// injected seam.
    static func defaultRowSource(firstSeenAtOrAfter floor: UInt64) -> [ObservedTransaction] {
        TransactionObserver.fetchObserved(fetchLimit: scanFetchLimit, firstSeenAtOrAfter: floor)
    }

    /// Sends a custom notification to the watch if the watch app is up.
    static func defaultWatchBridge(_ body: String) {
        #if !IGNORE_WATCH_TARGET
        DWPhoneWCSessionManager.sharedInstance().notifyTransactionString(body)
        #endif
    }
}

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
/// persister writes them, and the per-row replay guard below keeps initial
/// sync, restore, and rescan bursts from notifying.
final class TransactionNotificationProducer {
    /// A row must prove it is at most this recent to notify — this is the
    /// replay guard (Android's `isReplayedTx` parity): initial sync,
    /// restore, and rescan write historical rows in bulk, and none of them
    /// may fire a notification. What "recent" is measured against is the
    /// point `freshnessStamp(for:)` picks: for a mined row it is the
    /// block's own timestamp, which a replay cannot forge.
    static let freshnessWindow: TimeInterval = 10 * 60

    /// Hard floor for a catch-up boundary. A wallet left closed for weeks
    /// must not have its whole backlog announced the first time a refresh
    /// finally runs.
    static let maxCatchUpWindow: TimeInterval = 24 * 60 * 60

    /// Rows admitted per scan. The freshness floor already bounds the
    /// window; this guards a resync burst that lands many rows at once.
    static let scanFetchLimit = 100

    private let dispatcher: NotificationDispatcher
    private let store: NotifiedEventStoring
    /// Recent rows, given a `firstSeen` floor (epoch seconds).
    private let rowSource: (UInt64) -> [ObservedTransaction]
    /// Incoming Platform-address payments, which live in the app's own SQLite
    /// ledger rather than in SwiftData — `rowSource` cannot see them.
    private let platformActivitySource: (Date) -> [PlatformAddressActivityRecord]
    private let appState: AppStateProvider
    /// Mirrors a posted notification's body to the Apple Watch app.
    private let watchBridge: (String) -> Void
    /// The fiat half of the received-payment copy, for a DASH amount.
    private let fiatFormatter: (Decimal) async -> String
    private let now: () -> Date
    private var cancellables = Set<AnyCancellable>()

    init(dispatcher: NotificationDispatcher,
         store: NotifiedEventStoring,
         rowSource: @escaping (UInt64) -> [ObservedTransaction] = TransactionNotificationProducer.defaultRowSource,
         platformActivitySource: @escaping (Date) -> [PlatformAddressActivityRecord] =
             TransactionNotificationProducer.defaultPlatformActivitySource,
         appState: AppStateProvider = UIApplicationStateProvider(),
         watchBridge: @escaping (String) -> Void = TransactionNotificationProducer.defaultWatchBridge,
         fiatFormatter: @escaping (Decimal) async -> String = TransactionNotificationProducer.defaultFiatFormatter,
         now: @escaping () -> Date = Date.init) {
        self.dispatcher = dispatcher
        self.store = store
        self.rowSource = rowSource
        self.platformActivitySource = platformActivitySource
        self.appState = appState
        self.watchBridge = watchBridge
        self.fiatFormatter = fiatFormatter
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
    ///
    /// Deliberately not gated on `SyncingActivityMonitor`: dash-spv leaves
    /// `.syncDone` for every new block (see the "Synced is only a transient
    /// window" note in `SyncingActivityMonitor.handleCoordinatorUpdate`),
    /// and an incoming payment *is* what opens such a window — so a
    /// sync-state gate drops precisely the rows this producer exists for,
    /// with nothing rescanning once the state settles. The replay guard is
    /// per row instead.
    /// `since` widens the window for a catch-up scan: the background
    /// refresh runs no earlier than 15 minutes after backgrounding and iOS
    /// delays it further, so a payment mined two minutes after suspension is
    /// already outside the default 10-minute window by the time the sweep
    /// gets to run. The caller passes the persisted boundary
    /// (`DWGlobalOptions.notificationCatchUpDate`); the same value bounds
    /// both the fetch floor and the per-row freshness test, so the two
    /// cannot disagree.
    ///
    /// Historical-restore suppression is unaffected: a restored row is
    /// judged by `minedAt` (see `freshnessStamp`), which stays old however
    /// recent its `firstSeen` is, and the boundary is floored at
    /// `maxCatchUpWindow` so a long-dormant install cannot replay weeks.
    func scanAndNotify(since boundary: Date? = nil) async {
        let defaultCutoff = now().addingTimeInterval(-Self.freshnessWindow)
        let earliest = now().addingTimeInterval(-Self.maxCatchUpWindow)
        let cutoff = min(defaultCutoff, max(boundary ?? defaultCutoff, earliest))
        let floor = UInt64(max(0, cutoff.timeIntervalSince1970))
        let rows = rowSource(floor)
        // The `.platformAddressActivityRecorded` signal this producer
        // subscribes to is posted by `PlatformAddressActivityRecorder`, which
        // writes the app-owned activity ledger and creates NO
        // `PersistentTransaction` — so an incoming `dash1`/`tdash1` payment
        // woke the scan and was then absent from the rows it looked at.
        await scanPlatformActivity(cutoff: cutoff)
        guard !rows.isEmpty else { return }

        // One line per scan, not per row: a restore burst hands back up to
        // `scanFetchLimit` rows on every save signal.
        var outcomes: [Outcome: Int] = [:]
        for row in rows {
            outcomes[await process(row, cutoff: cutoff), default: 0] += 1
        }
        let tally = Outcome.allCases
            .compactMap { outcome in outcomes[outcome].map { "\(outcome.rawValue) \($0)" } }
            .joined(separator: ", ")
        DWLogger.log("TransactionNotificationProducer: scanned \(rows.count) recent row(s) — \(tally)")
    }

    /// The Platform half of a scan: incoming payments recorded against the
    /// wallet's Platform receive addresses.
    ///
    /// Identity is the ledger's own row id — append-only and stable, so the
    /// dispatcher's dedup holds across relaunches and a re-scan of the same
    /// window cannot post twice. Freshness is `observedAt`, which the
    /// recorder stamps when it first SEES the balance increase, so a restore
    /// that rebuilds baselines cannot backdate a payment into the window (it
    /// records nothing) and cannot replay one either.
    private func scanPlatformActivity(cutoff: Date) async {
        let records = platformActivitySource(cutoff)
        guard !records.isEmpty else { return }

        var posted = 0
        for record in records where record.amountDuffs > 0 && record.observedAt >= cutoff {
            let amount = UInt64(record.amountDuffs)
            let amountText = amount.formattedDashAmount
            let fiatText = await fiatFormatter(amount.dashAmount)
            let notification = AppNotification(
                id: "platform-activity.\(record.id)",
                topic: .transactions,
                title: nil,
                body: String(format: NSLocalizedString("Received %@ (%@)", comment: ""), amountText, fiatText),
                sound: UNNotificationSound(named: UNNotificationSoundName(rawValue: "coinflip.aiff")),
                // No txid to open: a Platform-address receive has no Core
                // transaction of its own, so this lands on the feed.
                route: .home,
                foregroundBehavior: .banner)

            // Same app-state policy as a received Core payment: consumed, not
            // dropped, so a later scan cannot re-post what the user watched
            // arrive in the foreground.
            if appState.isApplicationActive {
                await store.consume(id: notification.id, topic: notification.topic)
                continue
            }
            if await dispatcher.post(notification) {
                watchBridge(notification.body)
                posted += 1
            }
        }
        DWLogger.log("TransactionNotificationProducer: scanned \(records.count) platform activity row(s) — posted \(posted)")
    }

    /// What one row's pass decided, for the scan's log line.
    private enum Outcome: String, CaseIterable {
        case posted
        case notReceived = "not-received"
        case notFresh = "not-fresh"
        case zeroAmount = "zero-amount"
        /// Suppressed because the app is frontmost (and consumed, so a
        /// later scan cannot resurrect it).
        case appActive = "app-active"
        /// The dispatcher declined it — permission gate or already notified;
        /// it logs the reason itself.
        case dropped
    }

    @discardableResult
    private func process(_ tx: ObservedTransaction, cutoff: Date) async -> Outcome {
        // Incoming only — the SDK direction classifier is authoritative.
        // `.moved` (internal legs: shielded transfers, CoinJoin, self-sends)
        // and sends never notify.
        guard tx.wrapped.direction == .received else { return .notReceived }

        // Replay guard: a row that cannot prove it is fresh does not notify.
        guard let stamp = Self.freshnessStamp(for: tx), stamp >= cutoff else { return .notFresh }

        let amount = tx.wrapped.dashAmount
        guard amount > 0 else { return .zeroAmount }

        let notification = await notification(for: tx, amount: amount)

        // App-state policy, preserved from the balance-delta notifier: a
        // plain received payment posts only while the app is backgrounded
        // or inactive — the foreground feed is already showing it. The id
        // is still consumed in the store, so a later scan (relaunch,
        // background refresh) cannot post a payment the user watched
        // arrive. CrowdNode deposits post in every app state.
        if notification.topic != .crowdnode, appState.isApplicationActive {
            await store.consume(id: notification.id, topic: notification.topic)
            return .appActive
        }

        guard await dispatcher.post(notification) else { return .dropped }
        // The watch mirrors exactly the rows that produced a post.
        watchBridge(notification.body)
        return .posted
    }

    /// The point in time a row must prove is recent.
    ///
    /// A mined row is judged by its block's timestamp, never by `firstSeen`:
    /// restore and rescan persist historical transactions with a fresh
    /// device-clock `firstSeen`, so `firstSeen` cannot tell "just arrived"
    /// apart from "history replayed" — while consensus data can. A row that
    /// claims a block but carries no block timestamp proves nothing, so it
    /// is dropped (nil).
    ///
    /// An unmined row (mempool, or InstantSend-locked but not yet in a
    /// block) has no consensus stamp and needs none: it can only have
    /// entered the wallet's view just now, which is exactly the payment
    /// this producer notifies about.
    static func freshnessStamp(for tx: ObservedTransaction) -> Date? {
        if tx.blockHeight > 0 || tx.minedAt != nil {
            return tx.minedAt
        }
        return tx.timestamp
    }

    /// Classification picks copy, topic, sound, and route only — the
    /// identity stays the txid, so a CrowdNode deposit still dedups per
    /// transaction like every other received payment.
    private func notification(for tx: ObservedTransaction, amount: UInt64) async -> AppNotification {
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
        let fiatText = await fiatFormatter(amount.dashAmount)
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

    /// Production Platform activity: the active wallet's ledger rows on the
    /// current network, filtered to the scan window. Returns nothing when no
    /// wallet is resolved — a scan during teardown must not read another
    /// wallet's ledger.
    static func defaultPlatformActivitySource(since cutoff: Date) -> [PlatformAddressActivityRecord] {
        // Same resolution `SwiftDashSDKWalletSource.fetchPlatformActivity`
        // uses, through the same main-thread trampoline: the
        // handles are read on the main actor, the DAO's own SQLite connection
        // serializes the query from whatever executor the scan landed on.
        let handles: (walletId: Data, networkRaw: Int64)? = SwiftDashSDKWalletSource.onMain {
            guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                return nil
            }
            return (walletId, Int64(network.rawValue))
        }
        guard let handles else { return [] }
        return PlatformAddressActivityDAO.shared
            .activities(walletId: handles.walletId, networkRaw: handles.networkRaw)
            .filter { $0.observedAt >= cutoff }
    }

    /// Production fiat copy, formatted on the main actor. Scans run on
    /// whatever executor the signal's `Task` lands on, while
    /// `CurrencyExchanger` has no synchronization of its own: its rate
    /// tables are replaced by `BaseRatesProvider`'s update handler on the
    /// main actor, so reading them anywhere else races a rate refresh.
    /// (The retired balance notifier read them from `RunLoop.main` for the
    /// same reason.)
    static func defaultFiatFormatter(_ dashAmount: Decimal) async -> String {
        await MainActor.run {
            CurrencyExchanger.shared.fiatAmountString(for: dashAmount)
        }
    }

    /// Sends a custom notification to the watch if the watch app is up.
    static func defaultWatchBridge(_ body: String) {
        #if !IGNORE_WATCH_TARGET
        DWPhoneWCSessionManager.sharedInstance().notifyTransactionString(body)
        #endif
    }
}

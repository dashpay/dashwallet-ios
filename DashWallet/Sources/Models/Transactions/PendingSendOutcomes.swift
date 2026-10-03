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
import Foundation
import os
import SwiftDashSDK

/// Sends whose broadcast ended without a word from the network ("status
/// unknown"), followed until the network answers.
///
/// Such a send is handed back to the history instead of an error: its row
/// reads "Waiting for the network" until its stored row is InstantSend-locked
/// or mined, which moves it to "Sent" and raises a one-time notice. The SDK's
/// broadcast probe only prompts that check: an `.accepted` verdict means a
/// node took the bytes, not that the payment will settle, so it is never
/// shown as "Sent" on its own. An `.unresolved` verdict changes nothing.
///
/// A shared instance, not an injected one: the record has to outlive the send
/// screen that made it and be read by the history rows, the home notice and a
/// later send to the same address. It is persisted, so a relaunch keeps a send
/// waiting rather than turning it back into "Sending".
@objc(DWPendingSendOutcomes)
@MainActor
final class PendingSendOutcomes: NSObject, ObservableObject {
    @objc static let shared = PendingSendOutcomes()

    /// Posted on the main queue whenever a send starts or stops waiting, or
    /// the network is heard to have it — a history row's title changes
    /// without its stored row changing.
    nonisolated static let didChangeNotification = Notification.Name("PendingSendOutcomes.didChange")

    struct Entry: Codable, Equatable {
        /// 32 bytes, wire order (`Transaction.txHashData`).
        let txidWire: Data
        let walletId: Data
        /// Nil for a route that does not know the recipient's address.
        let address: String?
        let amount: UInt64
        let sentAt: Date
    }

    /// Sends that went through after all: one, or several that settled while
    /// an earlier notice was still up, told together. Each raise is a new `id`,
    /// so two payments of the same amount are two notices.
    struct Notice: Equatable {
        let id = UUID()
        let count: Int
        let total: UInt64
    }

    /// How long a notice stays up.
    static let noticeDuration: TimeInterval = 3

    @Published private(set) var entries: [Data: Entry] = [:]
    @Published private(set) var notice: Notice?
    private(set) var noticeRaisedAt: Date?

    /// Read by `Transaction.stateTitle`, which is not main-actor isolated.
    /// Mirrors `entries`, written only from the main actor.
    private nonisolated static let waitingTxids =
        OSAllocatedUnfairLock<Set<Data>>(initialState: [])

    private static let defaultsKey = "PendingSendOutcomes.entries.v1"
    /// A row that is still missing this long after its send is taken as gone
    /// (removed or swept) rather than not yet written by the persister.
    private static let missingRowGrace: TimeInterval = 60 * 60

    private var verdictWatch: AnyCancellable?
    private var saveWatch: AnyCancellable?
    private var reconcileInFlight = false
    private var reconcileRequestedAgain = false

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(stored.map { ($0.txidWire, $0) }, uniquingKeysWith: { a, _ in a })
        }
        publishWaitingTxids()
        // A save that touched the wallet's transactions may have locked or
        // mined a waiting send; the bookkeeping saves are skipped with the
        // home feed's filter (inspected on the posting thread, before the
        // hop). Throttled: during sync the persister saves several times a
        // second.
        saveWatch = NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .filter { HomeViewModel.saveTouchesFeedRows($0) }
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }
    }

    // MARK: - Recording

    /// The broadcast of `txidWire` ended with no answer from the network.
    /// Called by `WalletSendService` wherever it maps a broadcast to
    /// `broadcastUnknown`, and from nowhere else.
    ///
    /// - Returns: false when the send could not be followed (no active
    ///   wallet), so its row will not say "Waiting for the network".
    @discardableResult
    func recordUnknownOutcome(txidWire: Data, address: String?, amount: UInt64) -> Bool {
        guard let walletId = SwiftDashSDKHost.shared.wallet?.walletId else {
            DWLogger.log("💸 TXSEND :: unknown outcome not tracked, no active wallet")
            return false
        }
        entries[txidWire] = Entry(
            txidWire: txidWire,
            walletId: walletId,
            address: address,
            amount: amount,
            sentAt: Date())
        DWLogger.log("💸 TXSEND :: waiting for the network on \(Transaction.displayHex(txidWire))")
        didChangeEntries()
        reconcile()
        return true
    }

    /// Stop following `txidsWire` — their rows were removed by the user
    /// (`UnconfirmedTransactionRemover`).
    func forget(txidsWire: [Data]) {
        var changed = false
        for txid in txidsWire where entries.removeValue(forKey: txid) != nil {
            changed = true
            DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(txid)) removed, no longer tracked")
        }
        if changed { didChangeEntries() }
    }

    // MARK: - Reading

    /// Whether `txidWire` is a send still waiting for the network.
    nonisolated static func isWaiting(txidWire: Data) -> Bool {
        waitingTxids.withLock { $0.contains(txidWire) }
    }

    /// The newest send to `address` that the network has not confirmed yet,
    /// in the active wallet.
    func waitingPayment(to address: String) -> Entry? {
        let walletId = SwiftDashSDKHost.shared.wallet?.walletId
        return entries.values
            .filter { $0.address == address && $0.walletId == walletId }
            .max { $0.sentAt < $1.sentAt }
    }

    // MARK: - Verdicts

    /// Follow `manager`'s probe verdicts. Called for each manager the host
    /// configures; replaces the previous watch. Also settles, once, the sends
    /// that went through while the app was closed.
    func observeVerdicts(of manager: PlatformWalletManager) {
        reconcile()
        verdictWatch = manager.$outgoingTransactionVerdicts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] verdicts in
                MainActor.assumeIsolated { self?.apply(Array(verdicts.values)) }
            }
    }

    /// An `.accepted` verdict on a waiting send re-reads the stored rows: the
    /// lock or block that settles it may already be there. The verdict itself
    /// changes nothing — a node that took the bytes is not a settled payment.
    private func apply(_ events: [OutgoingTransactionProbeEvent]) {
        let heard = events.contains { event in
            event.verdict == .accepted && entries[event.txidWire]?.walletId == event.walletId
        }
        if heard { reconcile() }
    }

    // MARK: - Settling against the stored rows

    /// Drop the sends whose stored row is now InstantSend-locked or mined (or
    /// gone). Each one that settled raises the notice.
    private func reconcile() {
        guard !entries.isEmpty else { return }
        guard !reconcileInFlight else {
            reconcileRequestedAgain = true
            return
        }
        reconcileInFlight = true
        let pending = entries
        Task.detached(priority: .utility) { [weak self] in
            let snapshot = SwiftDashSDKWalletSource.fetch(txids: Set(pending.keys))
            await MainActor.run {
                guard let self else { return }
                if let snapshot {
                    self.settle(pending: pending, snapshot: snapshot)
                }
                self.reconcileInFlight = false
                if self.reconcileRequestedAgain {
                    self.reconcileRequestedAgain = false
                    self.reconcile()
                }
            }
        }
    }

    private func settle(pending: [Data: Entry], snapshot: SwiftDashSDKWalletTransactionSnapshot) {
        let rows = Dictionary(snapshot.transactions.map { ($0.txHashData, $0) },
                              uniquingKeysWith: { a, _ in a })
        var changed = false
        for entry in pending.values where entry.walletId == snapshot.walletId {
            if let row = rows[entry.txidWire] {
                guard row.state != .processing else { continue }
                DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(entry.txidWire)) settled on chain")
                raiseNotice(for: entry)
            } else {
                guard Date().timeIntervalSince(entry.sentAt) > Self.missingRowGrace else { continue }
                DWLogger.log("💸 TXSEND :: \(Transaction.displayHex(entry.txidWire)) left the wallet, no longer tracked")
            }
            entries.removeValue(forKey: entry.txidWire)
            changed = true
        }
        if changed { didChangeEntries() }
    }

    // MARK: - Private

    /// Clear `notice` if it is still the one with `id` — a notice raised
    /// meanwhile stays.
    func dismissNotice(id: UUID) {
        guard notice?.id == id else { return }
        notice = nil
    }

    private func raiseNotice(for entry: Entry) {
        let now = Date()
        if let current = notice,
           let raisedAt = noticeRaisedAt,
           now.timeIntervalSince(raisedAt) < Self.noticeDuration {
            let (total, overflow) = current.total.addingReportingOverflow(entry.amount)
            notice = Notice(count: current.count + 1, total: overflow ? UInt64.max : total)
        } else {
            notice = Notice(count: 1, total: entry.amount)
        }
        noticeRaisedAt = now
    }

    private func didChangeEntries() {
        publishWaitingTxids()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        if let data = try? JSONEncoder().encode(Array(entries.values)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func publishWaitingTxids() {
        let txids = Set(entries.keys)
        Self.waitingTxids.withLock { $0 = txids }
    }
}
